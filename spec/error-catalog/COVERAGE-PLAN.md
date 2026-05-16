# Error catalog coverage plan

Tracking item for the 15 error codes the reference Hub emits today that lack dedicated catalog pages. Backfill target: **v1.0.3**.

## Status

| Code | HTTP | Source ref (Hub) | Spec ref | Catalog page |
|---|---|---|---|---|
| `AGENT_NOT_FOUND` | 404 | `errors.rs::AgentNotFound` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `AUTH_REQUIRED` | 401 | `errors.rs::AuthRequired` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `DNS_VERIFICATION_FAILED` | 422 | `errors.rs::DnsVerificationFailed` | `spec/03-errors.md §3.9` | _TODO v1.0.3_ |
| `EXECUTION_FAILED` | 502 | `errors.rs::ExecutionFailed` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `FREE_TIER_EXHAUSTED` | 402 | `errors.rs::FreeTierExhausted` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `INSUFFICIENT_TRUST` | 403 | `errors.rs::InsufficientTrust` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `INTERNAL_ERROR` | 500 | `errors.rs::Internal` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `INVALID_API_KEY` | 401 | `errors.rs::InvalidApiKey` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `INVALID_REQUEST` | 400 | `errors.rs::InvalidRequest` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `MANDATE_EXPIRED` | 401 | `errors.rs::MandateExpired` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `PAYMENT_REQUIRED` | 402 | `errors.rs::PaymentRequired` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `PROVIDER_NOT_FOUND` | 404 | `errors.rs::ProviderNotFound` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `ROTATION_24H_CAP` | 429 | `errors.rs::Rotation24hCap` | `spec/03-errors.md §3.9` | _TODO v1.0.3_ |
| `ROTATION_RACE` | 409 | `errors.rs::RotationRace` | `spec/03-errors.md §3.9` | _TODO v1.0.3_ |
| `SERVICE_ERROR` | 502 | `errors.rs::ServiceError` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `UNKNOWN_ACTION` | 400 | `errors.rs::UnknownAction` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `UNKNOWN_CAPABILITY` | 400 | `errors.rs::UnknownCapability` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `UNSUPPORTED_VERSION` | 400 | `errors.rs::UnsupportedVersion` | `spec/03-errors.md` | _TODO v1.0.3_ |
| `VALIDATION_FAILED` | 400 | `errors.rs::ValidationFailed` | `spec/03-errors.md` | _TODO v1.0.3_ |

## Authoring guidelines

Each catalog page MUST follow the structure documented in [`README.md`](README.md#adding-a-new-error-code). Minimum sections:

- Header + frontmatter (public URL, spec source, last-updated)
- **What it means** — one paragraph with HTTP status
- **When it fires** — concrete trigger conditions
- **Response envelope** — JSON example showing `details` shape
- **Fix in 30s** — recovery checklist
- **Related errors** — cross-links to adjacent codes
- **Conformance** — list of conformance YAML assertions, if any

Backfill priority order (highest-traffic first):

1. `INVALID_REQUEST`, `VALIDATION_FAILED`, `AUTH_REQUIRED`, `INVALID_API_KEY` — most common Agent-side mistakes.
2. `PAYMENT_REQUIRED`, `FREE_TIER_EXHAUSTED`, `MANDATE_EXPIRED` — billing-adjacent codes that callers hit at scale.
3. `UNKNOWN_CAPABILITY`, `UNKNOWN_ACTION`, `UNSUPPORTED_VERSION`, `AGENT_NOT_FOUND` — routing/discovery codes.
4. `INSUFFICIENT_TRUST` — mandate trust-gate.
5. `EXECUTION_FAILED`, `SERVICE_ERROR`, `INTERNAL_ERROR` — server-side; ship last because the fix-in-30s is mostly "retry / contact Hub operator".

## Out-of-scope (intentional non-coverage)

None at the v1.0 baseline. All wire-format codes emitted by the reference Hub MUST have a catalog page by v1.0.3 or be removed from the Hub.
