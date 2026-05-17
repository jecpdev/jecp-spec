# Error catalog

Each file in this directory documents one JECP error code. Hub-emitted error envelopes include `error.details.documentation_url` deep-linking to a rendered version of the matching file at `https://jecp.dev/errors/<lowercase-code>` (with optional `#anchor` for sub-categorized codes).

These pages are the canonical source. The public website at jecp.dev is downstream — when the spec and the website disagree, the spec wins.

## Index

| File | HTTP status | When it fires |
|---|---|---|
| [`AGENT_NOT_FOUND.md`](AGENT_NOT_FOUND.md) | 404 | `agent_id` doesn't match a registered Agent. |
| [`AUTH_REQUIRED.md`](AUTH_REQUIRED.md) | 401 | No `X-Agent-ID` / `X-API-Key` headers and no mandate credentials. Carries `next_action.type = "register"`. |
| [`CAPABILITY_DEPRECATED.md`](CAPABILITY_DEPRECATED.md) | 410 | Capability past sunset date. `details.successor` names the replacement when one exists. |
| [`DNS_VERIFICATION_FAILED.md`](DNS_VERIFICATION_FAILED.md) | 422 | Provider `verify-dns` could not find the `_jecp.<domain>` TXT record. Three reason anchors (`txt_record_missing`, `txt_record_mismatch`, `nxdomain`). |
| [`DUPLICATE_REQUEST.md`](DUPLICATE_REQUEST.md) | 409 | The idempotency `id` was reused for a different request body. |
| [`EXECUTION_FAILED.md`](EXECUTION_FAILED.md) | 500 (spec: 502) | Capability handler threw an error not classified into a more specific code. |
| [`FREE_TIER_EXHAUSTED.md`](FREE_TIER_EXHAUSTED.md) | 429 (spec: 402) | Agent's free quota consumed and no other funding source attached. |
| [`INPUT_SCHEMA_VIOLATION.md`](INPUT_SCHEMA_VIOLATION.md) | 400 | Action input failed the capability's published JSON Schema. `details.errors[]` enumerates each failed assertion. |
| [`INSUFFICIENT_BALANCE.md`](INSUFFICIENT_BALANCE.md) | 402 | Agent's wallet balance is below the action's quoted price. |
| [`INSUFFICIENT_BUDGET.md`](INSUFFICIENT_BUDGET.md) | 402 | `mandate.budget` cap was below the action's quoted price even though the wallet has funds. |
| [`INSUFFICIENT_TRUST.md`](INSUFFICIENT_TRUST.md) | 403 | Agent's trust tier below action's `trust_tier_required`. Carries `next_action.type = "earn_trust"`. |
| [`INTERNAL_ERROR.md`](INTERNAL_ERROR.md) | 500 | Hub-side bug or unexpected condition; message sanitized per spec §3.7. |
| [`INVALID_API_KEY.md`](INVALID_API_KEY.md) | 401 | `(agent_id, api_key)` supplied but the api_key didn't verify. Message deliberately opaque (no enumeration oracle). |
| [`INVALID_REQUEST.md`](INVALID_REQUEST.md) | 400 | Body didn't parse as JSON, or top-level envelope structurally broken. |
| [`MANDATE_EXPIRED.md`](MANDATE_EXPIRED.md) | 402 (spec: 401) | `mandate.expires_at` is in the past. Carries `next_action.type = "renew_mandate"`. |
| [`PAYMENT_REQUIRED.md`](PAYMENT_REQUIRED.md) | 402 | Generic 402: no funding source applies. Carries `next_action.type = "topup"` and a `payment` sibling for x402. |
| [`PROVENANCE_MISMATCH.md`](PROVENANCE_MISMATCH.md) | 403 | `mandate.provenance_hash` failed verification. Six subcause anchors (`wire_malformed`, `clock_skew`, `hmac_mismatch`, `nonce_replay`, `v1_legacy_mismatch`, `v1_unavailable`). |
| [`PROVIDER_NOT_FOUND.md`](PROVIDER_NOT_FOUND.md) | 404 | Namespace portion of a fully-qualified capability has no registered Provider (Stage 3 feature). |
| [`RATE_LIMITED.md`](RATE_LIMITED.md) | 429 | Agent or source IP exceeded the per-window quota. `details.retry_after_seconds` mirrors the `Retry-After` header. |
| [`ROTATION_24H_CAP.md`](ROTATION_24H_CAP.md) | 429 | Provider/Agent rotation rate-limit (default 3 / 24h sliding window). |
| [`ROTATION_RACE.md`](ROTATION_RACE.md) | 409 | Concurrent rotation race lost at the row-lock layer. Retry-safe with backoff. |
| [`SERVICE_ERROR.md`](SERVICE_ERROR.md) | 500 (spec: 502) | Upstream Provider unreachable or returned bare 5xx. |
| [`UNKNOWN_ACTION.md`](UNKNOWN_ACTION.md) | 400 (spec: 404) | Capability resolved, named action does not exist on it. |
| [`UNKNOWN_CAPABILITY.md`](UNKNOWN_CAPABILITY.md) | 400 (spec: 404) | `capability` field doesn't match any entry in the Hub's registry. |
| [`UNSUPPORTED_MEDIA_TYPE.md`](UNSUPPORTED_MEDIA_TYPE.md) | 415 | Request `Content-Type` was not `application/json`. |
| [`UNSUPPORTED_VERSION.md`](UNSUPPORTED_VERSION.md) | 400 | `jecp` field is not a version this Hub supports. |
| [`URL_BLOCKED_SSRF.md`](URL_BLOCKED_SSRF.md) | 422 | Agent-controlled URL hit the SSRF deny-list. Five reason anchors emitted by the reference Hub today (`parse_error`, `scheme`, `host_syntax`, `resolved_to_deny_cidr`, `dns_resolve_failed`) plus one reserved-for-v1.1.x (`connect_pin_violation`). |
| [`VALIDATION_FAILED.md`](VALIDATION_FAILED.md) | 400 | Envelope parsed but a specific field violated its declared constraint. |

