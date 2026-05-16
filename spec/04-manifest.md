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
# Manifest schema (YAML representation; JSON Schema below)

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
  type: api_key | mtls | oauth2
  header_name: <string>       # for type=api_key
  # mtls / oauth2 fields per type

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

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://jecp.dev/schemas/v1/manifest.json",
  "type": "object",
  "required": ["namespace", "display_name", "capability", "version", "description", "endpoint", "actions"],
  "properties": {
    "namespace":     { "type": "string", "pattern": "^[a-z][a-z0-9-]{2,31}$" },
    "display_name":  { "type": "string", "minLength": 2, "maxLength": 100 },
    "website":       { "type": "string", "format": "uri" },
    "support_email": { "type": "string", "format": "email" },
    "documentation": { "type": "string", "format": "uri" },
    "logo_url":      { "type": "string", "format": "uri" },
    "capability":    { "type": "string", "pattern": "^[a-z][a-z0-9-]{2,63}$" },
    "version":       { "type": "string", "pattern": "^\\d+\\.\\d+\\.\\d+$" },
    "description":   { "type": "string", "maxLength": 500 },
    "tags":          { "type": "array", "maxItems": 8, "items": { "type": "string", "maxLength": 32 } },
    "endpoint":      { "type": "string", "format": "uri", "pattern": "^https://" },
    "streaming":     { "type": "boolean", "default": false },
    "authentication": { "$ref": "#/$defs/Authentication" },
    "actions":       { "type": "array", "minItems": 1, "items": { "$ref": "#/$defs/Action" } },
    "compliance":    { "$ref": "#/$defs/Compliance" },
    "billing":       { "$ref": "#/$defs/Billing" },
    "deprecation":   { "$ref": "#/$defs/Deprecation" },
    "metadata":      { "type": "object" },
    "extensions":    { "type": "object" }
  },
  "$defs": {
    "Action": {
      "type": "object",
      "required": ["id", "description", "pricing", "input_schema", "output_schema"],
      "properties": {
        "id":          { "type": "string", "pattern": "^[a-z][a-z0-9-]{2,63}$" },
        "name":        { "type": "string", "maxLength": 100 },
        "description": { "type": "string", "maxLength": 300 },
        "streaming":   { "type": "boolean", "default": false },
        "pricing":     { "$ref": "#/$defs/Pricing" },
        "trust_tier_required": { "enum": ["bronze","silver","gold","platinum"] },
        "rate_limit_rpm": { "type": "integer", "minimum": 0 },
        "input_schema":  { "type": "object" },
        "output_schema": { "type": "object" },
        "examples":      { "type": "array", "items": { "type": "object" } },
        "side_effects":  { "$ref": "#/$defs/SideEffects" },
        "sla":           { "$ref": "#/$defs/Sla" },
        "composes":     { "$ref": "#/$defs/Composes" }
      },
      "allOf": [
        { "not": { "required": ["composes", "streaming"] } }
      ]
    },
    "Composes": {
      "type": "object",
      "required": ["steps"],
      "properties": {
        "max_depth":         { "type": "integer", "minimum": 1, "maximum": 1, "default": 1 },
        "on_step_failure":   { "enum": ["rollback", "continue"], "default": "rollback" },
        "timeout_total_ms":  { "type": "integer", "minimum": 1000, "maximum": 300000, "default": 60000 },
        "steps": {
          "type": "array",
          "minItems": 1,
          "maxItems": 8,
          "items":   { "$ref": "#/$defs/CompositeStep" }
        }
      }
    },
    "CompositeStep": {
      "type": "object",
      "required": ["id", "call", "action", "input"],
      "properties": {
        "id":     { "type": "string", "pattern": "^[a-z][a-z0-9-]{0,30}$" },
        "call":   { "type": "string", "pattern": "^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$" },
        "action": { "type": "string", "pattern": "^[a-z][a-z0-9-]*$" },
        "input":  { "type": "object" }
      }
    },
    "Pricing": {
      "type": "object",
      "required": ["base", "currency", "model"],
      "properties": {
        "base":     { "type": "string", "pattern": "^\\$\\d+(\\.\\d+)?$" },
        "currency": {
          "description": "ISO 4217 alpha-3 fiat code (USD, JPY, EUR, GBP, CAD, AUD, CHF, KRW, SGD, HKD, ...) or crypto extension code (USDC, USDT, BTC, ETH, MATIC). The literal 'both' is retained for backward compatibility with v1.0-draft Providers and means USD+USDC; new Providers SHOULD pick a single concrete currency.",
          "type": "string",
          "pattern": "^([A-Z]{3,5}|both)$"
        },
        "model":    { "enum": ["flat", "per_call", "per_token", "per_chunk", "per_second", "tiered"] },
        "input_per_token_usdc":  { "type": "number", "minimum": 0 },
        "output_per_token_usdc": { "type": "number", "minimum": 0 },
        "per_chunk_usdc":        { "type": "number", "minimum": 0 },
        "audio_per_second_usdc": { "type": "number", "minimum": 0 }
      }
    },
    "Authentication": {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type":        { "enum": ["api_key", "mtls", "oauth2"] },
        "header_name": { "type": "string" }
      }
    },
    "SideEffects": {
      "type": "object",
      "properties": {
        "external_api_call": { "type": "boolean" },
        "stores_data":       { "type": "boolean" },
        "modifies_state":    { "type": "boolean" },
        "sends_email":       { "type": "boolean" }
      }
    },
    "Sla": {
      "type": "object",
      "properties": {
        "latency_p95_ms": { "type": "integer", "minimum": 1 },
        "timeout_ms":     { "type": "integer", "minimum": 1000, "maximum": 300000 }
      }
    },
    "Compliance": {
      "type": "object",
      "properties": {
        "pii_handling":   { "enum": ["process_only_no_store", "store_with_consent"] },
        "gdpr_compliant": { "type": "boolean" },
        "data_residency": { "type": "array", "items": { "type": "string" } }
      }
    },
    "Billing": {
      "type": "object",
      "properties": {
        "payout_currency": {
          "description": "ISO 4217 alpha-3 fiat code (USD, JPY, EUR, GBP, ...) or crypto extension code (USDC, USDT, BTC, ETH, MATIC). MUST be a currency that the Hub's underlying payment processor (e.g., Stripe Connect for fiat, on-chain settlement for crypto) supports for the Provider's registered country. Hubs MUST further restrict acceptance to a closed list of supported currencies (the regex is permissive intentionally — closed-list enforcement is Hub-side per §6.1).",
          "type": "string",
          "pattern": "^([A-Z]{3,5}|both)$"
        },
        "stripe_connect_required": { "type": "boolean" }
      }
    },
    "Deprecation": {
      "type": "object",
      "properties": {
        "status":            { "enum": ["active", "deprecated", "sunset"] },
        "sunset_at":         { "type": "string", "format": "date-time" },
        "successor_version": { "type": "string", "pattern": "^\\d+\\.\\d+\\.\\d+$" }
      }
    }
  }
}
```

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
