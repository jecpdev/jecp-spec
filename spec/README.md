# JECP Specification v1.0-draft

This directory contains the formal specification of the **Joint Execution Capability Protocol** (JECP).

| File                              | Topic                                              |
|-----------------------------------|----------------------------------------------------|
| [00-overview.md](00-overview.md)  | Identity, terminology, comparison to MCP/A2A/Stripe |
| [01-protocol.md](01-protocol.md)  | Wire format (request/response JSON Schema)         |
| [02-authentication.md](02-authentication.md) | API Key, Mandate, Provenance, Trust Gate    |
| [03-errors.md](03-errors.md)      | Error catalog with HTTP mapping + next_action      |
| [04-manifest.md](04-manifest.md)  | Capability Manifest YAML schema (Stage 3 Providers) |
| [05-discovery.md](05-discovery.md)| Well-known URIs, agent-guide.json structure        |

**Status**: Draft (v1.0.0-draft, 2026-05-07)
**License**: Apache 2.0
**Reference implementation**: https://github.com/jecpdev/jecp-server (production: https://setsuna-jobdonebot.fly.dev)
