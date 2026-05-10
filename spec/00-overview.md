# JECP — Joint Execution & Commerce Protocol

**Spec Version**: 1.0.0
**Status**: Stable
**Date**: 2026-05-07
**License**: Apache 2.0

## 1. Abstract

JECP is an open protocol for AI agents to discover, execute, and pay for external service capabilities. It provides budget pre-authorization (Mandate), tier-based trust gates, machine-readable error recovery, and binary artifact delivery as a single standard.

## 2. Status of This Memo

This document is a Draft v1.0 of the Joint Execution & Commerce Protocol. It is published for review and comment by the JECP Working Group. The protocol category is "Agent Commerce Protocol".

A reference implementation runs in production at `https://setsuna-jobdonebot.fly.dev` since April 2026.

This document is governed by Apache License 2.0. Distribution is unlimited.

### 2.1 Naming history

The acronym **JECP** was originally coined as "JobDoneBot Execution Capability Protocol" (May 2026, when the first reference implementation went live). It was subsequently renamed to "Joint Execution Capability Protocol" upon initial public spec release (Sprint 4, May 2026), and to "Joint Execution & Commerce Protocol" upon transition to a multi-vendor standard track. The acronym `JECP` and all URLs (`jecp.dev`, `github.com/jecpdev`) are preserved across renames.

## 3. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

### 3.1 Defined Terms

- **Agent**: An AI system (LLM-based bot, autonomous agent, custom integration) that calls JECP endpoints to execute capabilities. One Agent represents one logical service (NOT one user session).

- **Provider**: An entity that publishes a Capability and its Actions on JECP, receiving payment for each invocation. (Stage 3 feature)

- **Hub**: The central JECP server. Authenticates agents, validates Mandates, routes to Providers, and handles billing.

- **Capability**: A namespaced functional area (e.g., `document-pipeline`, `content-factory`).

- **Action**: A specific operation within a Capability (e.g., `generate-invoice`, `summarize`).

- **Mandate**: A signed authorization that limits per-call cost and expires at a specified time.

- **Trust Tier**: A quality-of-service tier (Bronze, Silver, Gold, Platinum) automatically promoted by lifetime call count.

- **Wallet**: An Agent's prepaid balance in USDC. Charged via Stripe Checkout, consumed per capability call.

## 4. Overview

### 4.1 Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Agent (consumer)                                         │
│   - Holds API key                                       │
│   - Issues Mandate (optional)                           │
│   - Calls POST /v1/invoke                               │
└──────────────────────────┬──────────────────────────────┘
                           │ HTTPS
                           ▼
