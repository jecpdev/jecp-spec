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
- **Cause**: `mandate.provenance_hash` is invalid. The error response carries an OPTIONAL `details.subcause` field from the **closed registry** below. Hubs MAY omit `details.subcause`; if present, it MUST be one of the registered values. New values are added by spec patch only; clients MUST treat unknown subcauses as the parent code (`PROVENANCE_MISMATCH`).
- **Retry-safe**: Yes (with a freshly-computed v2 hash and a fresh nonce)
- **Recovery**: Generate a new v2 `provenance_hash` (see 02-authentication.md §5.2) using a fresh nonce and the current unix-seconds timestamp. v1 is deprecated (sunset 2026-11-01) and SHOULD NOT be used for new code; see 02-authentication.md §5.7 for migration timing.

##### `details.subcause` registry (spec v1.0.1)

| Subcause | Meaning | Recovery hint |
|---|---|---|
| `wire_malformed` | The `provenance_hash` value does not match the §4.2 regex (e.g. v2 missing prefix, bad timestamp parse, nonce shorter than 16 hex chars, non-hex nonce, missing HMAC tag, or v1 length ≠ 64). | Recompute via SDK helper (`computeProvenanceV2` / `verifyProvenanceV2` reject malformed wire client-side). |
| `clock_skew` | v2 timestamp is outside the ±300s clock-skew window. Hub also returns `details.drift_seconds` (signed: `now − timestamp`). | Synchronize NTP on the Agent host. The window MUST NOT be widened by Hubs. |
| `hmac_mismatch` | v2 HMAC tag does not match the value the Hub recomputed using `mandate.api_key`. | Confirm the api_key the Agent signs with is identical to the one in `mandate.api_key`. Common cause: stale rotation grace key. |
| `nonce_replay` | The `(agent_id, nonce)` tuple was already seen in the past 600s. | Generate a fresh nonce (≥ 16 random hex chars) per request — never reuse. |
| `v1_legacy_mismatch` | v1 SHA-256 hash does not match the server-recomputed value (Agent's `total_calls` is likely stale). | Migrate to v2; v1 cannot be made replay-safe. |
| `v1_unavailable` | v1 was attempted on a rotated Agent — the Hub no longer stores the plaintext `api_key` prefix needed to recompute v1. | Migrate to v2 immediately (see 02-authentication.md §5.8 — the migration recipe). |

The `details.documentation_url` field, when present, is a deep-link of the form `https://jecp.dev/errors/provenance_mismatch#<subcause>` and points to the same row in the catalog page.

##### Subcause emission policy

A Hub MUST NOT emit `details.subcause` until after it has verified the Agent's `api_key` against the stored credential (i.e., a request whose `X-API-Key` did not match the hashed credential MUST receive a generic `PROVENANCE_MISMATCH` without subcause). This prevents the subcause from acting as an enumeration oracle for unauthenticated callers.

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
- **Cause**: Envelope-level violation (missing `jecp`, malformed `id`, structurally invalid request body). For action-level input schema violations, see `INPUT_SCHEMA_VIOLATION` below.
- **Retry-safe**: No (must fix request body)
- **`details`**: `{ "errors": [{ "path": "<JSON pointer>", "reason": "<description>" }] }`

#### `INPUT_SCHEMA_VIOLATION`

- **HTTP**: 400
- **Cause**: `input` is syntactically valid JSON and parses against the request envelope, but does not satisfy the action's published `input_schema` (04-manifest.md §5).
- **Retry-safe**: No (must fix input)
- **`details`**: `{ "errors": [{ "instance_path": "<JSON pointer to offending value>", "schema_path": "<JSON pointer to violated schema rule>", "reason": "<human-readable>" }], "schema_url": "https://<hub>/v1/capabilities/<id>#input_schema" }`
- **Note**: `INPUT_SCHEMA_VIOLATION` (action-level) is distinct from `VALIDATION_FAILED` (envelope-level). Both are HTTP 400; the code distinguishes the layer where the violation occurred so SDKs can surface clearer diagnostics. New in spec v1.0.2.

#### `UNSUPPORTED_MEDIA_TYPE`

- **HTTP**: 415
- **Cause**: Request `Content-Type` is not `application/json` (parameters such as `; charset=utf-8` are accepted). Empty / missing `Content-Type` is implementation-defined: Hubs MAY tolerate it for backward compatibility, but SHOULD log + warn. The streaming response negotiation (`Accept: text/event-stream`) is independent of request `Content-Type`.
- **Retry-safe**: Yes (after fixing `Content-Type`)
- **`details`**: `{ "received": "<value>", "expected": "application/json" }`
- **Note**: New in spec v1.0.2.

#### `INPUT_TOO_LARGE`

- **HTTP**: 413
- **Cause**: Request body exceeds Hub size limit (default 10 MB), or `metadata` exceeds 4 KB
- **Retry-safe**: No

#### `DUPLICATE_REQUEST`

- **HTTP**: 409 (per RFC 9110 §15.5.10 — request conflicts with existing idempotency state)
- **Cause**: A previous request with the same `id` and same Agent recorded a different `input`, `capability`, or `action` within the idempotency window. Per spec §5, idempotent retries with identical payloads MUST return the cached response, not 409. 409 fires only on conflict (same id, different payload).
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
- **Cause**: The capability/action's `sunset_at` (per its manifest, 04-manifest.md §5) is in the past relative to the Hub's clock.
- **Retry-safe**: No
- **`details`**: `{ "successor": "<capability/action>", "sunset_at": "<RFC 3339>" }` (when available)
- **Headers (MUST)**: Hubs MUST attach the following per RFC 8594 (`Sunset`) and the IETF `Deprecation` HTTP Header draft:
  - `Sunset: <IMF-fixdate>` — the manifest's `sunset_at` reformatted to IMF-fixdate.
  - `Deprecation: true` — boolean form (NOT timestamp).
  - `Link: <https://jecp.dev/spec/v1.0/03-errors.md#capability-deprecated>; rel="deprecation"`.
  - `Link: <successor-capability-url>; rel="successor-version"` — when a successor is registered in the manifest.
- **Pre-sunset notice**: Conformant Hubs MUST also attach the four headers above to **successful 2xx responses** for the 30 days preceding `sunset_at` (i.e., when `(sunset_at - now()) <= 30 days` and the request would otherwise succeed). Agents observe these headers as their migration alarm.

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
- **Retry-safe**: Yes (after topup or via x402 settlement)
- **`payment` sibling**: When the resolved capability accepts x402 (per `payment_methods` on its manifest, 04-manifest.md §5), the Hub MUST attach an OPTIONAL sibling `payment` field on the error envelope (NOT inside `details`) carrying the x402 challenge. See 06-x402-integration.md §2 for the wire shape. Old SDKs that do not parse the `payment` field continue to use the wallet path via `next_action.type = "topup"`. New in v1.1.0.

### 3.5 Throttling (429)

#### `RATE_LIMITED`

- **HTTP**: 429
- **Cause**: Trust Tier rate limit exceeded (sliding 60s window)
- **Retry-safe**: Yes (after `Retry-After` seconds)
- **Headers (MUST)**: `Retry-After: <integer-seconds>` per RFC 9110 §10.2.3, integer form (delta-seconds, not HTTP-date). The value MUST be in `[1, 600]`; 0 is invalid.
- **Headers (SHOULD)**: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` (de-facto convention; reserved for v1.0.3 normative tightening)
- **`details`**: `{ "tier": "<bronze|silver|gold|platinum>", "limit_rpm": <int>, "retry_after_seconds": <int>, "reset_at": "<RFC 3339>" }` — `retry_after_seconds` mirrors the header and is informational for clients that don't read response headers.

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

### 3.8 x402 Settlement (4xx / 5xx)

These error codes are introduced in spec v1.1.0 alongside the x402 integration (06-x402-integration.md). They fire only on x402-enabled Hubs that advertise `"x402"` in any capability's `payment_methods` (04-manifest.md §5). Hubs that do not configure x402 never emit these codes.

The `details.subcause` field on each code is drawn from a **closed registry** (§3.8.6). Hubs MAY emit `details.subcause`; if present it MUST be one of the registered values. New values are added by spec patch only; clients MUST treat unknown subcauses as the parent code.

#### `X402_PAYMENT_INVALID`

- **HTTP**: 422
- **Cause**: The agent's `X-Payment` header is structurally well-formed at the JECP layer but the facilitator (or the Hub's pre-facilitator validation) rejected the inner payload. Subcauses cover signature failure, amount mismatch, expiry, payee mismatch, header size violation, header duplication, malleable signatures, and binding violations.
- **Retry-safe**: Yes (with a corrected `X-Payment`)
- **`details`**: `{ "subcause": "<one of the values in §3.8.6>", "facilitator_message": "<optional verbatim from facilitator>", "documentation_url": "https://jecp.dev/errors/x402_payment_invalid#<subcause>" }`
- **Recovery**: Per subcause; see §3.8.6.

#### `X402_NOT_ACCEPTED`

- **HTTP**: 422
- **Cause**: The agent presented an `X-Payment` header but the resolved capability does not declare `"x402"` in its `pricing.payment_methods`. Also fires when the Hub's kill switch (`feature_flags.x402_enabled = false`, 06-x402-integration.md §6.3) is engaged and any agent attempts an x402 invocation.
- **Retry-safe**: No (re-route to wallet path)
- **`details`**: `{ "accepted": ["stripe"], "received": "x402", "subcause": "capability_wallet_only" | "x402_disabled" | "network_unsupported" }`
- **Recovery**: Drop `X-Payment` and use the wallet path, OR pick a different capability.

#### `X402_SETTLEMENT_TIMEOUT`

- **HTTP**: 504
- **Cause**: The Hub's facilitator call (`/verify` or `/settle`) did not return within the configured timeout (5 s default). Either the facilitator is slow or the underlying chain is congested.
- **Retry-safe**: Yes (after backoff)
- **`details`**: `{ "facilitator_url": "<https URL>", "elapsed_ms": <int>, "subcause": "facilitator_slow" | "chain_congested" }`
- **Headers (MUST)**: `Retry-After: <integer-seconds>` per RFC 9110 §10.2.3.
- **`next_action`**: SHOULD point the agent at the wallet (`stripe-wallet`) fallback path.

#### `X402_FACILITATOR_UNREACHABLE`

- **HTTP**: 502
- **Cause**: The Hub could not reach the trusted facilitator. Distinct from `X402_SETTLEMENT_TIMEOUT` (which is a slow successful connection). Subcauses cover DNS failure, TCP refusal, TLS cert pin mismatch, and Ed25519 response signature pin mismatch.
- **Retry-safe**: Yes (after backoff) — except subcauses `cert_pin_mismatch` and `signature_pin_mismatch` which indicate ongoing facilitator compromise; the operator MUST investigate before further x402 traffic flows.
- **`details`**: `{ "facilitator_url": "<https URL>", "subcause": "dns_fail" | "connection_refused" | "cert_pin_mismatch" | "signature_pin_mismatch", "last_error": "<sanitized one-line>" }`
- **Headers**: `Retry-After: <integer-seconds>` (SHOULD).
- **`next_action`**: SHOULD point the agent at the wallet (`stripe-wallet`) fallback path.

#### `X402_SETTLEMENT_REUSED`

- **HTTP**: 409
- **Cause**: The same settlement payload (or its EIP-3009 `nonce`, or the resulting `tx_hash`) was already recorded for a different `(agent_id, request_id)`. Per ADR-0004, the Hub maintains UNIQUE constraints on `(payer, eip3009_nonce)` AND on `tx_hash` in the `x402_settlements` table.
- **Retry-safe**: No (use a fresh `X-Payment` with a fresh `nonce`)
- **`details`**: `{ "tx_hash": "0x<64-hex>", "original_request_id": "<echoed>", "original_settled_at": "<RFC 3339>", "subcause": "tx_hash_seen" | "nonce_reused" }`
- **`next_action`**: `{ "type": "x402_settle", "hint": "Generate a new EIP-3009 authorization with a fresh nonce, base64-encode the new envelope, and retry." }`

##### Example: `X402_PAYMENT_INVALID`

```json
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json

{
  "jecp": "1.0",
  "id": "req_abc123",
  "status": "failed",
  "error": {
    "code": "X402_PAYMENT_INVALID",
    "message": "X-Payment signature is invalid: signer 0xabc... does not match `from` 0xdef...",
    "details": {
      "subcause": "signature_invalid",
      "facilitator_message": "EIP-712 recover yielded 0xabc..., expected 0xdef...",
      "documentation_url": "https://jecp.dev/errors/x402_payment_invalid#signature_invalid"
    }
  }
}
```

##### Example: `X402_SETTLEMENT_REUSED`

```json
HTTP/1.1 409 Conflict
Content-Type: application/json

{
  "jecp": "1.0",
  "id": "req_abc123",
  "status": "failed",
  "error": {
    "code": "X402_SETTLEMENT_REUSED",
    "message": "This X-Payment was already settled for request req_b4c5d6 at 2026-05-11T10:00:00Z. Construct a fresh authorization.",
    "details": {
      "tx_hash": "0x12345abcdef...",
      "original_request_id": "req_b4c5d6",
      "original_settled_at": "2026-05-11T10:00:00Z",
      "subcause": "nonce_reused",
      "documentation_url": "https://jecp.dev/errors/x402_settlement_reused"
    }
  },
  "next_action": {
    "type": "x402_settle",
    "hint": "Generate a new EIP-3009 authorization with a fresh nonce, base64-encode the new envelope, and retry."
  }
}
```

##### Example: `X402_FACILITATOR_UNREACHABLE`

```json
HTTP/1.1 502 Bad Gateway
Content-Type: application/json
Retry-After: 30

{
  "jecp": "1.0",
  "id": "req_abc123",
  "status": "failed",
  "error": {
    "code": "X402_FACILITATOR_UNREACHABLE",
    "message": "x402 facilitator at https://x402.org/facilitator returned 502 twice; settlement aborted. Retry in 30s or top up wallet to use the wallet payment method instead.",
    "details": {
      "facilitator_url": "https://x402.org/facilitator",
      "subcause": "connection_refused",
      "last_error": "upstream_5xx",
      "documentation_url": "https://jecp.dev/errors/x402_facilitator_unreachable"
    }
  },
  "next_action": {
    "type": "topup",
    "ui": "https://jecp.dev/account/topup",
    "hint": "x402 settlement is currently degraded. Top up the wallet to use the alternative payment method."
  }
}
```

#### 3.8.6 `details.subcause` registry (closed)

Per the spec convention established by `PROVENANCE_MISMATCH` (§3.1) and `URL_BLOCKED_SSRF` (`error-catalog/URL_BLOCKED_SSRF.md`), the x402 errors carry a closed-registry `subcause` field. New values MUST be added by spec patch. Clients MUST treat unknown subcauses as the parent code and preserve forward-compatibility.

| Subcause | Parent code | When raised |
|---|---|---|
| `signature_invalid` | `X402_PAYMENT_INVALID` | Facilitator's ECDSA verify failed (recovered signer ≠ `from`). |
| `signature_malleable` | `X402_PAYMENT_INVALID` | Non-canonical low-`s` signature form rejected (EIP-2). |
| `amount_mismatch` | `X402_PAYMENT_INVALID` | Verified `value` < expected `max_amount_required`. |
| `payto_mismatch` | `X402_PAYMENT_INVALID` | Verified `to` ≠ Splitter contract address from the matching `accepts[]` entry. |
| `network_mismatch` | `X402_PAYMENT_INVALID` | Verified `network` ≠ claimed `network` (e.g., Sepolia signature against mainnet challenge). |
| `asset_mismatch` | `X402_PAYMENT_INVALID` | Verified `asset` ≠ accepted asset (e.g., non-USDC ERC-20). |
| `expired` | `X402_PAYMENT_INVALID` | EIP-3009 `validBefore < now()` or `validAfter > now()`. |
| `nonce_reused` (under invalid) | `X402_PAYMENT_INVALID` | `auth_nonce` already in `x402_settlements` and rejected pre-facilitator. |
| `unsupported_scheme` | `X402_PAYMENT_INVALID` | `payload.scheme` is not `"exact"`. |
| `header_too_large` | `X402_PAYMENT_INVALID` | `X-Payment` header > 8 KB. |
| `duplicate_payment_header` | `X402_PAYMENT_INVALID` | Multiple `X-Payment` headers (any case-folded variant) present. |
| `payload_decode_error` | `X402_PAYMENT_INVALID` | Base64 decode failed, JSON parse failed, or top-level fields missing. |
| `payment_capability_binding_violation` | `X402_PAYMENT_INVALID` | `X-Payment` valid for one capability replayed against a different capability with different price. |
| `capability_wallet_only` | `X402_NOT_ACCEPTED` | Capability declares `payment_methods: ["stripe"]`. |
| `x402_disabled` | `X402_NOT_ACCEPTED` | Hub's kill switch (`feature_flags.x402_enabled = false`) is engaged. |
| `network_unsupported` | `X402_NOT_ACCEPTED` | Capability accepts x402 but not on the network the agent's payload targets. |
| `facilitator_slow` | `X402_SETTLEMENT_TIMEOUT` | Facilitator did not respond within configured timeout. |
| `chain_congested` | `X402_SETTLEMENT_TIMEOUT` | Facilitator confirmed timeout cause was Base chain backlog. |
| `dns_fail` | `X402_FACILITATOR_UNREACHABLE` | DNS resolution of facilitator hostname failed. |
| `connection_refused` | `X402_FACILITATOR_UNREACHABLE` | TCP connect to facilitator failed twice. |
| `cert_pin_mismatch` | `X402_FACILITATOR_UNREACHABLE` | Facilitator TLS certificate SPKI hash does not match the pinned value. |
| `signature_pin_mismatch` | `X402_FACILITATOR_UNREACHABLE` | Facilitator response signature does not verify against the pinned Ed25519 pubkey. |
| `tx_hash_seen` | `X402_SETTLEMENT_REUSED` | Same settlement `tx_hash` already recorded for a different `(agent_id, request_id)`. |
| `nonce_reused` (under reused) | `X402_SETTLEMENT_REUSED` | Same `(payer, eip3009_nonce)` tuple already recorded. |

The `details.documentation_url` field, when present, is a deep-link of the form `https://jecp.dev/errors/<lowercase code>#<subcause>` and points to the same row in the catalog page.

##### Subcause emission policy

A Hub MUST NOT emit `details.subcause` until after it has authenticated the agent (via `X-API-Key` or equivalent). This prevents the subcause registry from acting as an enumeration oracle for unauthenticated callers — same rule as `PROVENANCE_MISMATCH` (§3.1).

### 3.9 Provider Self-Service Endpoints (Stage 3)

These error codes fire only on the Provider-admin endpoints defined in 04-manifest.md §8.6 (`POST /v1/providers/verify-dns`, `POST /v1/providers/me/rotate-key`). They are never emitted on agent-facing wire calls (`POST /v1/invoke`, etc.). Hubs that do not yet implement Stage 3 (third-party Provider acceptance) never emit these codes.

#### `DNS_VERIFICATION_FAILED`

- **HTTP**: 422
- **Cause**: The Provider invoked `POST /v1/providers/verify-dns` (04-manifest.md §8.6.2) but the Hub could not find a matching `_jecp.<domain>` TXT record carrying `jecp-verify=<token>` against the domain extracted from `provider.endpoint_url`. Either the record is absent, the token mismatches, or DNS propagation has not completed.
- **Retry-safe**: Yes (after the Provider publishes / corrects the TXT record and DNS propagates)
- **`details`**: `{ "domain": "<host>", "expected_token_prefix": "<first 8 chars>", "reason": "txt_record_missing" | "txt_record_mismatch" | "nxdomain" }`
- **Recovery**: Publish the TXT record per 04-manifest.md §8.2, wait for propagation (typically < 5 minutes for low-TTL zones), then re-call `POST /v1/providers/verify-dns`.

#### `ROTATION_24H_CAP`

- **HTTP**: 429
- **Cause**: The Provider invoked `POST /v1/providers/me/rotate-key` (04-manifest.md §8.6.3) but has already rotated the maximum number of times allowed in a sliding 24-hour window (default 3). The request has NO effect on the existing key.
- **Retry-safe**: Yes (after the oldest rotation in the window ages out)
- **Headers (SHOULD)**: `Retry-After: <integer-seconds>` indicating when the next rotation slot opens.
- **`details`**: `{ "limit_per_24h": <int>, "rotations_in_last_24h": <int>, "next_slot_at": "<RFC 3339>" }`
- **Recovery**: Wait until `next_slot_at`. Operators MAY adjust the cap via Hub configuration; agents/Providers cannot.

#### `ROTATION_RACE`

- **HTTP**: 409
- **Cause**: The Provider invoked `POST /v1/providers/me/rotate-key` but the Provider record was modified or deleted by a concurrent administrative action mid-transaction (e.g., Provider deleted, or another rotation racing with row-level lock contention). No new key is issued and the existing key is unchanged.
- **Retry-safe**: Yes (re-issue the call once the contending operation completes)
- **`details`**: `{ "reason": "row_locked" | "provider_disappeared" }`
- **Recovery**: Retry the call after a brief backoff (100-500 ms). If `provider_disappeared`, the Provider record has been removed and the Provider must re-register.

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
| `x402_settle`     | `PAYMENT_REQUIRED` (when capability accepts x402), `X402_SETTLEMENT_REUSED` | `hint` (and may co-occur as `payment.next_action` per 06-x402-integration.md §2) |

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