## Coverage

The reference Hub (`jecp/src/protocol/errors.rs`) emits ~28 distinct error codes today. The index above documents all wire-format codes emitted on agent-facing surfaces plus the Stage 3 Provider self-service codes (`DNS_VERIFICATION_FAILED`, `ROTATION_24H_CAP`, `ROTATION_RACE`). The v1.0.3 backfill is complete; see [`COVERAGE-PLAN.md`](COVERAGE-PLAN.md) for the delivered list.

Several codes carry an HTTP status divergence between `spec/03-errors.md` and the reference Hub's actual emission (annotated `(spec: NNN)` in the index above). Branch on the `code` string, not the HTTP status, for portable behavior. Hub patches to align with the spec are tracked for the next minor release.

## Adding a new error code

When the spec adds a new error code:

1. Define the code, HTTP status, and any structured `details` fields in `spec/03-errors.md`.
2. Add a catalog file here. Follow the structure used by the existing files:
   - Header `# \`CODE_NAME\``
   - Frontmatter quote block: public URL, spec source pointer, last-updated date.
   - **What it means** — one paragraph, HTTP status, and when the error fires.
   - **Response envelope** — a concrete JSON example.
   - **Fix in 30s** — concrete recovery action(s).
   - **Why the Hub …** — design rationale (helps operators predict behavior).
   - **Related errors** — cross-links to adjacent codes.
3. If the code has sub-categories (a closed-registry `subcause` or `reason` field), include an anchored section per value so the deep-link form `https://jecp.dev/errors/<code>#<sub>` lands at the right row.
4. Mirror the entry on the public website at `jecpdev/website/errors/<code>.html` for browser-readable rendering.

## File naming

Filenames use `UPPER_SNAKE_CASE.md` — matching the code itself. The website route uses `lower_snake_case` for the public URL (so `URL_BLOCKED_SSRF.md` is mirrored at `https://jecp.dev/errors/url_blocked_ssrf`). This split is intentional: the catalog file mirrors the wire constant; the URL mirrors web convention.
