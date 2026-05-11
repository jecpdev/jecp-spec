# JECP — Wire Format

**Spec Version**: 1.0.0
**Status**: Stable
**Companion**: 00-overview.md, 02-authentication.md, 03-errors.md

## 1. Abstract

This document defines the wire format for JECP requests and responses. It specifies the JSON Schema for the `POST /v1/invoke` endpoint, including request structure, response structure, and streaming responses.

## 2. Endpoint

The canonical execution endpoint is:

```
POST {hub_origin}/v1/invoke
```

Where `{hub_origin}` is the JECP Hub's HTTPS origin (e.g., `https://jecp.dev` or `https://setsuna-jobdonebot.fly.dev`).

Hubs MUST serve this endpoint over HTTPS. Plain HTTP MUST NOT be used.

The Hub MUST accept `Content-Type: application/json` (with optional `;charset=...` parameter) and MUST reject other content types with HTTP 415 `UNSUPPORTED_MEDIA_TYPE` (03-errors.md §3.2).

### 2.1 Legacy alias

The path `/v1/jecp` is a retained legacy alias. v1.0.0 and v1.0.1 of this specification published a contradiction (some sections referenced `/v1/jecp`, others `/v1/invoke`); v1.0.2 resolves the contradiction by promoting `/v1/invoke` to canonical and demoting `/v1/jecp` to a legacy alias.

Conformant Hubs:

- MUST accept `POST /v1/jecp` with semantics identical to `POST /v1/invoke` through the v1.x line.
- MUST attach `Deprecation: true` and `Sunset: Sat, 01 Jan 2028 00:00:00 GMT` response headers to every response served via the `/v1/jecp` path (regardless of status code), per RFC 8594.
- MUST attach `Link: <https://jecp.dev/spec/v1.0/01-protocol.md#21-legacy-alias>; rel="deprecation"` on the same responses.
- MAY include `error.details.endpoint_alias = "/v1/jecp (legacy; use /v1/invoke)"` on error envelopes served via the alias.
- MUST remove `/v1/jecp` at v2.0.

The alias is scheduled for sunset on 2028-01-01.

### 2.2 Migration note for spec readers

v1.0.2 reconciles a v1.0.0/v1.0.1 contradiction. Both endpoints work on conformant Hubs through the v1.x line, but new code SHOULD use `/v1/invoke`. Tooling generated against v1.0.0 or v1.0.1 that targeted `/v1/jecp` continues to function unchanged — agents observe the new `Deprecation` / `Sunset` response headers as their migration signal (RFC 8594).

## 3. Request

### 3.1 Headers

| Header             | Required | Description |
|--------------------|----------|-------------|
| `Content-Type`     | MUST     | `application/json` |
| `X-Agent-ID`       | SHOULD   | Agent identifier (also accepted in `mandate.agent_id`) |
| `X-API-Key`        | SHOULD   | Agent API key (also accepted in `mandate.api_key`) |
| `X-Request-ID`     | MAY      | Client-supplied request identifier; echoed in response |
| `X-Idempotency-Key`| MAY      | Override request body's `id` for idempotency |
| `Accept`           | MAY      | `application/json` (default) or `text/event-stream` for streaming |

If neither header nor `mandate` provides credentials, the Hub MUST respond with HTTP 401 `AUTH_REQUIRED`.

