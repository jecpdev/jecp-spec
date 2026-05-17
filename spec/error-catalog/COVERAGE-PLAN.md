# Error catalog coverage plan

Tracking item for the error codes the reference Hub emits that historically lacked dedicated catalog pages. Backfill target: **v1.0.3** — **DELIVERED 2026-05-17**.

## Status

All 19 codes below now have dedicated catalog pages. Branch on `code` string for portable behavior; HTTP status divergences between spec and reference Hub are annotated per-page and tracked for the next Hub patch release.

| Code | HTTP (Hub) | HTTP (spec) | Source ref (Hub) | Spec ref | Catalog page |
|---|---|---|---|---|---|
| `AGENT_NOT_FOUND` | 404 | 404 | `errors.rs::AgentNotFound` | `spec/03-errors.md §3.3` | [`AGENT_NOT_FOUND.md`](AGENT_NOT_FOUND.md) |
| `AUTH_REQUIRED` | 401 | 401 | `errors.rs::AuthRequired` | `spec/03-errors.md §3.1` | [`AUTH_REQUIRED.md`](AUTH_REQUIRED.md) |
| `DNS_VERIFICATION_FAILED` | 422 (spec-canonical) | 422 | `routes/providers.rs::verify_dns` | `spec/03-errors.md §3.9` | [`DNS_VERIFICATION_FAILED.md`](DNS_VERIFICATION_FAILED.md) |
| `EXECUTION_FAILED` | 500 | 502 | `errors.rs::ExecutionFailed` | `spec/03-errors.md §3.7` | [`EXECUTION_FAILED.md`](EXECUTION_FAILED.md) |
| `FREE_TIER_EXHAUSTED` | 429 | 402 | `errors.rs::FreeTierExhausted` | `spec/03-errors.md §3.4` | [`FREE_TIER_EXHAUSTED.md`](FREE_TIER_EXHAUSTED.md) |
| `INSUFFICIENT_TRUST` | 403 | 403 | `errors.rs::InsufficientTrust` | `spec/03-errors.md §3.1` | [`INSUFFICIENT_TRUST.md`](INSUFFICIENT_TRUST.md) |
| `INTERNAL_ERROR` | 500 | 500 | `errors.rs::Internal` | `spec/03-errors.md §3.7` | [`INTERNAL_ERROR.md`](INTERNAL_ERROR.md) |
| `INVALID_API_KEY` | 401 | 401 | `errors.rs::InvalidApiKey` | `spec/03-errors.md §3.1` | [`INVALID_API_KEY.md`](INVALID_API_KEY.md) |
| `INVALID_REQUEST` | 400 | 400 | `errors.rs::InvalidRequest` | `spec/03-errors.md §3.2` | [`INVALID_REQUEST.md`](INVALID_REQUEST.md) |
| `MANDATE_EXPIRED` | 402 | 401 | `errors.rs::MandateExpired` | `spec/03-errors.md §3.1` | [`MANDATE_EXPIRED.md`](MANDATE_EXPIRED.md) |
| `PAYMENT_REQUIRED` | 402 | 402 | `errors.rs::PaymentRequired` | `spec/03-errors.md §3.4` | [`PAYMENT_REQUIRED.md`](PAYMENT_REQUIRED.md) |
| `PROVIDER_NOT_FOUND` | 404 | 404 | `errors.rs::ProviderNotFound`* | `spec/03-errors.md §3.3` | [`PROVIDER_NOT_FOUND.md`](PROVIDER_NOT_FOUND.md) |
| `ROTATION_24H_CAP` | 429 | 429 | `routes/keys.rs` (inline) | `spec/03-errors.md §3.9` | [`ROTATION_24H_CAP.md`](ROTATION_24H_CAP.md) |
| `ROTATION_RACE` | 409 | 409 | `routes/keys.rs` (inline) | `spec/03-errors.md §3.9` | [`ROTATION_RACE.md`](ROTATION_RACE.md) |
| `SERVICE_ERROR` | 500 | 502 | `errors.rs::ServiceError` | `spec/03-errors.md §3.6` | [`SERVICE_ERROR.md`](SERVICE_ERROR.md) |
| `UNKNOWN_ACTION` | 400 | 404 | `errors.rs::UnknownAction` | `spec/03-errors.md §3.3` | [`UNKNOWN_ACTION.md`](UNKNOWN_ACTION.md) |
| `UNKNOWN_CAPABILITY` | 400 | 404 | `errors.rs::UnknownCapability` | `spec/03-errors.md §3.3` | [`UNKNOWN_CAPABILITY.md`](UNKNOWN_CAPABILITY.md) |
| `UNSUPPORTED_VERSION` | 400 | 400 | `errors.rs::UnsupportedVersion` | `spec/03-errors.md §3.2` | [`UNSUPPORTED_VERSION.md`](UNSUPPORTED_VERSION.md) |
| `VALIDATION_FAILED` | 400 | 400 | `errors.rs::ValidationFailed` | `spec/03-errors.md §3.2` | [`VALIDATION_FAILED.md`](VALIDATION_FAILED.md) |

