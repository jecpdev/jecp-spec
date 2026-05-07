# JECP — Discovery

**Spec Version**: 1.0.0-draft
**Status**: Draft
**Companion**: 00-overview.md, 01-protocol.md, 04-manifest.md

## 1. Abstract

This document defines how Agents and tooling discover JECP Hubs and their Capabilities. It specifies well-known URIs, the structure of `agent-guide.json`, and capability catalog endpoints.

## 2. Well-Known URIs

A JECP Hub MUST publish the following URIs over HTTPS:

| URI                                  | Content-Type        | Cacheable | Purpose |
|--------------------------------------|---------------------|-----------|---------|
| `/.well-known/agent.json`            | `application/json`  | 1 hour    | A2A-compatible agent card |
| `/.well-known/agent-guide.json`      | `application/json`  | 30 min    | Comprehensive AI-readable manual |
| `/llms.txt`                          | `text/plain`        | 1 hour    | LLM-readable summary (community standard) |
| `/v1/capabilities`                   | `application/json`  | 5 min     | Capability + Action catalog (live) |
| `/v1/capabilities/{id}`              | `application/json`  | 5 min     | Single capability metadata |
| `/health`                            | `application/json`  | no-cache  | Hub health check |

CORS MUST allow `Access-Control-Allow-Origin: *` on all discovery endpoints (read-only, no credentials).

## 3. `/.well-known/agent.json`

A2A-compatible Agent Card. Hubs MUST emit at minimum:

```json
{
  "name": "<hub or operator name>",
  "description": "<short, single line>",
  "url": "<hub origin>",
  "version": "1.0.0",
  "provider": {
    "organization": "<org name>",
    "url": "<org url>"
  },
  "jecp": {
    "endpoint": "<hub origin>/v1/jecp",
    "version": "1.0",
    "engine": "jecp",
    "capabilities_url": "<hub origin>/v1/capabilities",
    "streaming": true,
    "mandate_required": false
  },
  "authentication": {
    "schemes": ["api_key", "mandate"],
    "api_key_header": "X-API-Key",
    "agent_id_header": "X-Agent-ID",
    "registration_url": "<hub origin>/api/agent/register"
  }
}
```

Hubs MAY include additional fields under top-level keys. Agents MUST ignore unknown fields.

## 4. `/.well-known/agent-guide.json`

This is the canonical "manual for AI agents". A single GET request returns everything an Agent needs to start using JECP autonomously.

### 4.1 Top-Level Structure

```json
{
  "$schema": "https://jecp.dev/schemas/agent-guide-v1.json",
  "version": "1.0.0",
  "last_updated": "<RFC 3339 date>",
  "audience": "AI agents",

  "identity":           { /* what JECP is, who operates this Hub */ },
  "wow_factors":        { /* metrics that prove the Hub is real and fast */ },
  "quickstart":         { /* 3-step register → execute → topup */ },
  "capabilities":       { /* full catalog with examples */ },
  "decision_tree":      { /* "if user wants X, use capability.action" */ },
  "error_recovery":     { /* per error code, how to recover */ },
  "trust_tiers":        { /* Bronze/Silver/Gold/Platinum rules */ },
  "best_practices":     { /* how to avoid common mistakes */ },
  "integration_examples":{ /* Python, TypeScript, curl */ },
  "referral_program":   { /* viral loop with ethics rules */ },
  "related_resources":  { /* links to other discovery URIs */ },
  "contact":            { /* support, operator, issues */ }
}
```

### 4.2 Required Sections

The following sections MUST be present:

- `identity.protocol` and `identity.operator`
- `quickstart` with at least 1 step (`step_1_register` or equivalent)
- `capabilities` with at least 1 capability
- `error_recovery` covering at minimum: `AUTH_REQUIRED`, `INSUFFICIENT_BALANCE`, `INSUFFICIENT_TRUST`
- `related_resources.capabilities_url`
- `contact.support`

### 4.3 Optional Sections

All other sections are RECOMMENDED for richness but optional. Agents MUST gracefully handle missing sections.

### 4.4 Update Frequency

The Hub MUST refresh content within 30 minutes of capability changes. Cache headers SHOULD be `public, max-age=1800, s-maxage=3600`.

## 5. `/llms.txt`

The `llms.txt` standard is an emerging community convention for LLM-readable site summaries. JECP Hubs SHOULD publish one with at minimum:

```
# <Hub or operator name>

> <one-line elevator description>

<paragraph of context>

## For AI Agents

<API endpoints, auth model, key links>

## Pricing

<concise pricing summary>

## Documentation

<links to spec, examples>
```