### 3.2 Body Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://jecp.dev/schemas/v1/request.json",
  "type": "object",
  "required": ["jecp", "id", "capability", "action", "input"],
  "additionalProperties": false,
  "properties": {
    "jecp":      { "type": "string", "const": "1.0" },
    "id":        { "type": "string", "pattern": "^[A-Za-z0-9_-]{4,64}$" },
    "capability":{ "type": "string", "pattern": "^[a-z][a-z0-9-]*(/[a-z][a-z0-9-]*)?$" },
    "action":    { "type": "string", "pattern": "^[a-z][a-z0-9-]*$" },
    "input":     { "type": "object" },
    "mandate":   { "$ref": "#/$defs/Mandate" },
    "delivery":  { "$ref": "#/$defs/Delivery" },
    "metadata":  { "type": "object" },
    "extensions":{ "type": "object" }
  },
  "$defs": {
    "Mandate":  { /* see 02-authentication.md */ },
    "Delivery": { /* see Section 3.5 */ }
  }
}
```

### 3.3 Field Definitions

#### `jecp`

- **Type**: string
- **Required**: MUST
- **Format**: literal value `"1.0"` (this spec)
- **Description**: Protocol version. Hubs MUST reject requests with mismatched major version. Hubs MUST reject unknown future versions with HTTP 400 `UNSUPPORTED_VERSION`.
- **Examples**:
  - Valid: `"1.0"`
  - Invalid: `"1"` (missing minor)
  - Invalid: `"v1.0"` (extra prefix)
  - Invalid: `"2.0"` (this Hub does not support v2)

#### `id`

- **Type**: string
- **Required**: MUST
- **Format**: 4–64 chars, `[A-Za-z0-9_-]+`
- **Description**: Idempotency key. The Hub MUST cache the result for at least 24 hours. A second request with the same `id` from the same Agent MUST return the cached result (HTTP 200) or a `DUPLICATE_REQUEST` error if `input` differs (HTTP 409).
- **Examples**:
  - Valid: `"req_a3f2b1"`, `"42"`, `"req-2026-05-07-001"`
  - Invalid: `"<3>"` (special chars), `""` (empty), `"x"` (too short)

#### `capability`

- **Type**: string
- **Required**: MUST
- **Format**: `<name>` for built-in, or `<namespace>/<name>` for Provider-supplied
- **Pattern**: `^[a-z][a-z0-9-]*(/[a-z][a-z0-9-]*)?$`
- **Description**: Identifies the capability. If the Hub has a built-in named `<name>` and no Provider with the same identifier, plain `<name>` resolves to the built-in. Once Stage 3 (Providers) is enabled, fully qualified `<namespace>/<name>` is RECOMMENDED to avoid ambiguity.
- **Examples**:
  - Valid: `"content-factory"`, `"deepl/translate"`, `"acme/payment"`
  - Invalid: `"Content-Factory"` (uppercase), `"content factory"` (space), `"content_factory"` (underscore)

#### `action`

- **Type**: string
- **Required**: MUST
- **Pattern**: `^[a-z][a-z0-9-]*$`
- **Description**: The specific operation within the capability. The Hub MUST return `ACTION_NOT_FOUND` (HTTP 404) if the action does not exist on the resolved capability.
- **Examples**:
  - Valid: `"generate-invoice"`, `"summarize"`, `"translate"`
  - Invalid: `"GenerateInvoice"`, `"summarize_text"`

#### `input`

- **Type**: object
- **Required**: MUST
- **Description**: Capability- and action-specific. The schema is published per action via `GET /v1/capabilities/{capability}` (see 05-discovery.md). The Hub MUST validate `input` against the published schema and return `VALIDATION_FAILED` (HTTP 400) on failure.

#### `mandate`

- **Type**: object
- **Required**: OPTIONAL
- **Description**: Per-call budget pre-authorization. See 02-authentication.md.

#### `delivery`

- **Type**: object
- **Required**: OPTIONAL
- **Default**: `{ "mode": "sync", "format": "base64" }`
- **Description**: Controls how artifacts are delivered. See Section 3.5.

#### `metadata`

- **Type**: object
- **Required**: OPTIONAL
- **Description**: Free-form metadata. Echoed in `result.metadata` if present. Use for end-user identification, session tracking, or analytics. The Hub MUST NOT interpret these fields.
- **Constraints**: Total serialized size MUST NOT exceed 4 KB. The Hub MAY reject with HTTP 413 `INPUT_TOO_LARGE`.

#### `extensions`

- **Type**: object
- **Required**: OPTIONAL
- **Description**: Forward-compatibility hatch. Future versions MAY define keys here without breaking v1.0 clients. Hubs MUST ignore unknown extension keys but SHOULD log them for telemetry.

### 3.3.1 The `payment` sibling field on 402 responses (v1.1.0)

When the Hub returns HTTP 402 with `error.code = PAYMENT_REQUIRED` (03-errors.md §3.4) AND the resolved capability accepts x402 (04-manifest.md §5 `pricing.payment_methods`), the response envelope MUST carry an OPTIONAL sibling `payment` field next to `error` (NOT inside `error.details`). The field carries the x402 challenge per 06-x402-integration.md §2: an `accepts[]` array of payment-requirement objects (`stripe-wallet` first, `exact` second), a `ttl_seconds`, and a `next_action.type = "x402_settle"` recovery hint. Old SDKs that do not parse the `payment` field silently ignore it (additive OPTIONAL field; JSON parsers tolerate unknown keys) and continue to recover via the existing top-level `next_action.type = "topup"` hint. The agent retries with the `X-Payment` request header (06-x402-integration.md §3) to settle on-chain via the configured x402 facilitator.

### 3.4 Capability ID Resolution

When `capability` lacks a `/`, the Hub resolves it as follows:

1. Look up Provider routing rules (Stage 3): if a routing rule matches, use it.
2. Else, look up built-in capability: if exists, use it.
3. Else, return `CAPABILITY_NOT_FOUND` (HTTP 404).

When `capability` contains a `/`, the Hub MUST treat it as `<provider_namespace>/<capability_name>`. If no Provider matches, the Hub MUST return `PROVIDER_NOT_FOUND` (HTTP 404).

### 3.5 Delivery Object

```json
{
  "mode":         "sync" | "stream" | "async",
  "format":       "base64" | "url" | "inline",
  "callback_url": "<RFC 3986 URI>"
}
```

- **`mode`** (default `sync`):
  - `sync`: Hub returns the result in the HTTP response body.
  - `stream`: Hub streams progress events as Server-Sent Events. Client MUST send `Accept: text/event-stream`.
  - `async`: Hub returns `202 Accepted` with a polling URL. (Stage 3 feature; v1.0 implementations MAY return `503` for `async`.)

- **`format`** (default `base64`):
  - `base64`: Binary artifacts are base64-encoded inside JSON.
  - `url`: Artifacts are stored on the Hub's blob storage and a signed URL is returned. URL TTL MUST be at least 1 hour.
  - `inline`: Same as `base64` for v1.0; reserved for future binary multipart formats.

- **`callback_url`** (only for `async`): RFC 3986 URI where the Hub POSTs the final result. MUST be HTTPS.

## 4. Response

### 4.1 Success Response (Sync)

HTTP 200, `Content-Type: application/json`:

```json
{
  "jecp": "1.0",
  "id": "<echoed from request>",
  "status": "completed",
  "result": {
    "capability": "<echoed>",
    "action": "<echoed>",
    "output": { /* action-specific schema */ },
    "metadata": { /* echoed from request, if any */ }
  },
  "billing": {
    "cost_usdc": 0.005,
    "method": "wallet" | "free_call" | "mandate",
    "balance_after": 4.995,
    "transaction_id": "<UUID>"
  },
  "execution": {
    "duration_ms": 127,
    "engine": "jecp-v1.0.0",
    "provider": "<provider namespace, if Stage 3>",
    "trust_tier": "bronze" | "silver" | "gold" | "platinum"
  }
}
```

### 4.2 Streaming Response

HTTP 200, `Content-Type: text/event-stream`:

```
event: status
data: {"state":"working","step":"validating","progress":0.1}

