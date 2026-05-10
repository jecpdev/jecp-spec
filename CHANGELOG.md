# JECP Specification — Changelog

This file tracks changes to the JECP wire protocol, error catalog, and manifest schema.

The repository follows [SemVer](https://semver.org). Major versions break wire compatibility; minor versions add backward-compatible features; patch versions clarify or fix non-normative wording.

---

## v1.0.1 (errata) — 2026-05-10 — Provenance v2 + C1–C4 batch

Errata release. Backward-compatible. Hubs already on v1.0.0 remain conformant
because every change is either an *additive* feature (Provenance v2 alongside
v1) or a *clarification* of behavior the spec was already silent on. New
deployments MUST adopt these changes.

### Authentication (02-authentication.md)

- **§3.1 Vendor-neutral ID format (C1)**. Examples and prose now make the
  `<vendor>_<kind>_<random>` pattern explicit instead of treating `jdb_` as
  literal. Hubs MAY pick any 2–8 char lowercase vendor prefix; reference
  implementation continues to use `jdb_`.
- **§4.2 Mandate JSON schema (C2)**. `agent_id` / `api_key` regex now match the
  vendor-prefix convention (`^[a-z]{2,8}_(ag|ak)_[A-Za-z0-9]{16,}$`). The
  `provenance_hash` regex now accepts both v1 (64-hex) and v2
  (`v2:<ts>:<nonce>:<hmac>`) wire formats.
- **§5 Provenance Hash — full rewrite (Provenance v2 errata)**.
  - **§5.2 v2 = HMAC-SHA256(api_key, "agent_id:timestamp:nonce")** with wire
    format `"v2:<unix_seconds>:<nonce_hex>:<hmac_hex>"`. Clock-skew window
    ±300s, nonce-replay cache 600s. RECOMMENDED for all new deployments.
  - **§5.4 Format discrimination** by `"v2:"` prefix. Hubs MUST dispatch
    automatically.
  - **§5.5 Reference implementation note**. Documents the v1 4-part vs 3-part
    discrepancy that motivated the rewrite.
  - **§5.6 v1 = SHA256("agent_id:total_calls:api_key[..8]")** — canonicalized
    as 3-part input matching the actual reference implementation, deprecated.
  - **§5.7 Sunset schedule for v1**: deprecated 2026-05-10; `Deprecation` /
    `Sunset` response headers from 2026-08-01; verifier removal 2026-11-01.
- **§9.2 Mandate Theft** updated for v1 (no replay defense) vs v2 (nonce cache
  + clock skew enforce a hard 600s ceiling).
- **§9.7 Server-Side Request Forgery (SSRF) on Agent-Controlled URLs (C3)**
  — new section. Hubs MUST validate `callback_url`, `provider.endpoint_url`,
  and `webhook.destination_url` against a deny list (loopback, link-local,
  private IPv4/IPv6 ranges, non-HTTPS schemes) and MUST re-resolve hostnames
  immediately before connecting (DNS-rebinding defense).

### Errors (03-errors.md)

- **§3.1 `PROVENANCE_MISMATCH`** updated to enumerate v2 sub-causes (wire
  malformed / clock skew / nonce replay / HMAC mismatch) in addition to the v1
  hash mismatch. Recovery guidance points Agents at v2.

### Manifest (04-manifest.md)

- **§5 Pricing.currency (C4)**. Enum widened from `USD | USDC | both` to ISO
  4217 alpha-3 fiat codes (`USD`, `JPY`, `EUR`, `GBP`, `CAD`, `AUD`, `CHF`,
  `KRW`, `SGD`, `HKD`, ...) plus a crypto extension (`USDC`, `USDT`, `BTC`,
  `ETH`, `MATIC`). The literal `"both"` is retained until 2026-11-01 for
  backward compatibility, then removed.
- **§5.1 Pricing JSON schema** updated to match (regex `^([A-Z]{3}|both)$`).
- **§5.1 Billing.payout_currency** widened analogously (regex
  `^[A-Z]{3,5}$`).
- **§6.1 Validation rule 8** rewritten to validate the new currency set.

### Migration (informative)

- Reference Hub at `setsuna-jobdonebot.fly.dev` ships Provenance v2 dual-path
  verification in v53+. v1 verifiers remain enabled until 2026-11-01.
- Reference TS SDK `@jecpdev/sdk` exports `computeProvenanceV2` from v0.6.0+
  (and a deprecated `computeProvenanceV1` for legacy callers).
- No wire-breaking changes for existing Agents; v1 hashes continue to validate.

---

## v1.0.0 — 2026-05-09 — Stable

First non-draft release. Wire compatibility frozen for the v1.x line. Backward-compatible additions (M2/M3 in this release) live alongside the v0.x draft surface; nothing has been removed.

### Wire format (01-protocol.md)

- **§4.3 Provider streaming on `/v1/invoke`** (W5 / Phase A) — Server-Sent Events with five terminal events (`open`/`chunk`/`meter`/`completed`/`error`/`cancelled`). Pass-through; billing settles on `completed`.
- **§4.4 Composite action execution** (M3 / Phase B) — server-side workflow with `composes.steps[]`, deterministic ordering, automatic rollback refunds. v1.0 limit: depth=1, max 8 steps, 5-min total cap, no streaming for composites.
- §3.1 Headers: `Accept: text/event-stream` is now a normative content-negotiation switch on `/v1/invoke`.

### Manifest schema (04-manifest.md)

- **§5 Action.streaming**: per-action boolean (default false). Companion to §4.3 streaming.
- **§5 Pricing.model** enum extended: `flat | per_chunk | per_second` added alongside existing `per_call | per_token | tiered`. Optional unit-rate fields: `input_per_token_usdc`, `output_per_token_usdc`, `per_chunk_usdc`, `audio_per_second_usdc`.
- **§5.2 Composite Actions** (M3): new `composes` block on `Action` with `steps[]`, `max_depth`, `on_step_failure`, `timeout_total_ms`, plus `${...}` template substitution and per-step output binding.

### Error catalog (03-errors.md)

- **§3.5.1 Streaming**: `NOT_STREAMABLE`, `STREAM_IN_PROGRESS`, `STREAM_TIMEOUT`, `PROVIDER_TIMEOUT` (streaming variant), `STREAM_INCOMPLETE`, `PROVIDER_DISCONNECT`.
- **§3.5.2 Composites**: `COMPOSITE_STEP_FAILED`, `COMPOSITE_BIND_ERROR`, `COMPOSITE_DEPTH_EXCEEDED`, `COMPOSITE_TIMEOUT`, `COMPOSITE_REFUND_FAILED`.

### Reference implementation alignment (informative)

- Hub Rust at `setsuna-jobdonebot.fly.dev` ships the streaming endpoint live (Phase A) and the M2 key-rotation endpoints (`POST /v1/agents/me/rotate-key`, `POST /v1/providers/me/rotate-key`) — Phase B in flight. Composite execution (M3) is spec-only in v1.0.0 of the spec; first reference implementation ships in v1.1 once the Hub workflow engine lands.

### Migration from `1.0.0-draft`

There are no breaking changes between `1.0.0-draft` and `1.0.0` — everything in this release is additive. Implementations that targeted the draft remain conformant.

If you hard-coded the `Status: Draft` strings somewhere, update to `Status: Stable`.

---

## v1.0.0-draft — 2026-05-07 — Initial draft

Initial public draft.

- §1–§9: wire format, error envelope, idempotency, sizes, timeouts.
- 02-authentication: `X-Agent-ID` + `X-API-Key`, Mandate, provenance hash, Trust Tier (bronze/silver/gold/platinum).
- 03-errors v1: AUTH/VALIDATION/ROUTING/BILLING/THROTTLING/PROVIDER/HUB error groups.
- 04-manifest v1: namespace + capability + actions + pricing + schemas + side_effects + sla + compliance + billing + deprecation.
- 05-discovery: GET /v1/capabilities catalog format.
