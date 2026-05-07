# JECP Specification

> **Joint Execution Capability Protocol** — the open protocol for AI agent commerce.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-draft-orange.svg)](https://jecp.dev/spec)
[![Version](https://img.shields.io/badge/version-1.0.0--draft-blue.svg)](https://jecp.dev/spec)

---

## What is JECP?

**JECP** lets AI agents discover external services, manage budgets, charge for usage, and receive artifacts — all through one standard protocol.

JECP is the leading implementation of the **Agent Commerce Protocol** category.

```
MCP solved "talking to tools."
Stripe solved "accepting money."
JECP solves "agents transacting."
```

## Why JECP?

AI agents in 2026 can think, write, and call tools — but they cannot:

- ✗ Generate and deliver invoices
- ✗ Process images with multi-step pipelines
- ✗ Coordinate multiple third-party APIs
- ✗ Manage budgets across calls
- ✗ Pay for what they use, get paid for what they provide

JECP fills the gap.

## Core innovations (industry first)

| Feature | What it does |
|---------|-------------|
| **Mandate** | Agent budget pre-authorization with auto-stop on overrun |
| **Trust Gate** | Tier-based capability access (Bronze → Platinum) |
| **Workflow Capability** | Multi-step orchestration in one request |
| **Artifact Delivery** | Native binary output (PDF, images, audio) |

## Quick example

```bash
curl -X POST https://jecp.dev/v1/jecp \
  -H "X-Agent-ID: jdb_ag_abc" \
  -H "X-API-Key: jdb_ak_xxx" \
  -d '{
    "jecp": "1.0",
    "id": "req_a3f2",
    "capability": "document-pipeline",
    "action": "generate-invoice",
    "input": {
      "client_name": "ABC Corp",
      "items": [{"name": "Web Design", "quantity": 1, "unit_price": 500000}]
    }
  }'
```

Returns a complete PDF invoice in 127ms.

## Documentation

- [Specification (Draft)](spec/00-overview.md)
- [Quickstart](docs/quickstart.md)
- [Capability Manifest Schema](spec/04-manifest.md)
- [Authentication & Mandate](spec/02-authentication.md)
- [Error Catalog](spec/03-errors.md)

## Reference implementation

The reference server runs at https://jecp.dev (production).

Source: https://github.com/jecpdev/jecp-server (Apache 2.0)

## Status

**Draft** (v1.0.0-draft, May 2026)

The specification is in active development. Breaking changes possible until v1.0.0 final.

## Get involved

- [GitHub Discussions](https://github.com/jecpdev/jecp-spec/discussions) — design discussions
- [Issues](https://github.com/jecpdev/jecp-spec/issues) — bugs and proposals
- [Discord](https://discord.gg/jecp) — chat with maintainers

## Working group

JECP is developed by the **JECP Working Group**, with reference implementation maintained by JobDoneBot Inc.

Lead author: [@acromoney](https://github.com/acromoney)

## License

[Apache License 2.0](LICENSE)

The specification text and reference implementation are open source under Apache 2.0. Trademark "JECP" is reserved by JobDoneBot Inc. for the canonical specification.