event: progress
data: {"state":"working","step":"executing","progress":0.5}

event: result
data: {"output":{...}}

event: done
data: {"status":"completed","billing":{...},"execution":{...}}
```

Each SSE event contains valid JSON. The `done` event marks completion. If an error occurs, the Hub MUST emit:

```
event: error
data: {"code":"...","message":"..."}
```

before closing the stream.

### 4.3 Provider Streaming on `/v1/invoke`

When an agent invokes a third-party Provider via `POST /v1/invoke` with `Accept: text/event-stream`, the Hub forwards the Provider's SSE stream back to the agent chunk-by-chunk. Billing settles when the Provider emits `completed`.

**Eligibility.** The capability action's manifest MUST declare `streaming: true` (see 04-manifest.md §5). A streaming request against a non-streaming action MUST return HTTP 406 `NOT_STREAMABLE`.

**Wire format.** The Hub serves `Content-Type: text/event-stream` with five event types:

```
event: open
data: {"request_id":"req-1","capability":"llm/chat","action":"complete"}

event: chunk
data: {"delta":"Hello","index":0}

event: meter
data: {"tokens":12,"elapsed_ms":340}

event: completed
data: {"result":{...},"billing":{"charged":true,"amount_usdc":...,"transaction_id":"tx-..."},"provider":{...},"meter_summary":{...}}
```

**Event types.**

| Event       | Direction | Cardinality       | Description |
|-------------|-----------|-------------------|-------------|
| `open`      | Hub → Agent      | 1, first event    | Connection to Provider established. |
| `chunk`     | Provider → Agent | 0..N              | Incremental output (`delta`, optional `index`). |
| `meter`     | Provider → Agent | 0..N              | Periodic usage update. Hub accumulates for Phase B variable pricing. |
| `completed` | Hub → Agent      | 0..1, terminal    | Stream ended successfully. Hub re-emits with billing info attached. |
| `error`     | Hub → Agent      | 0..1, terminal    | Stream ended with an error. |
| `cancelled` | Hub → Agent      | 0..1, terminal    | Stream cancelled by Hub (timeout, Mandate exhaustion, agent abort). |

Exactly one of `completed`, `error`, or `cancelled` MUST be the last event. If the connection drops without one, both Hub and agent MUST treat the stream as `cancelled`.

**Termination guarantees.**
- Streams are NOT replayable. A second request with the same `(agent_id, id)` while the first is still in progress returns HTTP 409 `STREAM_IN_PROGRESS` (Phase B). A completed stream returns the cached terminal events.
- Hubs MUST enforce a per-chunk no-progress timeout of at least 30 s and a total stream timeout of at most 5 minutes.
- Hubs MUST NOT internally buffer beyond OS kernel sockets — the path is true pass-through.

**Cancellation.** Closing the agent → Hub connection MUST close the Hub → Provider connection. Hubs MUST charge for delivered output up to the disconnect using the action's flat `pricing.base` (Phase A) or accumulated `meter` totals (Phase B).

### 4.4 Composite Action Execution (M3 / Workflow)

When `POST /v1/invoke` resolves to an action that declares `composes` in its manifest (04-manifest.md §5.2), the Hub orchestrates the composition server-side. The agent sees a single response — same shape as any other invoke — and is billed exactly once at the composite's `pricing.base`.

**Sequence**:

```
Agent ──POST /v1/invoke──▶ Hub
                          │ 1. preflight: auth, capability, pricing.base, trust, balance, mandate
                          │ 2. resolve composes.steps[]
                          │ 3. acquire wallet lock for pricing.base
                          │
                          │ For each step in order:
                          │   a. substitute ${input.*} and ${prior_step.*}
                          │   b. POST sub-Provider with derived request_id
                          │      = "<composite_request_id>:<step_id>"
                          │   c. record output → bound name
                          │   d. accumulate sub-revenue_split row (no agent charge)
                          │
                          │ 4. on success:
                          │      compose final result {step_id: output, …}
                          │      emit single transaction at pricing.base
                          │      sub-providers paid from gross via revenue_splits
                          │ 4'. on any step failure with on_step_failure=rollback:
                          │      stop; for every PRIOR successful step,
                          │      issue automatic refund (5 s budget);
                          │      return COMPOSITE_STEP_FAILED with the upstream error
                          │
