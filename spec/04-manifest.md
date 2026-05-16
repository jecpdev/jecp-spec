# JECP — Capability Manifest Schema

**Spec Version**: 1.0.0
**Status**: Stable (full enforcement at Stage 3)
**Companion**: 00-overview.md, 01-protocol.md, 05-discovery.md

## 1. Abstract

This document defines the YAML schema (`jecp.yaml`) that Providers use to declare their Capabilities to JECP. It specifies required and optional fields, validation rules, versioning policy, and registration flow.

## 2. Status

The Manifest schema is normative for any Hub implementing Stage 3 (Provider acceptance). v1.0 reference Hub (JobDoneBot) does not yet accept third-party Manifests; first-party Capabilities are configured internally. Stage 3 is targeted for late 2026.

## 3. Purpose of `jecp.yaml`

A Manifest declares:

- Provider identity and contact information
- One or more Capability definitions, each with one or more Actions
- Per-Action pricing, schemas, side effects, and SLA targets
- Versioning information for backward compatibility

The Manifest is the canonical source. Hubs MUST NOT extend Provider Capabilities beyond what the Manifest declares.

## 4. File Location and Format

### 4.1 File Name

The file MUST be named `jecp.yaml` (lowercase, single file).

### 4.2 Format

YAML 1.2.2 syntax. Hubs MUST also accept JSON syntax (a Manifest written in JSON is a valid YAML document).

### 4.3 Encoding

UTF-8 without BOM.

### 4.4 Maximum Size

10 KB serialized. Larger Manifests MUST be rejected with `MANIFEST_TOO_LARGE`.

## 5. Schema

> **Machine-readable schema**: [`schemas/v1/manifest.schema.json`](../schemas/v1/manifest.schema.json) is the canonical JSON Schema 2020-12 file. Validators (CLIs, IDE plugins, CI lint, Hub publish acceptance) MUST load that file; the YAML / JSON snippets below are the human-readable reference and are kept in sync.
>
> **Reference fixture**: [`fixtures/manifest-minimal-valid.json`](../fixtures/manifest-minimal-valid.json) is the smallest manifest that validates. Conformance harnesses MAY use it as a positive baseline.

```yaml
# Manifest schema (YAML representation; canonical JSON Schema at schemas/v1/manifest.schema.json)

# ─── Provider identity ───
namespace: <string>           # MUST. ^[a-z][a-z0-9-]{2,31}$
display_name: <string>        # MUST. Human-readable
website: <url>                # SHOULD
support_email: <email>        # SHOULD
documentation: <url>          # MAY
logo_url: <url>               # MAY

# ─── Capability ───
capability: <string>          # MUST. ^[a-z][a-z0-9-]{2,63}$
version: <semver>             # MUST. e.g., "1.0.0"
description: <string>         # MUST. <= 500 chars
tags: [<string>]              # MAY. <= 8 tags, each <= 32 chars

# ─── Endpoint ───
endpoint: <https url>         # MUST. Hub forwards to this URL
streaming: <bool>             # MAY. Default false
authentication:               # SHOULD
  type: api_key               # v1.0 supports only api_key (HMAC-signed header).
                              # mtls and oauth2 are reserved for v1.1+ with
                              # per-type subschemas.
  header_name: <string>       # for type=api_key

# ─── Actions ───
actions:                      # MUST. Non-empty array
  - id: <string>              # MUST. ^[a-z][a-z0-9-]{2,63}$
    name: <string>            # SHOULD
    description: <string>     # MUST. <= 300 chars
    streaming: <bool>         # MAY. Default false. If true, Hub serves SSE on /v1/invoke (see 01-protocol.md §4.3)
    pricing:                  # MUST
      base: <amount string>   # e.g., "$0.005" — flat/up-front charge used by Hub for budget pre-flight
      currency: <ISO 4217 code> | <crypto code>
                              # MUST be one of:
                              #   - ISO 4217 alpha-3: USD, JPY, EUR, GBP, CAD, AUD, CHF, KRW, SGD, HKD, ...
                              #   - Crypto extension:  USDC, USDT, BTC, ETH, MATIC
                              #   - Multi-currency literal: "both" (legacy USD+USDC, deprecated 2026-11-01)
      model: flat | per_call | per_token | per_chunk | per_second | tiered
      # Optional unit rates for variable models (Phase B variable pricing engine):
      input_per_token_usdc: <number>   # for model=per_token
      output_per_token_usdc: <number>  # for model=per_token
      per_chunk_usdc: <number>         # for model=per_chunk
      audio_per_second_usdc: <number>  # for model=per_second
    trust_tier_required: bronze | silver | gold | platinum  # MAY. Default bronze
    rate_limit_rpm: <int>     # MAY. 0 = use Hub default
    input_schema:             # MUST. JSON Schema 2020-12 subset
      type: object
      required: [...]
      properties: { ... }
    output_schema:            # MUST. JSON Schema 2020-12 subset
      type: object
      required: [...]
      properties: { ... }
    examples:                 # SHOULD. >= 1 example
      - input: { ... }
        output: { ... }
    side_effects:             # SHOULD
      external_api_call: <bool>
      stores_data: <bool>
      modifies_state: <bool>
      sends_email: <bool>
    sla:                      # MAY
      latency_p95_ms: <int>
      timeout_ms: <int>       # Default 30000

# ─── Compliance ───
compliance:                   # SHOULD
  pii_handling: process_only_no_store | store_with_consent
  gdpr_compliant: <bool>
  data_residency: [<region>]  # e.g., ["EU","US","JP"]

# ─── Billing ───
billing:                      # SHOULD
  payout_currency: USD        # Currency for Stripe Connect payout
  stripe_connect_required: <bool>

# ─── Versioning ───
deprecation:                  # MAY
  status: active | deprecated | sunset
  sunset_at: <RFC 3339>       # If status != active
  successor_version: <semver> # If status != active

# ─── Extensions / metadata ───
metadata: { ... }             # Free-form
extensions: { ... }           # Vendor-specific
```