\* `PROVIDER_NOT_FOUND` is reserved in the spec for Stage 3 namespace lookups; the reference Hub's `errors.rs` does not enumerate it as a `JecpErrorCode` variant yet (it is emitted inline by the Stage 3 routing handler). Hub harmonization is tracked for the next patch.

## Spec / Hub divergence audit

The following codes have HTTP status mappings where the reference Hub differs from `spec/03-errors.md`:

| Code | Spec | Hub | Resolution path |
|---|---|---|---|
| `EXECUTION_FAILED` | 502 | 500 | Hub patch to 502 in next release (canonical Bad Gateway for handler failure) |
| `SERVICE_ERROR` | 502 | 500 | Same — Hub patch to 502 |
| `FREE_TIER_EXHAUSTED` | 402 | 429 | Pending discussion: 429 better expresses quota nature, but spec aligns with billing family 402 |
| `MANDATE_EXPIRED` | 401 | 402 | Hub treats mandate expiry as a billing-family failure (no payment authorization); spec maps to 401 (no valid auth). Pending discussion |
| `UNKNOWN_ACTION` | 404 | 400 | Hub treats unknown id as "bad request field"; spec treats it as "no such resource." Both reasonable; Hub harmonization to 404 likely in next patch |
| `UNKNOWN_CAPABILITY` | 404 | 400 | Same as `UNKNOWN_ACTION` |

The catalog pages document the **Hub-emitted status** as authoritative for callers writing against the live wire, but note the spec-canonical mapping inline. All pages instruct clients to branch on `code` rather than HTTP status for portable behavior.

## Authoring guidelines

Each catalog page MUST follow the structure documented in [`README.md`](README.md#adding-a-new-error-code). Minimum sections:

- Header + frontmatter (public URL, spec source, last-updated)
- **What it means** — one paragraph with HTTP status
- **When it fires** — concrete trigger conditions
- **Response envelope** — JSON example showing `details` shape
- **Fix in 30s** — recovery checklist
- **Related errors** — cross-links to adjacent codes
- **Conformance** — list of conformance YAML assertions, if any

## Out-of-scope (intentional non-coverage)

None at the v1.0 baseline. All wire-format codes emitted by the reference Hub now have a catalog page as of v1.0.3 (2026-05-17 backfill).

## Future work

- Hub-side patches to align HTTP status divergences listed in the audit table above.
- Spec-side `details.*` field tightening for `INVALID_REQUEST`, `UNSUPPORTED_VERSION`, `VALIDATION_FAILED` — the reference Hub currently emits message-only for these; spec recommends structured `details` for parity with `INPUT_SCHEMA_VIOLATION`.
- The reference Hub's `verify_dns` route currently returns `200 OK` with `verified: false` in the body rather than emitting the spec-canonical `DNS_VERIFICATION_FAILED` error envelope. Hub harmonization tracked for v1.0.3 patch.
