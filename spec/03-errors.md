# JECP — Error Catalog

**Spec Version**: 1.0.0
**Status**: Stable
**Companion**: 00-overview.md, 01-protocol.md

## 1. Abstract

This document specifies the complete error catalog for JECP v1.0. Every error response includes a stable `code`, a human-readable `message`, and an optional machine-readable `next_action` to guide automatic recovery.

## 2. Error Response Structure

All errors MUST follow this structure:

```json
{
  "jecp": "1.0",
  "id": "<request id, if available>",
  "status": "failed",
  "error": {
    "code": "<UPPER_SNAKE_CASE>",
    "message": "<human-readable, single line>",
    "details": { /* optional, code-specific */ },
    "documentation_url": "https://jecp.dev/errors/<lowercase-code>"
  },
  "next_action": { /* optional, see Section 4 */ }
}
```

The HTTP status code MUST match the error per Section 3.

## 3. Error Catalog

### 3.1 Authentication & Authorization (4xx)

#### `AUTH_REQUIRED`

- **HTTP**: 401
- **Cause**: No `X-Agent-ID` / `X-API-Key` headers and no `mandate.agent_id` / `mandate.api_key` fields
- **Retry-safe**: Yes (after registering)
- **Recovery**: Register an Agent first

#### `INVALID_API_KEY`

- **HTTP**: 401
- **Cause**: Provided `agent_id` and `api_key` do not match any registered Agent
- **Retry-safe**: No (re-check or re-register)
- **Recovery**: Verify credentials; if lost, re-register a new Agent

#### `MANDATE_EXPIRED`

- **HTTP**: 401
- **Cause**: `mandate.expires_at < now()`
- **Retry-safe**: Yes (with new mandate)
- **Recovery**: Issue a new Mandate with future `expires_at`

#### `MANDATE_INSUFFICIENT_BUDGET`

- **HTTP**: 402
- **Cause**: `mandate.budget_usdc < cost(capability, action)`
- **Retry-safe**: Yes (with higher budget)
- **`details`**: `{ "required_usdc": <number>, "remaining_usdc": <number> }`

Note: This is a per-call check in v1.0. Cumulative spend tracking is reserved for v1.1+.

#### `PROVENANCE_MISMATCH`

- **HTTP**: 403
- **Cause**: `mandate.provenance_hash` is invalid. Specific sub-causes:
  - **v2 hash** (`"v2:..."` prefix): wire format malformed, timestamp outside ±300s clock-skew window, nonce reused (replay defense), or HMAC tag mismatch
  - **v1 hash** (64 hex chars): SHA-256 input does not match server-computed value with the Agent's current `total_calls`
- **Retry-safe**: Yes (with a freshly-computed v2 hash and a fresh nonce)
- **Recovery**: Generate a new v2 `provenance_hash` (see 02-authentication.md §5.2) using a fresh nonce and the current unix-seconds timestamp. v1 is deprecated (sunset 2026-08-01) and SHOULD NOT be used for new code; see 02-authentication.md §5.7 for migration timing.

#### `INSUFFICIENT_TRUST`

- **HTTP**: 403
- **Cause**: Agent's Trust Tier is below capability's `trust_tier_required`
- **Retry-safe**: No (in current state)
- **`details`**: `{ "required": "<tier>", "current": "<tier>" }`
- **Recovery**: Use lower-tier capabilities to accumulate `total_calls`

### 3.2 Validation (4xx)

#### `INVALID_REQUEST`

- **HTTP**: 400
- **Cause**: Request body is not valid JSON, or top-level structure is malformed
- **Retry-safe**: No

#### `UNSUPPORTED_VERSION`

- **HTTP**: 400
- **Cause**: `jecp` field is not `"1.0"` (this Hub supports only v1.0)
- **Retry-safe**: No
- **`details`**: `{ "supported": ["1.0"], "received": "<value>" }`

#### `VALIDATION_FAILED`

