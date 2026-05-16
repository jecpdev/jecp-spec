# Error catalog

Each file in this directory documents one JECP error code. Hub-emitted error envelopes include `error.details.documentation_url` deep-linking to a rendered version of the matching file at `https://jecp.dev/errors/<lowercase-code>` (with optional `#anchor` for sub-categorized codes).

These pages are the canonical source. The public website at jecp.dev is downstream — when the spec and the website disagree, the spec wins.

## Index

| File | HTTP status | When it fires |
|---|---|---|
| [`CAPABILITY_DEPRECATED.md`](CAPABILITY_DEPRECATED.md) | 410 | Capability past sunset date. `details.successor` names the replacement when one exists. |
| [`DUPLICATE_REQUEST.md`](DUPLICATE_REQUEST.md) | 409 | The idempotency `id` was reused for a different request body. |
| [`INPUT_SCHEMA_VIOLATION.md`](INPUT_SCHEMA_VIOLATION.md) | 400 | Action input failed the capability's published JSON Schema. `details.errors[]` enumerates each failed assertion. |
| [`INSUFFICIENT_BALANCE.md`](INSUFFICIENT_BALANCE.md) | 402 | Agent's wallet balance is below the action's quoted price. |
| [`INSUFFICIENT_BUDGET.md`](INSUFFICIENT_BUDGET.md) | 402 | `mandate.budget` cap was below the action's quoted price even though the wallet has funds. |
| [`PROVENANCE_MISMATCH.md`](PROVENANCE_MISMATCH.md) | 403 | `mandate.provenance_hash` failed verification. Six subcause anchors (`wire_malformed`, `clock_skew`, `hmac_mismatch`, `nonce_replay`, `v1_legacy_mismatch`, `v1_unavailable`). |
| [`RATE_LIMITED.md`](RATE_LIMITED.md) | 429 | Agent or source IP exceeded the per-window quota. `details.retry_after_seconds` mirrors the `Retry-After` header. |
| [`UNSUPPORTED_MEDIA_TYPE.md`](UNSUPPORTED_MEDIA_TYPE.md) | 415 | Request `Content-Type` was not `application/json`. |
| [`URL_BLOCKED_SSRF.md`](URL_BLOCKED_SSRF.md) | 422 | Agent-controlled URL hit the SSRF deny-list. Five reason anchors emitted by the reference Hub today (`parse_error`, `scheme`, `host_syntax`, `resolved_to_deny_cidr`, `dns_resolve_failed`) plus one reserved-for-v1.1.x (`connect_pin_violation`). |

## Coverage gap

The reference Hub (`jecp/src/protocol/errors.rs`) emits 24 distinct error codes. The index above documents 9 of them. The following 15 codes ship without dedicated catalog pages today and are scheduled to land in v1.0.3 — see [`COVERAGE-PLAN.md`](COVERAGE-PLAN.md) for backfill schedule and per-code authoring notes.

| Missing catalog page | HTTP status | Backfill target |
|---|---|---|
| `AGENT_NOT_FOUND` | 404 | v1.0.3 |
| `AUTH_REQUIRED` | 401 | v1.0.3 |
| `EXECUTION_FAILED` | 502 | v1.0.3 |
| `FREE_TIER_EXHAUSTED` | 402 | v1.0.3 |
| `INSUFFICIENT_TRUST` | 403 | v1.0.3 |
| `INTERNAL_ERROR` | 500 | v1.0.3 |
| `INVALID_API_KEY` | 401 | v1.0.3 |
| `INVALID_REQUEST` | 400 | v1.0.3 |
| `MANDATE_EXPIRED` | 401 | v1.0.3 |
| `PAYMENT_REQUIRED` | 402 | v1.0.3 |
| `SERVICE_ERROR` | 502 | v1.0.3 |
| `UNKNOWN_ACTION` | 400 | v1.0.3 |
| `UNKNOWN_CAPABILITY` | 400 | v1.0.3 |
| `UNSUPPORTED_VERSION` | 400 | v1.0.3 |
| `VALIDATION_FAILED` | 400 | v1.0.3 |

Until backfill lands, callers receiving these codes can find structured `details` field documentation in `spec/03-errors.md` and in the reference Hub source.

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
