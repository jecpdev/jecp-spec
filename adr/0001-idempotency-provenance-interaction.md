# ADR-0001: Idempotency–Provenance Interaction

> **TL;DR for VPs of Eng**: JECP runs two separate caches — idempotency (so retries are safe) and replay defense (so stolen Mandates die fast). They look interchangeable but are not. Getting their key composition wrong silently bypasses replay defense on the second retry. This ADR records the decision: idempotency keys MUST include `mandate.provenance_hash`. The reference Hub does this; conformant Hubs must too.

## Status

Accepted (2026-05-10). Supersedes the informal note that lived in 01-protocol.md §5.2.2 of v1.0.1.

## Context

JECP §5 (01-protocol.md) mandates idempotent retries: same `(agent_id, request_id)` within a 24-hour window MUST return the cached response and MUST NOT re-charge. The motivation is well-trodden: networks lose responses; agents retry; charging twice is unacceptable. The reference Hub stores a `request_cache` row keyed by `(agent_id, id, input_hash)` and on cache hit returns the stored body verbatim — including its HTTP status, including any 4xx errors that were cached by design.

JECP §5.2 (02-authentication.md) mandates Provenance v2: every authenticated request that carries a `mandate.provenance_hash` includes a fresh, server-verifiable HMAC-SHA256 over `(agent_id, request_id, timestamp, nonce)`. The motivation here is also well-trodden: a Mandate captured on the wire is a bearer token; without binding the Mandate to a one-shot nonce, capture-and-replay is a complete authentication bypass.

These two MUSTs *interact*, and their interaction is the entire reason this ADR exists. A naive idempotency key of `(agent_id, request_id)` lets an attacker who has captured **one** valid Provenance hash replay it indefinitely against the cache. The cache returns a 200 without re-verification, the wallet is not re-debited, the webhook is not re-emitted — but the attacker has, in effect, learned a permanent replay token. The replay-defense layer fires on the *first* request and never sees the attacker's second one.

v1.0.1 errata H2 patched the reference Hub by mixing `mandate.provenance_hash` into the input hash that becomes the idempotency cache key. Concrete site: `jecp/src/routes/invoke.rs:543-549` and `jecp/src/routes/jecp.rs::compute_input_hash`. This ADR ratifies that patch as a normative requirement and documents the alternatives we considered and rejected.

## Decision

**The Hub's idempotency cache key is**

```
SHA-256(
  capability ||
  "|" || action ||
  "|" || canonical_json(input) ||
  "|" || (mandate.provenance_hash if present else "")
)
```

**Every request — even a replay with identical `(agent_id, request_id, capability, action, input)` — MUST pass full Provenance v2 verification (including replay-cache nonce registration) BEFORE the idempotency cache is consulted.** The order of operations on the request hot path is:

1. Authenticate `agent_id` + `api_key` (bcrypt verify).
2. Verify `mandate.provenance_hash` (HMAC + timestamp skew + nonce-cache check).
3. Compute the idempotency cache key per the formula above.
4. Look up; on hit, return the cached response body and HTTP status as-is.
5. On miss, execute the capability and store the response keyed by the same hash.

Cache hits MUST NOT re-charge the wallet, MUST NOT re-emit webhooks, and MUST NOT re-trigger Provider invocation. Cache TTL is 24 hours; conformant Hubs MAY use a shorter TTL but MUST NOT use less than 1 hour. Cache-key collisions (same `(agent_id, request_id)` with different content) are detected and reported as 409 `DUPLICATE_REQUEST` (per 03-errors.md §3.2 and RFC 9110 §15.5.10).

## Consequences

**Positive**

- A stolen `provenance_hash` cannot be replayed against the cache. The nonce-replay gate fires first (returns 403 `PROVENANCE_MISMATCH` with `details.subcause = nonce_replay`); the cache never sees the second observation.
- Two requests with the same `id` but different inputs deterministically yield 409 — no silent overwrite, no ambiguous failure mode.
- Providers receive at-most-once delivery within the 24-hour window for any unique `(agent, id, content, provenance)` tuple. This composes cleanly with at-least-once webhook semantics on the Hub-to-Provider hop.