Agent ◀──single response── Hub
```

**Determinism guarantees**:
- Steps execute strictly in declaration order (no parallelism in v1.0).
- Each sub-call's `request_id` is `<composite_request_id>:<step_id>` so Provider-side idempotency caches absorb retries cleanly.
- Whole-composite timeout is `composes.timeout_total_ms` (default 60 s, max 300 s).
- A single `transaction_id` is recorded for billing. Sub-call `revenue_splits` rows reference the same `transaction_id` with `composite_step_id` populated for audit.

**Constraints**:
- `composes` and `streaming: true` MUST NOT both be present (composites are not streamable in v1.0).
- `max_depth` MUST be 1 in v1.0. A sub-call resolving to another composite at runtime returns `COMPOSITE_DEPTH_EXCEEDED` (HTTP 409) and the wallet lock is released without charge.

### 4.5 Error Response

See 03-errors.md for the complete error catalog. Error responses follow this structure:

```json
{
  "jecp": "1.0",
  "id": "<echoed if available>",
  "status": "failed",
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "<human-readable>",
    "details": { /* optional, code-specific */ },
    "documentation_url": "https://jecp.dev/errors/insufficient-balance"
  },
  "next_action": { /* optional, see 03-errors.md */ }
}
```

### 4.6 Capability sunset

When a capability or action carries a `sunset_at` field in its manifest (04-manifest.md §5 `deprecation.sunset_at`) and that timestamp is in the past relative to the Hub's clock, the Hub MUST reject invocations of that capability/action with HTTP 410 `CAPABILITY_DEPRECATED` (03-errors.md §3.3) and MUST attach a `Sunset` response header in IMF-fixdate form (RFC 8594 §3) with the manifest's sunset timestamp.

Conformant Hubs MUST also attach:

- `Deprecation: true` (boolean form per IETF Deprecation HTTP Header draft)
- `Link: <https://jecp.dev/spec/v1.0/03-errors.md#capability-deprecated>; rel="deprecation"`
- `Link: <successor-capability-url>; rel="successor-version"` when the manifest declares a `successor_version`