- **HTTP**: 400
- **Cause**: `input` does not conform to the action's published JSON Schema
- **Retry-safe**: No (must fix input)
- **`details`**: `{ "errors": [{ "path": "<JSON pointer>", "reason": "<description>" }] }`

#### `INPUT_TOO_LARGE`

- **HTTP**: 413
- **Cause**: Request body exceeds Hub size limit (default 10 MB), or `metadata` exceeds 4 KB
- **Retry-safe**: No

#### `DUPLICATE_REQUEST`

- **HTTP**: 409
- **Cause**: A previous request with the same `id` and same Agent had different `input`, `capability`, or `action`
- **Retry-safe**: No (use a new `id`)

### 3.3 Routing (4xx)

#### `CAPABILITY_NOT_FOUND`

- **HTTP**: 404
- **Cause**: The `capability` does not exist on this Hub
- **Retry-safe**: No
- **Recovery**: Fetch `GET /v1/capabilities` to enumerate available capabilities

#### `ACTION_NOT_FOUND`

- **HTTP**: 404
- **Cause**: The `action` does not exist on the resolved capability
- **Retry-safe**: No
- **Recovery**: Fetch `GET /v1/capabilities/{capability}` to enumerate actions

#### `CAPABILITY_DEPRECATED`

- **HTTP**: 410
- **Cause**: The capability/action was removed or replaced
- **Retry-safe**: No
- **`details`**: `{ "successor": "<capability/action>" }` (when available)

#### `PROVIDER_NOT_FOUND`

- **HTTP**: 404
- **Cause**: A fully qualified `<namespace>/<capability>` references no registered Provider (Stage 3 feature)
- **Retry-safe**: No

### 3.4 Billing (402)

#### `WALLET_INSUFFICIENT_BALANCE`

- **HTTP**: 402
- **Code alias**: `INSUFFICIENT_BALANCE` (for symmetry; servers MAY emit either)
- **Cause**: Agent's wallet balance is below action cost; no Mandate provided as fallback
- **Retry-safe**: Yes (after topup)
- **`details`**: `{ "required_usdc": <number>, "remaining_usdc": <number> }`
- **Recovery**: Topup wallet via `POST {hub_origin}/api/agent/topup`

#### `PAYMENT_REQUIRED`

- **HTTP**: 402
- **Cause**: Free tier exhausted, no wallet balance, no Mandate
- **Retry-safe**: Yes (after topup)

### 3.5 Throttling (429)

#### `RATE_LIMITED`

- **HTTP**: 429
- **Cause**: Trust Tier rate limit exceeded (sliding 60s window)
- **Retry-safe**: Yes (after `Retry-After` seconds)
- **Headers**: `Retry-After: <seconds>`, `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`
- **`details`**: `{ "tier": "<bronze|silver|gold|platinum>", "limit_rpm": <int>, "reset_at": "<RFC 3339>" }`

### 3.5.1 Streaming (4xx / SSE event)

#### `NOT_STREAMABLE`

- **HTTP**: 406
- **Cause**: Request was sent with `Accept: text/event-stream` but the resolved capability action does not declare `streaming: true` in its manifest
- **Retry-safe**: Yes (resend without the streaming Accept header, or pick a streaming-capable action)
- **Recovery**: See 04-manifest.md §5 for the `streaming` flag

#### `STREAM_IN_PROGRESS`

- **HTTP**: 409
- **Cause**: A previous streaming request with the same `(agent_id, id)` is still open
- **Retry-safe**: Yes (after the first stream terminates)
- **Note**: Reserved for Phase B; Phase A Hubs MAY skip this check

#### `STREAM_TIMEOUT`

- **HTTP**: 200 (delivered as SSE `cancelled` event)
- **Cause**: Total stream duration exceeded the Hub's hard cap (5 minutes default)
- **Retry-safe**: Yes (with shorter expected duration)

#### `PROVIDER_TIMEOUT` (streaming)