**Negative**

- The cache key carries 64 bytes of provenance prefix on every entry. For agents that omit `mandate.provenance_hash` (Bronze-tier callers below the v2-required threshold), this is a `""` literal — minor overhead.
- Provenance verification cost (HMAC compute + replay-cache lookup) is paid on every retry, including idempotent replays from legitimate clients. Measured at ~50µs per request on the reference Hub. Acceptable.

## Alternatives Considered

**Alternative 1: Stripe-style idempotency key = `(agent_id, request_id)` only.**
Rejected. Stripe's idempotency keys are scoped to an authenticated session bound to one merchant — the merchant's API key authenticates the cache lookup itself. JECP keys are agent-supplied and traverse multiple Providers. Without binding to the per-call provenance, a leaked Mandate becomes a perpetual replay token — exactly the threat Provenance v2 was designed to neutralize. The Stripe pattern is correct for Stripe's threat model; it is wrong for JECP's.

**Alternative 2: Verify Provenance only on cache miss; cache hits skip verification.**
Rejected. This makes the cache itself the authentication boundary. An attacker who learns one cache key bypasses HMAC entirely. It inverts the spec's defense-in-depth posture: instead of "every request verifies, cache is for billing/safety", you get "cache is the auth layer, verification is for first-time requests". Once that inversion is shipped, you cannot un-ship it without breaking every client that has come to rely on the (incorrect) fast path.

**Alternative 3: Cache `(agent_id, request_id)` and hard-fail with 409 when input differs, but treat provenance as opaque.**
Rejected. The same nonce can be replayed across separate `(capability, action, input)` tuples — every replay creates a *new* cache row, so the 409 fence never fires against the attacker's varied payloads. Provenance MUST be inside the key, not beside it, for the cache to be a meaningful defense-in-depth boundary.

## Wire-format guarantee committed by this decision

For any sequence of requests R₁, R₂, ..., Rₙ to a v1.0-conformant Hub where ALL requests are syntactically valid AND share the tuple `(agent_id, request_id)`:

- If R₁ has a fresh nonce and a valid HMAC, R₁ is processed; R₂..Rₙ receive the cached body of R₁ **only if** `SHA-256(capability||"|"||action||"|"||input||"|"||provenance_hash)` matches R₁'s key, **else** they receive 409 `DUPLICATE_REQUEST`.
- If Rᵢ (where i ≥ 2) presents a duplicate nonce, Rᵢ MUST receive 403 `PROVENANCE_MISMATCH` with `details.subcause = nonce_replay`, regardless of cache state.
- The Agent's wallet is debited at most once per unique cache key. 409s and 403s do not debit.

## References

- [01-protocol.md §5 — Idempotency](../spec/01-protocol.md)
- [02-authentication.md §5.2 — Provenance v2](../spec/02-authentication.md)
- [02-authentication.md §5.2.2 — Idempotency–Provenance interaction](../spec/02-authentication.md) (cross-reference back to this ADR)
- [03-errors.md — DUPLICATE_REQUEST, PROVENANCE_MISMATCH](../spec/03-errors.md)
- Reference Hub source path: `jecp/src/routes/invoke.rs::compute_input_hash` (Hub implementation — open-source release pending)
- Reference Hub source path: `jecp/src/routes/jecp.rs` cache_lookup integration (Hub implementation — open-source release pending)
- Stripe Idempotency-Key documentation (anchor for Alternative 1)
- [RFC 9110 §9.2.2 — Idempotent Methods](https://datatracker.ietf.org/doc/html/rfc9110#section-9.2.2)
- v1.0.1 errata H2 — this ADR ratifies the patch
