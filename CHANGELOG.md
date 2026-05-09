# JECP Specification — Changelog

This file tracks changes to the JECP wire protocol, error catalog, and manifest schema.

The repository follows [SemVer](https://semver.org). Major versions break wire compatibility; minor versions add backward-compatible features; patch versions clarify or fix non-normative wording.

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