- **HTTP**: 200 (delivered as SSE `cancelled` event)
- **Cause**: No progress from the Provider for the no-progress window (30 s default)
- **Retry-safe**: Yes; consider an alternative Provider

#### `STREAM_INCOMPLETE`

- **HTTP**: 200 (delivered as SSE `error` event)
- **Cause**: Provider closed the stream without emitting any of `completed`, `error`, or `cancelled`
- **Retry-safe**: Yes

#### `PROVIDER_DISCONNECT`

- **HTTP**: 200 (delivered as SSE `error` event)
- **Cause**: TCP read error from the Provider mid-stream
- **Retry-safe**: Yes (with backoff); persistent failures suggest selecting an alternative Provider

### 3.5.2 Composites (M3 / Workflow)

Errors specific to composite actions defined in 04-manifest.md §5.2.

#### `COMPOSITE_STEP_FAILED`

- **HTTP**: 502
- **Cause**: A sub-call inside the composite failed
- **Retry-safe**: Depends on the underlying error (see `details.upstream_error.code`)
- **`details`**: `{ "failed_step_id": "<step id>", "upstream_error": <full JECP error envelope>, "refunds_issued": <int>, "unrefunded_step_ids": [...] }`

#### `COMPOSITE_BIND_ERROR`

- **HTTP**: 422
- **Cause**: Template substitution referenced an unknown prior step or path
- **Retry-safe**: No (manifest configuration bug)

#### `COMPOSITE_DEPTH_EXCEEDED`

- **HTTP**: 422 (at publish) or 409 (at runtime if a sub-call resolves to another composite mid-flight)
- **Cause**: `max_depth` violated — v1.0 caps at 1
- **Retry-safe**: No

#### `COMPOSITE_TIMEOUT`

- **HTTP**: 504
- **Cause**: Composite total wall-clock exceeded `timeout_total_ms` (default 60 s, max 300 s)
- **Retry-safe**: Yes (with backoff)

#### `COMPOSITE_REFUND_FAILED`

- **HTTP**: 502
- **Cause**: With `on_step_failure=rollback`, the Hub could not refund every successful prior step within 5 s of failure. Operator alerts MUST fire.
- **Retry-safe**: No (escalation only)
- **`details`**: `{ "unrefunded_step_ids": [...], "manual_intervention_required": true }`

### 3.6 Provider Errors (5xx, Stage 3)

#### `PROVIDER_ERROR`

- **HTTP**: 502
- **Cause**: Provider returned an error
- **Retry-safe**: Depends; check Provider's `Retry-After` if present

#### `PROVIDER_UNAVAILABLE`

- **HTTP**: 503
- **Cause**: Provider failed health check or is offline
- **Retry-safe**: Yes (exponential backoff RECOMMENDED)

#### `PROVIDER_TIMEOUT`

- **HTTP**: 504
- **Cause**: Provider exceeded maximum execution time (default 30s, up to 300s for `workflow.*`)
- **Retry-safe**: Yes (once); avoid retrying expensive operations

### 3.7 Hub Errors (5xx)

#### `INTERNAL_ERROR`

- **HTTP**: 500
- **Cause**: Hub-side bug or unexpected condition
- **Retry-safe**: Yes (once)
- **Note**: The Hub MUST NOT include stack traces, internal hostnames, or database error text in `details`

#### `SERVICE_DEGRADED`

- **HTTP**: 503
- **Cause**: DB outage, Redis unavailable, etc.
- **Retry-safe**: Yes (with backoff)
- **Headers**: `Retry-After: <seconds>`

#### `EXECUTION_FAILED`

- **HTTP**: 500
- **Cause**: Capability handler threw an error not classified above
- **Retry-safe**: No (typically)
- **`details`**: Sanitized error message; never raw exception text

#### `OUTPUT_INVALID`

