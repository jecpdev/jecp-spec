# ADR-0004: Idempotency × x402

> **TL;DR for VPs of Eng**: ADR-0001 mandated that the Hub's idempotency cache key includes `mandate.provenance_hash` so a stolen Mandate can't be replayed against the cache. x402 introduces a second bearer-token-equivalent — the signed EIP-3009 `transferWithAuthorization` payload — and the same naive idempotency would let the same on-chain settlement be redeemed across multiple requests, OR drop a paid signature silently if the cache key ignores it. This ADR extends ADR-0001's input-hash composition with the SHA-256 of the X-Payment payload AND the resulting settlement `tx_hash`, and adds a dedicated `x402_settlements` table with UNIQUE constraints on both `(payer, eip3009_nonce)` AND `tx_hash`. Two-layer defense closes Panel 2 `TM-D2` (Critical replay) and `TM-S4` (cross-capability replay).

## Status

Accepted (2026-05-11). Extends [ADR-0001 — Idempotency × Provenance](./0001-idempotency-provenance-interaction.md).

## Context

ADR-0001 established that the Hub's idempotency cache key MUST include `mandate.provenance_hash` to defend against bearer-token replay. The reasoning generalizes: any field that authenticates a payment-for-this-call must be inside the cache key, or the cache becomes the auth boundary (Alternative 2 in ADR-0001).

x402 introduces two new authorization-of-payment fields on the request hot path:

1. The `X-Payment` header — base64-encoded EIP-3009 `transferWithAuthorization` envelope. Signed by the agent's wallet. Burns one EIP-3009 nonce per use.
2. The settlement `tx_hash` — produced by the facilitator's `/settle` call. Recorded on-chain, irreversible.

Both behave like the `provenance_hash` from ADR-0001's perspective: they are bearer-token-equivalent (anyone holding the value can present it as proof of payment), and the wallet path's "you paid once, you get one cached response" invariant has to extend to them or the cache becomes a free-paid-call dispenser.

The threat is concrete and well-modeled by Panel 2:

- **`TM-D2` (Critical, replay flood)**: same valid `X-Payment` replayed N times. If the cache key includes only `(agent_id, request_id)` and the same `(id, X-Payment)` arrives twice, two outcomes are bad:
  - Hub re-calls facilitator each time → attacker burns the Hub's facilitator quota and racks up duplicate "settlements" if the facilitator returns success (it MUST not — but defense in depth requires the Hub to not depend on facilitator behavior).
  - Hub idempotency-caches by `request.id` only → benign retry path collides; the second `X-Payment`'s signed authorization is silently consumed without being settled (mild leak; the EIP-3009 nonce protects on-chain reuse but the Hub silently dropped a paid signature).

- **`TM-S4` (High, cross-capability replay)**: attacker observes Agent A's `X-Payment` (e.g., from a leaked log, MITM on a misconfigured proxy, or compromised Agent), then retries it against a *different* capability with a different price. If the cache key doesn't bind payment to capability, the cheaper capability uses Agent A's overpayment.

ADR-0001's wire-format guarantee — "for any sequence of requests with the same `(agent_id, request_id)`, the cache returns the cached body only if the full input hash matches" — is the right answer. x402 just expands what "the full input hash" includes.

The second layer — a dedicated `x402_settlements` table with UNIQUE constraints on the on-chain identifiers — is the safety net for the case where the input-hash defense fails (operator misconfiguration, two Hub instances racing, etc.). The table's constraints make the "same on-chain payment cannot be redeemed twice" invariant a property of the database, not just of the cache logic.

## Decision

### 1. Idempotency cache key extension

The Hub's idempotency cache key is extended from ADR-0001's formula to:

```
SHA-256(
  capability ||
  "|" || action ||
  "|" || canonical_json(input) ||
  "|" || (mandate.provenance_hash if present else "") ||
  "|" || (sha256_hex(decoded_x_payment_bytes) if X-Payment present else "") ||
  "|" || (settlement_tx_hash if known at cache-store time else "")
)
```

The `decoded_x_payment_bytes` is the base64-decoded payload, NOT the raw header value (which carries an unbounded number of valid base64 encodings — extra padding, etc.). The decode-then-hash approach makes the input deterministic.

The `settlement_tx_hash` is unknown at the moment the cache is FIRST consulted (the request has not yet been settled). The Hub MUST:

- Compute the cache key WITHOUT `settlement_tx_hash` for the initial cache lookup.
- On cache miss, proceed with verification + settlement.
- Once `tx_hash` is known, compute the cache key WITH `settlement_tx_hash` and store the response under that key.
- Subsequent retries with the same `(id, X-Payment)` arrive, decode + hash → same intermediate key → on cache miss, the Hub MUST re-call the facilitator's `/verify` (which is idempotent and cheap), receive the same `tx_hash` (because the facilitator's own replay defense returns the existing settlement on a duplicate payload), then look up the cache under the now-complete key and return the cached response.