These headers MUST also be attached to **successful 200 responses** for the 30 days preceding `sunset_at`, so Agents are notified before hard-fail. Specifically: if `(sunset_at - now()) <= 30 days` and the request would otherwise succeed, the Hub MUST attach the three headers to the 2xx response.

Hubs SHOULD log every CAPABILITY_DEPRECATED rejection at INFO level so operators can track migration pressure on each deprecated capability.

## 5. Idempotency

The Hub MUST implement idempotency for the `POST /v1/invoke` endpoint (and the `/v1/jecp` legacy alias):

1. Each request `id` is scoped to the authenticated `agent_id`.
2. A successful response is cached for at least 24 hours.
3. A second request with the same `(agent_id, id)` and identical `input`, `capability`, `action`:
   - MUST return the cached response with HTTP 200.
   - MUST NOT re-charge the agent.
4. A second request with the same `(agent_id, id)` but different `input`, `capability`, or `action`:
   - MUST return HTTP 409 `DUPLICATE_REQUEST`.

Hubs MAY use the `X-Idempotency-Key` header to override `id` for idempotency purposes only (the body `id` remains echoed in responses).

## 6. Concurrency

Multiple concurrent requests with the same `id` from the same agent: at most one MUST proceed; others MUST wait for the first to complete and receive the cached response.

This applies even across Hub instances; a distributed lock or atomic database operation is REQUIRED.

## 7. Maximum Sizes

| Field           | Maximum         | On exceed |
|-----------------|-----------------|-----------|
| Request body    | 10 MB           | HTTP 413 `INPUT_TOO_LARGE` |
| `input` field   | 5 MB            | HTTP 413 `INPUT_TOO_LARGE` |
| `metadata`      | 4 KB serialized | HTTP 413 |
| Response body   | 50 MB           | Hub MUST use `delivery.format=url` for larger |

## 8. Timeouts

| Phase                  | Default | Max  |
|------------------------|---------|------|
| Request body read      | 30 s    | 60 s |
| Capability execution   | 30 s    | 300 s (Workflow) |
| Streaming idle         | 30 s    | 60 s |

The Hub MUST emit a `408 Request Timeout` if the client fails to send the body within the read timeout, and `504 Gateway Timeout` (`PROVIDER_TIMEOUT`) if a Provider exceeds its deadline.

## 9. Examples

### 9.1 Generate Invoice (Sync)