### 5.1 JSON Schema (formal)

The canonical machine-readable schema lives at [`schemas/v1/manifest.schema.json`](../schemas/v1/manifest.schema.json). Implementers MUST validate against that file. The YAML reference at §5 above is the human-readable summary; on any disagreement between prose and schema, the schema is authoritative.

The canonical schema declares `additionalProperties: false` on the root and on every `$def`, narrows several enums beyond the prose summary (e.g. `Authentication.type: ["api_key"]` for v1.0; v1.1+ will add `mtls` and `oauth2`), and adds an `if/then` conditional on `Deprecation` requiring `sunset_at` whenever `status ∈ {deprecated, sunset}`. Refer to the schema file for the authoritative constraints.

## 5.2 Composite Actions (M3 / Workflow)

A composite action is a server-side workflow that calls other capabilities and
returns a single result. The Hub orchestrates the steps, captures the outputs,
substitutes them into later inputs, and bills the agent **once** for the whole
composition (the composite's own `pricing.base`).

```yaml
actions:
  - id: invoice-and-email
    name: Generate invoice and email it to the client
    description: One-shot billing flow — produces the PDF and sends it to the client.
    pricing:
      base: $0.05
      currency: USDC
      model: flat
    trust_tier_required: silver

    # Composition metadata. Presence of `composes` MUST make the action composite.
    composes:
      max_depth: 1                   # MAY (default 1). v1.0 forbids depth > 1.
      on_step_failure: rollback      # rollback | continue (rollback issues automatic refunds)
      timeout_total_ms: 60000        # MAY (default 60000, max 300000)
      steps:
        - id: invoice                # step-local name for output binding
          call: jobdonebot/document-pipeline
          action: generate-invoice
          input:
            client_name:    "${input.client_name}"
            client_address: "${input.client_address}"
            due_date:       "${input.due_date}"
            items:          "${input.items}"

        - id: send
          call: communication/send-email
          action: send
          input:
            to:          "${input.client_email}"
            subject:     "Your invoice"
            body:        "Attached. Total: ${invoice.total_usd} USD."
            attachments: ["${invoice.pdf_url}"]

    output_schema:
      type: object
      required: [invoice, send]
      properties:
        invoice: { type: object }
        send:    { type: object }
```

### 5.2.1 Composition primitives

| Field                 | Required | Description |
|-----------------------|----------|-------------|
| `composes.steps`      | MUST     | Ordered array, 1..8 entries (Hubs MAY reduce). |
| `composes.steps[].id` | MUST     | Step-local name. Output bound as `${id}` for later steps. Pattern `^[a-z][a-z0-9-]{0,30}$`. Unique within the composite. |
| `composes.steps[].call` | MUST   | Target capability `namespace/capability` (NOT cross-Hub in v1.0). |
| `composes.steps[].action` | MUST | Target action id. MUST exist on the resolved capability. |
| `composes.steps[].input` | MUST  | Object literal with template substitutions (see 5.2.2). |
| `composes.max_depth`  | MAY      | Allowed nesting (composites calling composites). Default 1. v1.0 only allows 1. |
| `composes.on_step_failure` | MAY | `rollback` (default) or `continue`. With `rollback`, Hub MUST attempt automatic refunds for any successful prior steps within 5 s of failure. |
| `composes.timeout_total_ms` | MAY | Wall-clock cap for the whole composite. Default 60 000, max 300 000. |

### 5.2.2 Template substitution

References use `${...}` and resolve in this order:

1. `${input.<path>}` — agent's request input (from `POST /v1/invoke` body).
2. `${<step_id>}` — full output object of a prior step.
3. `${<step_id>.<path>}` — JSON-Pointer-style nested access (dotted only; no array indexing in v1.0).

Substitutions happen on the Hub side at step launch, AFTER prior step outputs are available. Templating is purely lexical — no expressions, arithmetic, or function calls. Unresolved references return `COMPOSITE_BIND_ERROR`.

### 5.2.3 Pricing and billing

- The composite's own `pricing.base` is the **only** charge the agent sees.
- Hubs pay each sub-action's Provider out of the gross via standard 85/10/5 split (per sub-call).
- The composite's Provider receives the residual (gross − Σ sub-shares − hub_fee). It is the composite Provider's responsibility to price `base` such that the residual is non-negative; the Hub MUST validate this at publish time and reject manifests where the worst-case sub-cost sum exceeds `base * 0.85`.
- A single `transaction_id` is recorded for the composite. Sub-call `revenue_splits` rows reference the same `transaction_id` with `composite_step_id` populated.

### 5.2.4 Trust tier and Mandate

- The composite's `trust_tier_required` MUST be at least the maximum of any sub-action's required tier (validated at publish time).
- The agent's Mandate is checked once against the composite's `pricing.base`. Sub-call costs are NOT exposed to the agent.

### 5.2.5 Idempotency

- The composite uses the agent's `request_id` for idempotency at the composite level.
- The Hub MUST generate deterministic derived request_ids for sub-calls: `<composite_request_id>:<step_id>`. Sub-providers thus see stable ids and benefit from their own idempotency caches on retries.

### 5.2.6 Streaming

Composites are not streamable in v1.0. The action MUST NOT set both `composes` and `streaming: true`. Streaming-of-composites is reserved for v1.1+.

### 5.2.7 Recursion

`max_depth` defaults to 1. A composite step calling another composite is rejected at publish time when the resolved `max_depth` chain would exceed 1. v1.1+ MAY raise the bound after a Workflow trust tier review.

### 5.2.8 Errors specific to composites

| Code                         | HTTP                           | Cause |
|------------------------------|--------------------------------|-------|
| `COMPOSITE_STEP_FAILED`      | 502                            | A sub-call returned an error. `details.failed_step_id`, `details.upstream_error` populated. With `on_step_failure=rollback`, refunds were attempted (see `details.refunds_issued`). |
| `COMPOSITE_BIND_ERROR`       | 422                            | Template referenced an unknown step or path. Configuration bug. |
| `COMPOSITE_DEPTH_EXCEEDED`   | 422 (publish) / 409 (runtime)  | Depth bound exceeded — likely a sub-call resolved to another composite at runtime. |
| `COMPOSITE_TIMEOUT`          | 504                            | Whole-composite timeout exceeded `timeout_total_ms`. |
| `COMPOSITE_REFUND_FAILED`    | 502                            | Rollback could not refund every prior step. `details.unrefunded_step_ids` populated. Operator alerts ON. |

## 6. Validation Rules

### 6.1 At Submission

The Hub MUST validate:

1. YAML/JSON syntax is valid.
2. Schema conforms to Section 5.1.
3. `namespace` is unique per Provider; the same Provider MAY publish multiple Capabilities under their namespace.
4. `(namespace, capability, version)` tuple is globally unique. A Provider MAY publish multiple versions of the same Capability simultaneously.
5. `endpoint` is reachable: the Hub sends a `POST <endpoint>/health` and expects HTTP 200 within 10s.
6. `endpoint` resolves to a domain the Provider has proven ownership of (DNS TXT verification).
7. Each Action's `input_schema` and `output_schema` are valid JSON Schema 2020-12.
8. Each Action's `pricing.base` parses as a currency amount (e.g., `"$0.005"`) and `pricing.currency` is one of: an ISO 4217 alpha-3 fiat code (`USD`, `JPY`, `EUR`, ...), a crypto extension code (`USDC`, `USDT`, `BTC`, `ETH`, `MATIC`), or the literal `both` (deprecated, accepted through 2026-11-01).
9. Each Action has at least one `examples` entry (RECOMMENDED).

### 6.2 At Runtime

For every routed call, the Hub MUST:

1. Validate `request.input` against `input_schema`. Reject with `VALIDATION_FAILED` on failure.
2. Forward to `endpoint` with a configurable timeout.
3. Validate Provider's response against `output_schema`. If invalid, return `OUTPUT_INVALID` (HTTP 502).
4. Charge the Agent according to `pricing.base`.
5. Distribute revenue per `04-manifest.md` §10 (85% Provider, 10% Hub, 5% payment processor as defaults).

## 7. Versioning

### 7.1 Semantic Versioning

`version` MUST follow semver MAJOR.MINOR.PATCH:

- **MAJOR**: Breaking changes (removed fields, type changes, semantic changes). New deployment required.
- **MINOR**: Backward-compatible additions (new optional fields, new actions).
- **PATCH**: Bug fixes, documentation updates.

### 7.2 Coexistence

Multiple versions MAY coexist. Agents specify a version via:

```
"capability": "deepl/translate"            // latest active version
"capability": "deepl/translate@1.0.0"      // specific version (RECOMMENDED for production)
```

The Hub resolves `latest` as the highest semver version with `deprecation.status == "active"`.

### 7.3 Deprecation

A Provider deprecates a version by setting `deprecation.status: "deprecated"` and supplying `successor_version`. The Hub:

- Continues to route deprecated versions until `sunset_at`.
- Adds a `Deprecation` HTTP header on responses (per RFC 8594).
- Adds a `Sunset` HTTP header with the `sunset_at` date.

After `sunset_at`, the Hub MUST return `CAPABILITY_DEPRECATED` (HTTP 410) with `details.successor` set to the new version identifier.

## 8. Provider Registration Flow

### 8.1 Account Creation

```
POST {hub_origin}/v1/providers/register
Content-Type: application/json

{
  "namespace": "deepl",
  "display_name": "DeepL Translation",
  "owner_email": "engineering@deepl.com",
  "website": "https://deepl.com"
}
```

Hub returns `provider_id` + initial `provider_api_key` + a DNS verification token.

### 8.2 DNS Verification

Provider creates a TXT record:

```
_jecp.deepl.com.   TXT   "jecp-verify=<token>"
```

Hub verifies and updates `providers.dns_verified_at`. Until verification, the Provider cannot publish Manifests.

### 8.3 Stripe Connect Onboarding

Provider connects a Stripe Express account via OAuth. Hub stores `stripe_account_id`. This is REQUIRED for paid Capabilities.

### 8.4 Manifest Submission

```
POST {hub_origin}/v1/manifests
Content-Type: application/x-yaml
Authorization: Bearer <provider_api_key>

# jecp.yaml content
```

Hub responds with:

- `201 Created` with `{ "id": "...", "status": "active" }` on success
- `400 Bad Request` with validation errors on schema failure
- `409 Conflict` if `(namespace, capability, version)` already exists

### 8.5 Lifecycle

```
draft  →  submitted  →  validated  →  active
                                        ├→ deprecated
                                        └→ sunset (read-only, returns 410)
```

A Provider MAY recall a Manifest before activation. After activation, only deprecation/sunset transitions are allowed.

### 8.6 Provider Self-Service Endpoints

Once a Provider has completed `POST /v1/providers/register` (§8.1) and holds a valid `provider_api_key`, three self-service endpoints let the Provider inspect and maintain its own record. All three are authenticated with `Authorization: Bearer <provider_api_key>` and MUST be exposed by Conformant Hubs at Stage 3.

These endpoints are first-party admin surfaces; the Hub MUST reject any request without a valid `provider_api_key` with HTTP 401 carrying a JECP error envelope (see [`spec/03-errors.md`](03-errors.md) and the [`AUTH_REQUIRED`](03-errors.md#auth_required) definition). Conformance: see [`JECP-PROVIDER-MUST-AUTH-REQUIRED`](../conformance/v1.0/JECP-PROVIDER-MUST-AUTH-REQUIRED.yaml).

#### 8.6.1 `GET /v1/providers/me`

Returns the current Provider record.

**Auth**: `Authorization: Bearer <provider_api_key>` (REQUIRED).

**Request**: no body.

**Response 200 (JSON)**:

```json
{
  "provider_id":     "<uuid>",
  "namespace":       "deepl",
  "display_name":    "DeepL Translation",
  "status":          "verified",
  "dns_verified":    true,
  "stripe_verified": true,
  "endpoint_url":    "https://api.deepl.com/jecp/v1",
  "total_calls":     42
}
```

| Field | Type | Description |
|---|---|---|
| `provider_id` | string (UUID) | Stable Provider identifier. |
| `namespace` | string | Provider namespace; immutable post-registration. |
| `display_name` | string | Human-readable name. |
| `status` | string | Lifecycle status — one of `pending`, `dns_pending`, `verified`, `suspended`. |
| `dns_verified` | bool | `true` after a successful DNS TXT check (see §8.2). |
| `stripe_verified` | bool | `true` after Stripe Connect onboarding (see §8.3). |
| `endpoint_url` | string \| null | URL the Hub forwards `/v1/invoke` calls to. |
| `total_calls` | integer | Cumulative successful invocation count. |

**Errors**: [`AUTH_REQUIRED`](03-errors.md#auth_required) (401), [`INVALID_API_KEY`](03-errors.md#invalid_api_key) (401), [`PROVIDER_NOT_FOUND`](03-errors.md#provider_not_found) (404 — Provider deleted).

#### 8.6.2 `POST /v1/providers/verify-dns`

Re-triggers DNS TXT verification against the `endpoint_url`'s domain. Hubs MUST extract the domain server-side from `endpoint_url` rather than trust a client-supplied value; this prevents a Provider api_key holder from forcing DNS verification against a domain they don't control.

**Auth**: `Authorization: Bearer <provider_api_key>` (REQUIRED).

**Request body** (JSON, OPTIONAL):

```json
{ "domain": "deepl.com" }
```

If `domain` is supplied, it MUST equal the host extracted from `provider.endpoint_url`; mismatch is rejected with HTTP 400 / `INVALID_REQUEST`. The field is a client-side sanity check, never authoritative.

**Response 200 (JSON)**:

```json
{
  "verified": true,
  "status":   "verified",
  "message":  "TXT record matched expected token"
}
```

| Field | Type | Description |
|---|---|---|
| `verified` | bool | `true` on a successful TXT match. |
| `status` | string | New `providers.status` after the call. |
| `message` | string | Human-readable summary. On failure, names the missing or mismatched token. |

**Errors**: [`AUTH_REQUIRED`](03-errors.md#auth_required) (401), [`INVALID_API_KEY`](03-errors.md#invalid_api_key) (401), [`INVALID_REQUEST`](03-errors.md#invalid_request) (400 — domain mismatch or malformed body), [`DNS_VERIFICATION_FAILED`](03-errors.md#dns_verification_failed) (422 — TXT record absent or mismatched).

#### 8.6.3 `POST /v1/providers/me/rotate-key`

Atomically invalidates the current `provider_api_key` and issues a new one. Hubs MUST execute the invalidation, the rotation-counter increment, and the new-key write as a single transaction protected by a row-level lock on the Provider record; concurrent callers serialise on that lock so that either all three writes commit together or none do.

**Auth**: `Authorization: Bearer <current_provider_api_key>` (REQUIRED).

**Request body** (JSON, OPTIONAL):

```json
{
  "grace_seconds": 3600,
  "revoke_old":    false
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `grace_seconds` | integer (0 .. 86_400) | 3600 | How long the previous key remains valid alongside the new one. Hub MAY clamp; the effective value is returned in the response. Ignored (forced to 0) when `revoke_old=true`. |
| `revoke_old` | bool | `false` | When `true`, the previous key is rejected immediately (no grace period). Use when key compromise is suspected. |

**Response 200 (JSON)**:

```json
{
  "jecp":                     "1.0",
  "provider_id":              "<uuid>",
  "namespace":                "deepl",
  "api_key":                  "jdb_pk_<48-hex>",
  "api_key_prefix":           "jdb_pk_<8-hex>",
  "previous_key_valid_until": "2026-05-16T13:00:00Z",
  "grace_seconds":            3600,
  "revoke_old":               false,
  "rotations_in_last_24h":    1,
  "warning":                  "This api_key is shown only once. Store it now. ..."
}
```

The Hub MUST enforce a 24-hour rotation cap (default 3 successful rotations per Provider). Exceeding the cap returns HTTP 429 / `ROTATION_24H_CAP` and the request has NO effect on the existing key.

**Errors**: [`AUTH_REQUIRED`](03-errors.md#auth_required) (401), [`INVALID_API_KEY`](03-errors.md#invalid_api_key) (401), [`INVALID_REQUEST`](03-errors.md#invalid_request) (400 — body present but not valid JSON), [`ROTATION_24H_CAP`](03-errors.md#rotation_24h_cap) (429), [`ROTATION_RACE`](03-errors.md#rotation_race) (409 — Provider record disappeared mid-transaction).

## 9. Example Manifest

### 9.1 Minimal

```yaml
namespace: example
display_name: Example Provider
capability: hello
version: 1.0.0
description: Echoes input as a greeting
endpoint: https://api.example.com/jecp/v1

actions:
  - id: greet
    description: Returns a greeting
    pricing:
      base: $0.001
      currency: USD
      model: per_call
    input_schema:
      type: object
      required: [name]
      properties:
        name: { type: string }
    output_schema:
      type: object
      required: [greeting]
      properties:
        greeting: { type: string }
    examples:
      - input: { name: "World" }
        output: { greeting: "Hello, World" }
```

### 9.2 Full (DeepL Translation)

```yaml
namespace: deepl
display_name: DeepL Translation
website: https://deepl.com
support_email: api-support@deepl.com
documentation: https://www.deepl.com/docs-api
logo_url: https://www.deepl.com/img/logo.svg

capability: translate
version: 1.0.0
description: Professional machine translation between 30+ languages.
tags: [translation, language, deepl, ml]

endpoint: https://api.deepl.com/jecp/v1
streaming: false
authentication:
  type: api_key
  header_name: X-DeepL-Auth

actions:
  - id: translate
    name: Translate Text
    description: Translate text from one language to another with formality control.
    pricing:
      base: $0.005
      currency: USD
      model: per_call
    trust_tier_required: bronze
    rate_limit_rpm: 30
    input_schema:
      type: object
      required: [text, target_lang]
      properties:
        text:
          type: string
          maxLength: 10000
        target_lang:
          type: string
          pattern: "^[A-Z]{2}$"
        source_lang:
          type: string
          pattern: "^[A-Z]{2}$"
        formality:
          type: string
          enum: [default, more, less]
    output_schema:
      type: object
      required: [translated]
      properties:
        translated:           { type: string }
        detected_source_lang: { type: string }
    examples:
      - input:
          text: "Hello, world!"
          target_lang: "JA"
        output:
          translated: "こんにちは、世界!"
          detected_source_lang: "EN"
    side_effects:
      external_api_call: true
      stores_data: false
      modifies_state: false
    sla:
      latency_p95_ms: 500
      timeout_ms: 30000

  - id: detect-language
    name: Detect Language
    description: Identify the language of input text.
    pricing:
      base: $0.001
      currency: USD
      model: per_call
    trust_tier_required: bronze
    input_schema:
      type: object
      required: [text]
      properties:
        text: { type: string, maxLength: 5000 }
    output_schema:
      type: object
      required: [language, confidence]
      properties:
        language:   { type: string, pattern: "^[a-z]{2}$" }
        confidence: { type: number, minimum: 0, maximum: 1 }
    examples:
      - input: { text: "Bonjour le monde" }
        output: { language: "fr", confidence: 0.99 }

compliance:
  pii_handling: process_only_no_store
  gdpr_compliant: true
  data_residency: [EU, US]

billing:
  payout_currency: USD
  stripe_connect_required: true

metadata:
  vendor_logo_url: https://www.deepl.com/img/logo.svg
  benchmark_url: https://www.deepl.com/quality
```

## 10. Revenue Distribution

Default split per successful paid call:

- **Provider**: 85% of `pricing.base`
- **Hub fee**: 10%
- **Payment processor**: 5% (Stripe Connect or x402)

Hubs MAY negotiate alternative splits with high-volume Providers. The split MUST be disclosed in the Provider's onboarding agreement.

Payouts:

- Daily, weekly, or monthly per Provider preference
- Via Stripe Connect (for USD) or x402 settlement (for USDC)
- Subject to a minimum threshold ($10 default)

## 11. Authors

JECP Working Group. Contact: hello@jecp.dev.