- **HTTP**: 502
- **Cause**: Capability handler returned output that does not match its declared `output_schema` (Provider bug)
- **Retry-safe**: No

## 4. `next_action` Object

Errors that have a clear recovery path SHOULD include a `next_action` object with machine-readable guidance.

### 4.1 Structure

```json
{
  "type": "<action type>",
  "ui": "<human-friendly URL>",
  "api": "<programmatic endpoint>",
  "method": "POST",
  "headers": ["X-Agent-ID", "X-API-Key"],
  "body_example": { /* sample body */ },
  "description": "<plain-language hint>"
}
```

Additional code-specific fields are permitted under the `extensions` key.

### 4.2 Standard `type` Values

| `type`            | Triggered by                                  | Required fields                          |
|-------------------|-----------------------------------------------|-------------------------------------------|
| `register`        | `AUTH_REQUIRED`, `INVALID_API_KEY`            | `ui`, `api`, `body_example`              |
| `topup`           | `WALLET_INSUFFICIENT_BALANCE`, `PAYMENT_REQUIRED` | `ui`, `api`, `allowed_amounts_usd`     |
| `earn_trust`      | `INSUFFICIENT_TRUST`                          | `current_tier`, `required_tier`, `fallback` |
| `renew_mandate`   | `MANDATE_EXPIRED`                             | `description`                             |
| `wait`            | `RATE_LIMITED`                                | `retry_after_seconds`                    |
| `lookup_schema`   | `VALIDATION_FAILED`, `ACTION_NOT_FOUND`       | `schema_url`                             |

### 4.3 Examples

#### `next_action` for `WALLET_INSUFFICIENT_BALANCE`:

```json
{
  "type": "topup",
  "ui": "https://jobdonebot.com/agent/topup",
  "api": "https://jobdonebot.com/api/agent/topup",
  "method": "POST",
  "headers": ["X-Agent-ID", "X-API-Key"],
  "body_example": { "amount": 5 },
  "allowed_amounts_usd": [5, 20, 100],
  "description": "Top up your wallet via Stripe Checkout"
}
```

#### `next_action` for `INSUFFICIENT_TRUST`:

```json
{
  "type": "earn_trust",
  "current_tier": "bronze",
  "required_tier": "platinum",
  "description": "Make 2000+ paid calls to unlock workflow capabilities",
  "fallback": {
    "alternative_capabilities": ["content-factory", "sns-engine"],
    "build_count_strategy": "Use lower-tier actions to accumulate total_calls"
  }
}
```

## 5. Client Behavior

Clients SHOULD:

- Read `next_action` and execute the indicated recovery automatically when safe.
- Apply exponential backoff on 5xx errors (initial 1s, 2x multiplier, max 60s).
- Honor `Retry-After` headers exactly.
- Log error responses for diagnostics; redact `api_key` and `mandate.api_key`.

Clients MUST NOT:

- Retry 4xx errors blindly (most are not retry-safe).
- Ignore `Retry-After` and hammer rate-limited endpoints.
- Display raw `error.message` to end-users without context (use `documentation_url` for support).

## 6. Telemetry

Hubs SHOULD emit metrics per error code (counter), per HTTP status (counter), and per (capability, action, error_code) tuple. Aggregate dashboards enable drift detection across deployments.

## 7. Backwards Compatibility

This is v1.0 of the error catalog. Future minor versions MAY:

- Add new `code` values
- Add new `next_action.type` values
- Add fields to existing error objects

They MUST NOT:

- Repurpose existing `code` values
- Change HTTP status mappings
- Remove `code` values within a major version (use `CAPABILITY_DEPRECATED` to retire)

## 8. References

- [RFC 7807](https://datatracker.ietf.org/doc/html/rfc7807) — Problem Details for HTTP APIs
- [RFC 6585](https://datatracker.ietf.org/doc/html/rfc6585) — HTTP 429 Too Many Requests

## 9. Authors

JECP Working Group. Contact: hello@jecp.dev.
