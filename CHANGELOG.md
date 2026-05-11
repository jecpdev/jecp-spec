# JECP Specification — Changelog

This file tracks changes to the JECP wire protocol, error catalog, and manifest schema.

The repository follows [SemVer](https://semver.org). Major versions break wire compatibility; minor versions add backward-compatible features; patch versions clarify or fix non-normative wording.

---

## v1.1.0 — 2026-05-11 — x402 Integration

Backward-compatible minor release. Adds Coinbase's [x402](https://x402.org) (HTTP 402 + USDC-on-Base micropayment) as a **second, parallel payment path** on `POST /v1/invoke`. The existing pre-funded Stripe wallet path is unchanged. v1.1.0 conformance does NOT require x402 support — Hubs that omit the x402 facilitator config remain conformant with the existing v1.0.x suite plus the `payment_methods`-honors-default invariant.

The integration achieves three strategic goals: true sub-dollar invoke pricing (≤1% on-chain gas vs. ~5.9% Stripe top-up rake), agent-native UX (no human-in-the-loop top-up step for USDC-funded agents), and the load-bearing positioning claim "first agent-commerce protocol with on-chain atomic 85/10/5 revenue split" via the immutable `JecpSplitter` contract on Base mainnet.

All five admiral-locked design decisions are documented in [ADR-0003 — x402 Integration](adr/0003-x402-integration.md). The idempotency-side extension (binding settlement uniqueness to the existing input-hash defense from ADR-0001) is documented in [ADR-0004 — Idempotency × x402](adr/0004-idempotency-x402.md).

### New normative section

- **[06-x402-integration.md](spec/06-x402-integration.md)** (new file) — full normative spec for the x402 path: 402 challenge envelope shape, `X-Payment` request header (base64 EIP-3009, ≤8 KB), Hub→facilitator interaction (verify before settle), `X-Payment-Response` reply header, trust model (single facilitator + cert pin + Ed25519 + reconciler + kill switch), capability manifest extension, Splitter contract integration, and backward-compat semantics. ~700 lines.
- 01-protocol.md gains §3.3.1 — a 1-paragraph note about the OPTIONAL `payment` sibling field on the existing 402 error envelope, cross-referencing 06.

### New error codes (5)

Added to 03-errors.md as new §3.8. All carry a `details.subcause` from the closed registry §3.8.6 (19 subcauses total — same convention as `PROVENANCE_MISMATCH`).

- **`X402_PAYMENT_INVALID`** (HTTP 422) — facilitator rejected the X-Payment payload (subcauses: `signature_invalid`, `signature_malleable`, `amount_mismatch`, `payto_mismatch`, `network_mismatch`, `asset_mismatch`, `expired`, `nonce_reused`, `unsupported_scheme`, `header_too_large`, `duplicate_payment_header`, `payload_decode_error`, `payment_capability_binding_violation`).
- **`X402_NOT_ACCEPTED`** (HTTP 422) — capability does not declare x402, or kill switch engaged (subcauses: `capability_wallet_only`, `x402_disabled`, `network_unsupported`).
- **`X402_SETTLEMENT_TIMEOUT`** (HTTP 504) — facilitator did not respond within timeout (subcauses: `facilitator_slow`, `chain_congested`).
- **`X402_FACILITATOR_UNREACHABLE`** (HTTP 502) — Hub could not reach trusted facilitator (subcauses: `dns_fail`, `connection_refused`, `cert_pin_mismatch`, `signature_pin_mismatch`).
- **`X402_SETTLEMENT_REUSED`** (HTTP 409) — UNIQUE-constraint conflict on `(payer, eip3009_nonce)` or `tx_hash` per ADR-0004 (subcauses: `tx_hash_seen`, `nonce_reused`).

`PAYMENT_REQUIRED` (existing) gains a normative `payment` sibling field on x402-accepting capabilities. The new `next_action.type` value `"x402_settle"` is added to 03-errors.md §4.2.

### Manifest extension

- **04-manifest.md §5 `pricing.payment_methods`** — new OPTIONAL array, default `["stripe"]` when omitted, items in `["stripe", "x402"]`. Declares which payment methods an action accepts. Old manifests without the field continue to work unchanged (default to wallet-only behavior).

### Discovery extension

- **05-discovery.md §4.4.1** — new OPTIONAL `payment_methods_supported` top-level field on `/.well-known/agent-guide.json`. v1.1.0 reference Hubs SHOULD emit `["stripe", "x402"]` once the facilitator is configured. Includes a top-level `x402` block with `facilitator_url`, `supported_networks`, `supported_assets`, `splitter_contract`, `split_ratio`, `x402_version`, `spec_url`.
- 05-discovery.md §6 — `/v1/capabilities` action object MAY include `payment_methods` per action (mirror of the manifest field).

### Schemas

- **`schemas/v1/payment-requirements.json`** (new) — JSON Schema 2020-12 for items in `payment.accepts[]`. Two `oneOf` variants: `stripe-wallet` (JECP-defined) and `exact` (x402 v1).

### Conformance

- **`conformance/v1.1/X402_*.yaml`** (new directory, 19 files) — one assertion per Panel 2 §7 named test:
  - `X402_VERIFY_BEFORE_SETTLE`
  - `X402_AMOUNT_MISMATCH_REJECTED`
  - `X402_NONCE_REUSE_REJECTED`
  - `X402_TX_HASH_REUSE_REJECTED`
  - `X402_FACILITATOR_TIMEOUT_GRACEFUL`
  - `X402_CERT_PIN_ENFORCED`
  - `X402_RESPONSE_SIG_VERIFIED`
  - `X402_SUNSET_HEADER_PRESENT`
  - `X402_PAYMENT_METHODS_FIELD_OPTIONAL`
  - `X402_OLD_SDK_GRACEFUL_DEGRADE`
  - `X402_SPLITTER_ADDRESS_IN_PAYTO`
  - `X402_RECONCILER_CHAIN_CONFIRM`
  - `X402_RECONCILER_MISMATCH_FLAGGED`
  - `X402_RECONCILER_ORPHAN_DETECTED`
  - `X402_REFUND_RATE_LIMIT_ENFORCED`
  - `X402_KILL_SWITCH_HALTS_NEW`
  - `X402_KILL_SWITCH_PRESERVES_WALLET`
  - `X402_PAYMENT_RESPONSE_HEADER`
  - `X402_AGENT_GUIDE_DISCLOSES_X402`

### Fixtures

- **`fixtures/x402-*.json`** (new, 7 files) — golden request/response fixtures: `x402-happy-path-pure`, `x402-happy-path-wallet-fallback`, `x402-error-payment-invalid`, `x402-error-not-accepted`, `x402-error-settlement-timeout`, `x402-error-facilitator-unreachable`, `x402-error-settlement-reused`.

### Architecture decisions

- **[ADR-0003 — x402 Integration](adr/0003-x402-integration.md)** — full design rationale + the 5 admiral-locked decisions (single facilitator + cert pin + Ed25519; Splitter contract for atomic 85/10/5; 24h manual refund + Hub absorbs; Stripe-first `accepts[]` order; SDK auto-mode tries x402 aggressively). Documents 4 rejected alternatives (Hub-side KMS+multisig, Stripe co-charge bridging, Provider monthly settlement, custom facilitator with one-tx pull-and-split).
- **[ADR-0004 — Idempotency × x402](adr/0004-idempotency-x402.md)** — extends ADR-0001 to cover x402: idempotency cache key composition adds SHA-256 of the X-Payment payload AND the resulting `tx_hash`; a dedicated `x402_settlements` table enforces UNIQUE on both `(payer, eip3009_nonce)` AND `tx_hash`. Closes Panel 2 `TM-D2` (Critical replay) and `TM-S4` (cross-capability replay).

### SemVer justification

All wire changes are additive (new OPTIONAL fields, new OPTIONAL headers, 5 new error codes, 1 new value on the open enum `billing.method`, 1 new `next_action.type`). No REQUIRED fields added. No types changed. No fields removed. No HTTP status remappings. No behavior change for capabilities that omit `payment_methods` (or declare `["stripe"]`). The wire-version string `"jecp": "1.0"` is unchanged through the v1.x line — only the spec document version bumps to 1.1.0.

### Migration from v1.0.2

- **No wire-breaking changes.** Existing clients (≤ SDK v0.7.x) continue to function unchanged. The new `payment` sibling field on 402 envelopes is silently ignored by old SDKs (additive OPTIONAL).
- **Hub upgrade** requires running new database migrations (`x402_settlements`, `x402_refund_log`, `payment_methods` column on capabilities). Hubs that do NOT configure x402 (no facilitator URL, no Splitter address) remain v1.1.0-conformant — they simply never emit the new error codes and never advertise `"x402"` in any 402 response.
- **Provider opt-in** is per-capability via `pricing.payment_methods: ["stripe", "x402"]` (recommended default for x402-aware Providers; `["x402"]` only is supported but bounces older agents at the 402-vs-401 hop).
- **Agent SDKs** that want x402 SHOULD bump to `@jecpdev/sdk@0.8.0+` (ships `JecpClient({ payment: { mode, signer } })` + auto-fallback). Older SDKs continue using the wallet path on `["stripe", "x402"]` capabilities.

### Reference implementation alignment (informative)

Reference Hub implementation lands as part of jecp Hub Phase 1 / x402-impl Sprint:
- Rust modules: `protocol/x402_types.rs`, `protocol/x402_verify.rs`, `services/x402_facilitator.rs`, `services/x402_reconciler.rs`, `services/splitter_registry.rs`, modified `routes/invoke.rs`.
- Solidity contract: `JecpSplitter.sol` in separate repo `github.com/jecpdev/jecp-contracts` (Foundry; audit by Spearbit / Cure53 / Trail of Bits before mainnet).
- SDK: `@jecpdev/sdk@0.8.0` with `JecpClient`, `createSigner`, `X402PaymentInvalidError`, `X402FacilitatorTimeoutError`, etc.
- CLI: `@jecpdev/cli@0.7.0` with `wallet:link-usdc`, `--pay x402` flag, 4 new `doctor` checks.

Tagged `jecp-spec@v1.1.0-rc1` after spec text complete; promoted to `jecp-spec@v1.1.0` after Hub deploy + Splitter audit clean + 19/19 conformance assertions pass.

---

## v1.0.2 — 2026-05-10 — Errata

Backward-compatible patch release. Closes the four credibility-killers surfaced by the 7-agent panel review of v1.0.1 plus the ADR-0001 architecture artifact.

### Endpoint reconciliation (K1)

- **Canonical execution endpoint is `POST /v1/invoke`.** v1.0.0 / v1.0.1 contained an internal contradiction: §1, §2, §5, §9, §10 of 01-protocol referenced `/v1/jecp` while §4.3, §4.4 (streaming + composites) and 04§5.2 referenced `/v1/invoke`. The reference Hub ships `/v1/invoke`; v1.0.2 promotes it to canonical and demotes `/v1/jecp` to a legacy alias.
- All occurrences of `/v1/jecp` in 00, 01 (§1, §2, §5, §9, §10), 02 §8, 05 §3 + §9 replaced with `/v1/invoke`. New 01-protocol §2.1 "Legacy alias" clause defines the alias contract; new §2.2 documents the migration for spec readers.
- Wire compatibility preserved: Hubs MUST continue to accept `/v1/jecp` through the v1.x line and MUST attach `Deprecation: true` + `Sunset: Sat, 01 Jan 2028 00:00:00 GMT` + `Link: <…>; rel="deprecation"` response headers per RFC 8594. The legacy alias is removed at v2.0.

### Wire-format MUSTs (K2 — five credibility fixes)

- **HTTP 415 `UNSUPPORTED_MEDIA_TYPE`** (new code in 03-errors §3.2) — Hubs MUST return 415 when `Content-Type` is not `application/json` (parameters such as `;charset=utf-8` are accepted). 01-protocol §2 cross-references the new code.
- **HTTP 409 `DUPLICATE_REQUEST`** (existing code; status was already 409 in v1.0.1, v1.0.2 strengthens the wording with RFC 9110 §15.5.10 citation and clarifies that 409 fires only on conflict, not on identical replays).
- **HTTP 410 `CAPABILITY_DEPRECATED`** (new normative section 01-protocol §4.6 + 03-errors §3.3 hardening) — Hubs MUST attach `Sunset` (IMF-fixdate per RFC 8594), `Deprecation: true`, and `Link rel="deprecation"` response headers when serving deprecated capabilities, including a 30-day pre-sunset notice on successful 2xx responses.
- **`Retry-After` MUST on 429 `RATE_LIMITED`** (03-errors §3.5 hardening) — Hubs MUST emit `Retry-After: <integer-seconds>` in `[1, 600]` per RFC 9110 §10.2.3. `X-RateLimit-Limit / -Remaining / -Reset` remain SHOULD (reserved for v1.0.3 normative tightening).
- **HTTP 400 `INPUT_SCHEMA_VIOLATION`** (new code in 03-errors §3.2) — distinct from `VALIDATION_FAILED` (envelope-level): the new code identifies action-level input schema failures so SDKs can surface clearer diagnostics. `details.errors[]` carries `instance_path` + `schema_path` + `reason`.

### Hub Discovery (K4)

- **`/.well-known/agent-guide.json`** is now normative. New 05-discovery.md §4.5 makes the document MUST for conformant Hubs. Schema published at `schemas/v1/agent-guide.json` (JSON Schema 2020-12). Required fields: `version`, `last_updated`, `vendor_prefix`, `hub_name`, `hub_url`, `supported_capabilities`, `conformance_levels`, `register_endpoint`, `contact.support`.
- **Spec mirror at `https://jecp.dev/spec/v1.0/*`** — every tagged release is mirrored to the website via GitHub Action (`.github/workflows/mirror-spec.yml`). Tag-pinned URLs serve `Cache-Control: public, max-age=31536000, immutable`. The mirror is the canonical immutable source consumed by the `Link rel="deprecation"` headers and the spec's `documentation_url` references.

### Architecture decision artifact (K5)

- **[ADR-0001 — Idempotency–Provenance Interaction](adr/0001-idempotency-provenance-interaction.md)** published. Documents the v1.0.1 H2 patch as a normative architecture decision: idempotency cache keys MUST include `mandate.provenance_hash`. Records the three alternatives we considered and rejected (Stripe-style key only, verify-on-miss-only, opaque provenance). Cross-referenced from 02-authentication §5.2.2.
- ADR registry rules established: `adr/template.md`, `adr/README.md` index, `.github/workflows/adr-lint.yml` enforces required sections + CHANGELOG cross-link.

### Reference implementation alignment (informative)

- Hub `setsuna-jobdonebot.fly.dev` implements all v1.0.2 wire-format MUSTs in commits Phase-0/c2 through Phase-0/c7 (per `docs/jecp/PATH-TO-NO1.md`).
- `@jecpdev/sdk` 0.7.1 ships RELEASE_NOTES referencing ADR-0001; no API change (SDK already pins `/v1/invoke` since 0.4.0).
- `@jecpdev/cli` is unchanged.

### Migration from v1.0.1

- No wire-breaking changes. Existing clients that target `/v1/jecp` continue to function unchanged; they observe new `Deprecation` / `Sunset` headers as their migration alarm.
- `INPUT_SCHEMA_VIOLATION` is a new code; clients MUST tolerate unknown error codes (per 03-errors §7) and may map them to the parent code class.
- The `Retry-After` MUST and the K2.3 sunset-header MUST are hardenings of behavior the spec was previously silent on — Hubs that emit them already are conformant.

---

## v1.0.0 — 2026-05-10 — Stable

First non-draft release. Wire compatibility frozen for the v1.x line. Backward-compatible additions (M2/M3 in this release) live alongside the v0.x draft surface; nothing has been removed.

### Wire format (01-protocol.md)

- **§4.3 Provider streaming on `/v1/invoke`** (W5 / Phase A) — Server-Sent Events with five terminal events (`open`/`chunk`/`meter`/`completed`/`error`/`cancelled`). Pass-through; billing settles on `completed`.
- **§4.4 Composite action execution** (M3 / Phase B) — server-side workflow with `composes.steps[]`, deterministic ordering, automatic rollback refunds. v1.0 limit: depth=1, max 8 steps, 5-min total cap, no streaming for composites.
- §3.1 Headers: `Accept: text/event-stream` is now a normative content-negotiation switch on `/v1/invoke`.

### Authentication (02-authentication.md)

- **§3.1 Vendor-neutral ID format**. Examples and prose make the `<vendor>_<kind>_<random>` pattern explicit instead of treating `jdb_` as literal. Hubs MAY pick any 2–8 char lowercase vendor prefix; the reference implementation continues to use `jdb_`.
- **§4.2 Mandate JSON schema**. `agent_id` / `api_key` regex now match the vendor-prefix convention (`^[a-z]{2,8}_(ag|ak)_[A-Za-z0-9]{16,}$`). The `provenance_hash` regex accepts both v1 (64-hex) and v2 (`v2:<ts>:<nonce>:<hmac>`) wire formats.
- **§5 Provenance Hash — Provenance v2 (HMAC-SHA256) is now the recommended scheme**.
  - **§5.2 v2 = HMAC-SHA256(api_key, "agent_id:timestamp:nonce")** with wire format `"v2:<unix_seconds>:<nonce_hex>:<hmac_hex>"`. Clock-skew window ±300s, nonce-replay cache 600s. RECOMMENDED for all new deployments.
  - **§5.4 Format discrimination** by `"v2:"` prefix. Hubs MUST dispatch automatically.
  - **§5.5 Reference implementation note**. Documents the v1 4-part vs 3-part discrepancy that the v1.0 stable resolves: the canonical v1 input is the 3-part form (matching the reference Rust impl since day one).
  - **§5.6 v1 = SHA256("agent_id:total_calls:api_key[..8]")** — canonicalized as 3-part input, deprecated.
  - **§5.7 Sunset schedule for v1**: deprecated at v1.0 release (2026-05-10); `Deprecation` / `Sunset` response headers from 2026-08-01; verifier removal 2026-11-01.
- **§9.2 Mandate Theft** updated to reflect that v1 alone provides no replay defense; v2 enforces a hard 600s ceiling via the nonce cache + clock-skew window.
- **§9.7 Server-Side Request Forgery (SSRF) on Agent-Controlled URLs** — new section. Hubs MUST validate `callback_url`, `provider.endpoint_url`, and `webhook.destination_url` against a deny list (loopback, link-local, private IPv4/IPv6 ranges, non-HTTPS schemes) and MUST re-resolve hostnames immediately before connecting (DNS-rebinding defense).

### Manifest schema (04-manifest.md)

- **§5 Action.streaming**: per-action boolean (default false). Companion to §4.3 streaming.
- **§5 Pricing.model** enum extended: `flat | per_chunk | per_second` added alongside existing `per_call | per_token | tiered`. Optional unit-rate fields: `input_per_token_usdc`, `output_per_token_usdc`, `per_chunk_usdc`, `audio_per_second_usdc`.
- **§5 Pricing.currency** enum widened from `USD | USDC | both` to ISO 4217 alpha-3 fiat codes (`USD`, `JPY`, `EUR`, `GBP`, `CAD`, `AUD`, `CHF`, `KRW`, `SGD`, `HKD`, ...) plus a crypto extension (`USDC`, `USDT`, `BTC`, `ETH`, `MATIC`). The literal `"both"` is retained until 2026-11-01 for backward compatibility, then removed.
- **§5.1 Pricing JSON schema** updated to match (regex `^([A-Z]{3}|both)$`).
- **§5.1 Billing.payout_currency** widened analogously (regex `^[A-Z]{3,5}$`).
- **§5.2 Composite Actions** (M3): new `composes` block on `Action` with `steps[]`, `max_depth`, `on_step_failure`, `timeout_total_ms`, plus `${...}` template substitution and per-step output binding.
- **§6.1 Validation rule 8** rewritten to validate the new currency set.

### Error catalog (03-errors.md)

- **§3.1 `PROVENANCE_MISMATCH`** updated to enumerate v2 sub-causes (wire malformed / clock skew / nonce replay / HMAC mismatch) in addition to the v1 hash mismatch. Recovery guidance points Agents at v2.
- **§3.5.1 Streaming**: `NOT_STREAMABLE`, `STREAM_IN_PROGRESS`, `STREAM_TIMEOUT`, `PROVIDER_TIMEOUT` (streaming variant), `STREAM_INCOMPLETE`, `PROVIDER_DISCONNECT`.
- **§3.5.2 Composites**: `COMPOSITE_STEP_FAILED`, `COMPOSITE_BIND_ERROR`, `COMPOSITE_DEPTH_EXCEEDED`, `COMPOSITE_TIMEOUT`, `COMPOSITE_REFUND_FAILED`.

### Reference implementation alignment (informative)

- Hub Rust at `setsuna-jobdonebot.fly.dev` ships the streaming endpoint live (Phase A), the M2 key-rotation endpoints (`POST /v1/agents/me/rotate-key`, `POST /v1/providers/me/rotate-key`) — Phase B complete — and Provenance v2 dual-path verification from v53 (deployed 2026-05-10). Composite execution (M3) is spec-only in v1.0.0 of the spec; first reference implementation ships in v1.1 once the Hub workflow engine lands.
- Reference TS SDK `@jecpdev/sdk` exports `computeProvenanceV2` from v0.6.0+ (and a deprecated `computeProvenanceV1` for legacy callers).

### Migration from `1.0.0-draft`

There are no wire-breaking changes between `1.0.0-draft` and `1.0.0` — everything in this release is additive. Implementations that targeted the draft remain conformant.

- v1 `provenance_hash` (64-hex SHA-256) values continue to validate. Migration to v2 is RECOMMENDED but not required until 2026-11-01.
- `agent_id` / `api_key` regex widening is a relaxation: every value matching the old `^jdb_(ag|ak)_...` pattern matches the new vendor-prefix pattern.
- `Pricing.currency = "USD"` and `"USDC"` continue to validate; `"both"` continues to validate until 2026-11-01.
- If you hard-coded the `Status: Draft` strings somewhere, update to `Status: Stable`.

---

## v1.0.0-draft — 2026-05-07 — Initial draft

Initial public draft.

- §1–§9: wire format, error envelope, idempotency, sizes, timeouts.
- 02-authentication: `X-Agent-ID` + `X-API-Key`, Mandate, provenance hash, Trust Tier (bronze/silver/gold/platinum).
- 03-errors v1: AUTH/VALIDATION/ROUTING/BILLING/THROTTLING/PROVIDER/HUB error groups.
- 04-manifest v1: namespace + capability + actions + pricing + schemas + side_effects + sla + compliance + billing + deprecation.
- 05-discovery: GET /v1/capabilities catalog format.