The text MUST be ≤ 50 KB. Larger content SHOULD link out to `/llms-full.txt` (custom convention).

## 6. `/v1/capabilities`

### 6.1 GET Response

```json
{
  "jecp": "1.0",
  "capabilities": [
    {
      "id": "content-factory",
      "provider": "jobdonebot",
      "name": "AI Content Factory",
      "description": "Generate structured content using AI",
      "version": "1.0.0",
      "actions": [
        {
          "id": "summarize",
          "description": "Summarize text",
          "price_usdc": 0.003,
          "input_schema":  { /* JSON Schema */ },
          "output_schema": { /* JSON Schema */ }
        }
      ],
      "trust_tier_required": "bronze",
      "rate_limit_rpm": 10
    }
  ],
  "total": <count>,
  "version": "1.0.0",
  "next_cursor": null
}
```

### 6.2 Pagination

For Hubs with many capabilities (Stage 3), pagination uses cursor-based pagination:

```
GET /v1/capabilities?limit=50&cursor=<opaque>
```

Response includes `next_cursor` (string or null when exhausted).

### 6.3 Filtering

Hubs MAY support filters:

- `?provider=<namespace>` — only capabilities from a specific Provider
- `?tier=<bronze|silver|gold|platinum>` — only capabilities accessible at a tier
- `?tag=<tag>` — only capabilities matching a tag

## 7. `/v1/capabilities/{id}`

Returns a single capability with full action schemas:

```json
{
  "id": "content-factory",
  "provider": "jobdonebot",
  "name": "AI Content Factory",
  "description": "...",
  "version": "1.0.0",
  "actions": [ /* full action objects with input_schema, output_schema, examples */ ],
  "trust_tier_required": "bronze",
  "rate_limit_rpm": 10,
  "manifest_url": "<URL to manifest YAML, if Stage 3 Provider>",
  "deprecation": null
}
```

## 8. `/health`

Health-check endpoint. Used by uptime monitors, load balancers, and `agent-guide.json` validators.

```json
{
  "status": "ok" | "degraded" | "down",
  "engine": "jecp-v1",
  "version": "1.0.0",
  "uptime_seconds": <int>,
  "checks": {
    "database": "ok" | "degraded" | "down",
    "stripe":   "ok" | "degraded" | "down",
    "response_ms": <int>
  }
}
```

HTTP 200 for `ok` and `degraded`. HTTP 503 for `down`.

This endpoint MUST NOT require authentication.

## 9. Discovery Sequence

Typical sequence for an Agent encountering JECP for the first time:

```
1. GET /.well-known/agent-guide.json
   → reads quickstart, error_recovery, capabilities

2. POST /api/agent/register
   → obtains agent_id + api_key

3. POST /v1/jecp                    (first execution)
   → if 401 INSUFFICIENT_TRUST, falls back to lower-tier
   → if 402 INSUFFICIENT_BALANCE, calls /api/agent/topup

4. GET /v1/capabilities             (when more detail needed)
   → enumerates available actions
```

## 10. Discovery from Other Hubs (Stage 4)

A future feature: Hub-to-Hub federation, where one Hub redirects an Agent to another Hub's Capability that the first Hub does not host. This requires:

- A standard cross-Hub identity (similar to OpenID Connect or IndieAuth)
- A trust framework
- Negotiated revenue sharing

This is out of scope for v1.0.

## 11. Caching Recommendations

| Endpoint                   | Recommended `Cache-Control`             |
|----------------------------|------------------------------------------|
| `/.well-known/agent.json`  | `public, max-age=3600, s-maxage=86400`  |
| `/.well-known/agent-guide.json` | `public, max-age=1800, s-maxage=3600` |
| `/llms.txt`                | `public, max-age=3600`                  |
| `/v1/capabilities`         | `public, max-age=300, s-maxage=600`     |
| `/v1/capabilities/{id}`    | `public, max-age=300, s-maxage=600`     |
| `/health`                  | `no-cache`                               |

Conditional GET (`If-None-Match`, `ETag`) is RECOMMENDED for catalog endpoints.

## 12. Schema Hosting

Hubs SHOULD host JSON Schema files for agent-guide.json, capabilities, and the request/response wire format at predictable URLs:

```
https://jecp.dev/schemas/v1/request.json
https://jecp.dev/schemas/v1/response.json
https://jecp.dev/schemas/v1/manifest.json
https://jecp.dev/schemas/v1/agent-guide.json
```

Schema files use JSON Schema 2020-12.

## 13. Authors

JECP Working Group. Contact: hello@jecp.dev.