In practice this means the cache key has two states: a "lookup key" (without `tx_hash`) and a "store key" (with `tx_hash`). Conformant Hubs MAY simplify by using the `(payer, eip3009_nonce)` pair (which is computable from the decoded X-Payment alone) as the cache key — this works because the table-level UNIQUE constraint (§2 below) guarantees the same `(payer, eip3009_nonce)` always resolves to the same settlement. The reference Hub uses this simplification.

### 2. Single-use settlements table

Conformant Hubs MUST maintain a dedicated `jecp.x402_settlements` table with UNIQUE constraints on BOTH:

- `(payer, eip3009_nonce)` — catches replay even before facilitator settlement (the agent re-sends the same `X-Payment` for a different request `id`).
- `tx_hash` — catches replay after facilitator settlement (an attacker captures a `tx_hash` from a public log and submits a hand-crafted request claiming that settlement).

```sql
CREATE TABLE jecp.x402_settlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tx_hash VARCHAR(66) NOT NULL UNIQUE,
    payer VARCHAR(42) NOT NULL,
    eip3009_nonce VARCHAR(66) NOT NULL,
    agent_id UUID NOT NULL,
    request_id VARCHAR(255) NOT NULL,
    capability_id VARCHAR(255) NOT NULL,
    amount_usdc_micro BIGINT NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'facilitator_attested',
    facilitator_response_jsonb JSONB NOT NULL,
    settled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    chain_confirmed_at TIMESTAMPTZ,
    UNIQUE (payer, eip3009_nonce)
);
```

Before calling the facilitator's `/settle`, the Hub MUST atomically `INSERT ... ON CONFLICT DO NOTHING` against `(payer, eip3009_nonce)`. If the conflict fires, the same payload was already used by a different `(agent_id, request_id)` — return HTTP 409 `X402_SETTLEMENT_REUSED` with `details.subcause = "nonce_reused"` (03-errors.md §3.8).

After `/settle` returns `tx_hash`, the Hub MUST update the row with the `tx_hash` and `facilitator_response_jsonb`. If the UPDATE conflicts on `tx_hash` (another row already records this settlement), the Hub MUST return HTTP 409 `X402_SETTLEMENT_REUSED` with `details.subcause = "tx_hash_seen"` and roll back the in-flight invocation.

### 3. Order of operations

Per ADR-0001, every request — even an idempotent retry — MUST pass full Provenance v2 verification before the cache is consulted. The x402 extension adds:

1. Authenticate `agent_id` + `api_key` (bcrypt verify).
2. Verify `mandate.provenance_hash` (HMAC + timestamp skew + nonce-cache check).
3. **NEW**: If `X-Payment` present, decode the envelope, verify size ≤ 8 KB, normalize header. Reject duplicate `X-Payment` headers.
4. **NEW**: If `X-Payment` present, atomically `INSERT ON CONFLICT DO NOTHING` into `x402_settlements` keyed on `(payer, eip3009_nonce)`. On conflict → 409 `X402_SETTLEMENT_REUSED`.
5. Compute the idempotency cache key per §1.
6. Look up; on hit, return the cached response body and HTTP status as-is.
7. On miss, call facilitator `/verify` then `/settle`; record `tx_hash`; execute capability; store the response.

Cache hits MUST NOT re-call the facilitator, MUST NOT re-charge the wallet, and MUST NOT re-trigger the Splitter contract.

## Consequences

**Positive**

- A captured `X-Payment` cannot be replayed against the cache for a different `(capability, action, input)` tuple. The input-hash extension binds payment to capability, mitigating Panel 2 `TM-S4`.
- The same `(payer, eip3009_nonce)` cannot be redeemed twice across Hub restarts, two Hub instances, or across distinct requests — the database UNIQUE constraint is the source of truth, not in-memory cache state. Closes `TM-D2`.
- The same `tx_hash` cannot be claimed by two different requests — important for multi-Hub deployments where two Hubs share a database but not a memory-cache.
- The two-layer defense (input hash + table constraints) means an operator misconfiguration on the cache layer (wrong TTL, cache eviction race, etc.) does not silently allow double-spend — the database constraint catches it loudly with a 409.
- Idempotent retries from legitimate clients (network drops, agent crash recovery) work transparently — same `(id, X-Payment)` returns the cached response without burning a second facilitator call or a second on-chain settlement.

**Negative**