┌─────────────────────────────────────────────────────────┐
│ JECP Hub                                                 │
│   1. Authenticate (X-Agent-ID, X-API-Key)              │
│   2. Validate Mandate (budget, expiry, provenance)     │
│   3. Check Trust Gate (tier vs capability)             │
│   4. Apply rate limit                                  │
│   5. Deduct cost (free tier OR wallet OR mandate)      │
│   6. Route to capability handler                        │
│   7. Return artifact + billing metadata                 │
└──────────────────────────┬──────────────────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        ▼                                      ▼
   Built-in handler                      Provider (Stage 3)
   (operator's own code)                 (third-party server)
```

### 4.2 Comparison to Adjacent Protocols

| Aspect              | MCP   | A2A   | Stripe | LangChain | **JECP**  |
|---------------------|-------|-------|--------|-----------|-----------|
| Tool discovery      | Yes   | Yes   | No     | Yes       | Yes       |
| Binary artifacts    | Limit | Limit | No     | Limit     | Yes       |
| Multi-step workflow | No    | No    | No     | Yes       | Yes       |
| Budget pre-auth     | No    | No    | Limit  | No        | **Yes**   |
| Tiered trust        | No    | No    | Yes    | No        | **Yes**   |
| AI-specific design  | Yes   | Yes   | No     | Yes       | Yes       |
| Open spec           | Yes   | Yes   | No     | No        | Yes       |
| Billing integration | No    | No    | Yes    | No        | **Yes**   |

JECP is the only protocol that combines all rows.

### 4.3 Use Cases

- Generate a PDF invoice for a client (`document-pipeline.generate-invoice`)
- Summarize a long article (`content-factory.summarize`)
- Translate text between languages (`content-factory.translate`)
- Process an image batch with multiple ops (`file-chain.image-pipeline`)
- Forecast time-series with confidence intervals (`data-insight.forecast`)
- Run multi-step workflow `invoice→email→DB` (`workflow.invoice-and-notify`)
- Automate SNS posts across X / TikTok / Instagram (`sns-engine.*`)

### 4.4 Protocol Layers

JECP defines four complementary specifications:

1. **Wire Format** (Section 01-protocol.md): Request / response JSON schemas
2. **Authentication** (Section 02-authentication.md): API Key, Mandate, Provenance, Trust Gate
3. **Errors** (Section 03-errors.md): Error code catalog with machine-readable next_action
4. **Manifest** (Section 04-manifest.md): Capability declaration schema (YAML) for Providers

A fifth document covers **Discovery** (Section 05-discovery.md): well-known URIs and agent-readable indices.

## 5. Goals and Non-Goals

### 5.1 Goals

JECP aims to:

- Provide a single entry point for AI agents to access many services
- Enable per-call budget pre-authorization (`Mandate`) to prevent runaway costs
- Standardize machine-readable error recovery (`next_action`)
- Support binary artifact delivery (PDF, images, audio) at the protocol level
- Allow third-party Providers to publish Capabilities with revenue share
- Maintain backwards compatibility within MAJOR version

### 5.2 Non-Goals

JECP explicitly does NOT aim to:

- Replace MCP for tool discovery (JECP complements MCP for paid execution)
- Replace LLM provider APIs (Anthropic, OpenAI) — JECP orchestrates these
- Provide its own authentication layer for end-users (Agents are server-side; end-user auth is Provider's responsibility)
- Provide hosting for Providers (Providers run their own servers; JECP routes)
- Define a query language or planner (JECP is the execution layer)

## 6. Versioning

JECP follows Semantic Versioning. The major version is reflected in the URL path:

```
POST https://jecp.dev/v1/invoke   (this spec)
POST https://jecp.dev/v2/jecp     (future, when breaking changes ship)
```

All Request and Response objects MUST include a `jecp` version field set to `"1.0"` for this spec.

A Hub MUST support v1 for at least 12 months after v2 launches. v1 MUST emit a `Deprecation` HTTP header for at least 6 months before sunset.

## 7. Reference Implementation

A canonical implementation in Rust (Apache 2.0):

- Source: https://github.com/jecpdev/jecp-server
- Production: https://setsuna-jobdonebot.fly.dev
- Operator: JobDoneBot Inc.

Independent implementations are encouraged. Test fixtures and conformance suites will be published in a future revision.

## 8. Document Conventions

- HTTP requests are shown with method + path + headers + body, prefixed by `→`.
- HTTP responses are shown with status + headers + body, prefixed by `←`.
- JSON examples are formatted for readability; whitespace is non-significant per RFC 8259.
- All examples are valid unless explicitly marked `(invalid)`.

## 9. References

### 9.1 Normative

- [RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119) — Key words for use in RFCs to indicate Requirement Levels
- [RFC 7231](https://datatracker.ietf.org/doc/html/rfc7231) — HTTP/1.1 Semantics and Content
- [RFC 7807](https://datatracker.ietf.org/doc/html/rfc7807) — Problem Details for HTTP APIs
- [RFC 8259](https://datatracker.ietf.org/doc/html/rfc8259) — JSON
- [RFC 4122](https://datatracker.ietf.org/doc/html/rfc4122) — UUID
- [RFC 3339](https://datatracker.ietf.org/doc/html/rfc3339) — Date-Time on the Internet
- [JSON Schema 2020-12](https://json-schema.org/draft/2020-12/release-notes.html)

### 9.2 Informative

- [Anthropic MCP Specification](https://modelcontextprotocol.io)
- [Google A2A Specification](https://github.com/google/a2a)
- [Stripe API Reference](https://stripe.com/docs/api)
- [OpenAPI 3.1](https://spec.openapis.org/oas/v3.1.0)

## 10. Authors

- JECP Working Group
- Reference implementation maintained by JobDoneBot Inc.
- Contact: hello@jecp.dev