Request:
```http
POST /v1/invoke HTTP/1.1
Host: jecp.dev
Content-Type: application/json
X-Agent-ID: jdb_ag_abc123
X-API-Key: jdb_ak_xxxxxxxxxxxxxxxxxxxxxxx

{
  "jecp": "1.0",
  "id": "req_a3f2b1",
  "capability": "document-pipeline",
  "action": "generate-invoice",
  "input": {
    "client_name": "ABC Corp",
    "items": [
      {"name": "Web Design", "quantity": 1, "unit_price": 500000, "tax_rate": 10}
    ],
    "due_date": "2026-06-30"
  }
}
```

Response:
```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "jecp": "1.0",
  "id": "req_a3f2b1",
  "status": "completed",
  "result": {
    "capability": "document-pipeline",
    "action": "generate-invoice",
    "output": {
      "pdf": "JVBERi0xLjQK...",
      "metadata": {
        "invoice_number": "INV-2026-0042",
        "total_amount": 550000,
        "tax_amount": 50000
      }
    }
  },
  "billing": {
    "cost_usdc": 0.005,
    "method": "wallet",
    "balance_after": 4.995,
    "transaction_id": "663a5426-244a-4c82-b1f1-775196bc15fa"
  },
  "execution": {
    "duration_ms": 127,
    "engine": "jecp-v1.0.0",
    "trust_tier": "silver"
  }
}
```

### 9.2 Summarize with Mandate (Sync)

Request:
```json
{
  "jecp": "1.0",
  "id": "req_b4c5d6",
  "capability": "content-factory",
  "action": "summarize",
  "input": { "text": "...", "max_length": 50 },
  "mandate": {
    "agent_id": "jdb_ag_abc123",
    "api_key": "jdb_ak_xxxxxxxxxxxxx",
    "budget_usdc": 0.10,
    "expires_at": "2026-12-31T23:59:59Z"
  },
  "metadata": {
    "end_user_id": "user_xyz",
    "session_id": "sess_42"
  }
}
```

Response includes `metadata` echoed back inside `result.metadata`.

### 9.3 Streaming Forecast

Request:
```http
POST /v1/invoke HTTP/1.1
Accept: text/event-stream
Content-Type: application/json
X-Agent-ID: jdb_ag_abc123
X-API-Key: jdb_ak_xxxxxxxxxxx

{
  "jecp": "1.0",
  "id": "req_e7f8g9",
  "capability": "data-insight",
  "action": "forecast",
  "input": { "csv": "...", "periods": 12 },
  "delivery": { "mode": "stream" }
}
```

Response (truncated):
```
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache

event: status
data: {"state":"working","step":"parsing","progress":0.1}

event: progress
data: {"state":"working","step":"forecasting","progress":0.6}

event: result
data: {"output":{"forecast":[...],"confidence_intervals":[...]}}

event: done
data: {"status":"completed","billing":{"cost_usdc":0.02,"method":"wallet","balance_after":4.975},"execution":{"duration_ms":1850}}
```

### 9.4 Error Response (Insufficient Balance)

```json
{
  "jecp": "1.0",
  "id": "req_x1y2z3",
  "status": "failed",
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "Wallet balance 0.001 < required 0.05",
    "details": { "required_usdc": 0.05, "remaining_usdc": 0.001 },
    "documentation_url": "https://jecp.dev/errors/insufficient-balance"
  },
  "next_action": {
    "type": "topup",
    "ui": "https://jobdonebot.com/agent/topup",
    "api": "https://jobdonebot.com/api/agent/topup",
    "method": "POST",
    "headers": ["X-Agent-ID", "X-API-Key"],
    "body_example": { "amount": 5 },
    "allowed_amounts_usd": [5, 20, 100]
  }
}
```

## 10. Backwards Compatibility

This is v1.0 of the wire format. Future minor versions (v1.1+) MAY add optional fields. They MUST NOT:

- Add required fields to Request or Response
- Change field types
- Remove fields
- Reuse field names with different semantics

A Hub serving multiple major versions MUST namespace them by URL path (`/v1/invoke`, `/v2/invoke`). The legacy alias `/v1/jecp` is removed at v2.0; v2.x serves `/v2/invoke` only.

## 11. Authors

JECP Working Group. Contact: hello@jecp.dev.