- The cache key now has two computation states (lookup vs. store) for x402 paths. Implementations MUST get the protocol right or a benign retry can drop into the cache-miss path, re-call the facilitator, and waste API quota. The reference Hub's simplification (`(payer, eip3009_nonce)` as cache key) is a viable workaround but requires understanding the invariant.
- Writing to `x402_settlements` BEFORE calling `/settle` creates a transient state where a row exists with `tx_hash = NULL`. The reconciler (06-x402-integration.md §6.2) MUST tolerate this state and treat NULL-tx_hash rows older than 10 minutes as `orphaned` (the `/settle` call failed silently, e.g., Hub crashed mid-flight).
- Per-request cost is one extra DB write (the INSERT) on every x402-path invoke. Measured at ~3-8ms p99 on the reference Hub. Acceptable for a payment hot path.
- The `x402_settlements` table grows by one row per x402 invoke; partitioning by `settled_at` (monthly) and 18-month retention with cold archive is recommended (per Panel 2 `TM-D7`). Spec does not normalize the retention policy; operator choice.

## Alternatives Considered

**Alternative 1: Cache key stays (agent_id, request_id, input_hash) — ignore X-Payment.**
Rejected. Same threat model as ADR-0001 Alternative 1 (Stripe-style key). A captured `X-Payment` could be replayed against arbitrary capabilities at lower price points (`TM-S4`). The whole point of binding payment to capability is to make the cache an authentication-aware boundary, not a free-paid-call dispenser.

**Alternative 2: Use only the `x402_settlements` UNIQUE constraints — no input hash extension.**
Rejected. The table-only defense fires AFTER the facilitator round-trip (the INSERT is at step 4 of the order of operations above, but the cache lookup at step 5 still reads stale data). Without the input hash extension, the Hub re-calls the facilitator on every benign retry — burning facilitator quota and adding 200-300ms to every retry. The two layers compose: input hash is the fast-path optimization; table constraints are the correctness backstop.

**Alternative 3: Trust the EIP-3009 nonce alone (it's already on-chain unique).**
Rejected. The EIP-3009 nonce is unique at the *asset contract layer* — the chain rejects a tx that reuses it. But the Hub's idempotency is between the *Hub and the agent*, not the chain. A duplicate `X-Payment` arriving at the Hub before the on-chain rejection lands would still trigger a facilitator round-trip, still consume Hub resources, and still race with the cache. The UNIQUE constraint at the Hub layer makes the JECP semantics explicit and testable without round-tripping to the chain.

**Alternative 4: Separate cache namespace per payment method.**
Use `request_cache_wallet` and `request_cache_x402` as distinct tables. Rejected because: a single `(agent_id, request_id)` represents one logical agent intent; routing to two cache tables based on which header is present means the same `id` can produce different cached responses depending on which method was used — exactly the conflict that 409 `DUPLICATE_REQUEST` was designed to surface. Single namespace + composite key is the right shape.

## Wire-format guarantee committed by this decision

For any sequence of requests R₁, R₂, ..., Rₙ to a v1.1.0-conformant Hub where ALL requests share the tuple `(agent_id, request_id)`:

- If Rᵢ presents an `X-Payment` header, the Hub atomically registers `(payer, eip3009_nonce)` in `x402_settlements` BEFORE calling the facilitator.
- If R₁ has a fresh nonce, valid HMAC, and a valid `X-Payment`, R₁ is processed; R₂..Rₙ receive the cached body of R₁ **only if** the full input hash (per §1) matches R₁'s key, **else** they receive 409 `DUPLICATE_REQUEST` (or 409 `X402_SETTLEMENT_REUSED` if the `X-Payment` differs).
- If Rᵢ (i ≥ 2) presents an `X-Payment` whose `(payer, eip3009_nonce)` was already used by ANY other `(agent_id, request_id)`, Rᵢ MUST receive 409 `X402_SETTLEMENT_REUSED` with `details.subcause = "nonce_reused"`, regardless of cache state.
- If two requests with different `(agent_id, request_id)` somehow surface the same `tx_hash` (e.g., facilitator replay), the second MUST receive 409 `X402_SETTLEMENT_REUSED` with `details.subcause = "tx_hash_seen"`.
- The agent's USDC is debited at most once per unique cache key; the on-chain Splitter is invoked at most once per unique `(payer, eip3009_nonce)`.

## References

- ADR-0001 — Idempotency × Provenance interaction (the prior decision this extends)
- ADR-0003 — x402 Integration (the design rationale this idempotency extension serves)
- 01-protocol.md §5 — Idempotency (base spec normative requirement)
- 03-errors.md §3.8 — `X402_SETTLEMENT_REUSED` + subcauses `nonce_reused` / `tx_hash_seen`
- 06-x402-integration.md §3.4 — Idempotency interaction (normative restatement of this ADR)
- 06-x402-integration.md §6.2 — Reconciler (handles the transient `tx_hash = NULL` state described in the Negative consequences)
- Panel 2 §3.1 — `TM-D2` (replay) + `TM-S4` (cross-capability replay) — the two threats this ADR closes
- [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) — `transferWithAuthorization` and the per-signer nonce semantics
- [RFC 9110 §15.5.10](https://datatracker.ietf.org/doc/html/rfc9110#section-15.5.10) — 409 Conflict semantics for idempotency disputes
