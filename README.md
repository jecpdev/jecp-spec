# JECP Specification

> **Joint Execution & Commerce Protocol** — the open protocol for AI agent commerce.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-draft-orange.svg)](https://jecp.dev/spec)
[![Version](https://img.shields.io/badge/version-1.0.0--draft-blue.svg)](https://jecp.dev/spec)
[![npm](https://img.shields.io/npm/v/@jecpdev/sdk?label=%40jecpdev%2Fsdk)](https://www.npmjs.com/package/@jecpdev/sdk)

---

## What is JECP?

**JECP** lets AI agents discover external services, manage budgets, charge for usage, and receive artifacts — all through one standard protocol.

JECP serves two opposite intents through one protocol:

- **Sell to agents** — turn AI agent traffic into per-call revenue
- **Build with agents** — give your agent its own wallet and budget cap

## Three things JECP gives you

| Feature | What it does |
|---------|-------------|
| **Per-agent wallet** | Each agent has its own USDC balance, separate from any human's card. Top up via Stripe. |
| **Mandate** | Pre-authorize a budget cap. Server enforces it. Autonomous agents can't burn past `budget_usdc`. |
| **Trust Gate** | Tier-based capability access (Bronze → Silver → Gold → Platinum) earned by call history. |
| **`next_action`** | Every error returns a machine-readable recovery hint. Agents recover without human intervention. |
| **Atomic billing** | 85% Provider / 10% Hub / 5% payment, allocated atomically per successful call. Failed calls are not charged. |
| **Multi-vendor** | Capabilities live under namespaces. Switch Provider without changing agent code. |
| **Binary artifacts** | Native PDF / image / audio return inline as base64. |
| **Idempotency** | Safe to retry within 24h on `(agent_id, request_id)`. |

## Quick start

### TypeScript (recommended)

```bash
npm install @jecpdev/sdk
```

```typescript
import { JecpClient } from '@jecpdev/sdk';

const jecp = new JecpClient({ agentId, apiKey });

const { output, billing } = await jecp.invoke(
  'jobdonebot/content-factory', 'translate',
  { text: 'Hello', target_lang: 'JA' },
  { mandate: { budget_usdc: 1.00 } },
);
```

[Full SDK docs](https://github.com/jecpdev/jecp-sdk-typescript)

### Any language (raw HTTP)

```bash
curl -X POST https://jecp.dev/v1/invoke \
  -H "X-Agent-ID: jdb_ag_abc" \
  -H "X-API-Key: jdb_ak_xxx" \
  -d '{
    "jecp": "1.0",
    "id": "req-001",
    "capability": "jobdonebot/content-factory",
    "action": "translate",
    "input": { "text": "Hello", "target_lang": "JA" }
  }'
```

## Documentation

- [Specification (Draft v1.0)](spec/00-overview.md) — full RFC-2119 spec
- [Authentication & Mandate](spec/02-authentication.md) — how wallets and budget caps work
- [Error catalog](spec/03-errors.md) — every error code and its `next_action`
- [Capability manifest schema](spec/04-manifest.md) — how Providers describe their services
- [Roadmap](ROADMAP.md)

## Live infrastructure

- **Hub:** https://jecp.dev (production since April 2026)
- **Reference Hub source:** https://github.com/jecpdev/jecp-server (Rust + Axum, Apache 2.0)
- **TS SDK:** https://github.com/jecpdev/jecp-sdk-typescript ([npm](https://www.npmjs.com/package/@jecpdev/sdk))
- **Live catalog:** https://jecp.dev/v1/capabilities
- **Health:** https://jecp.dev/health

## Status

**Draft v1.0.0-draft** (May 2026). Breaking changes possible until v1.0 final.

## Get involved

- [Discussions](https://github.com/jecpdev/jecp-spec/discussions) — design questions, RFCs
- [Issues](https://github.com/jecpdev/jecp-spec/issues) — bugs, spec ambiguities
- Email: [hello@jecp.dev](mailto:hello@jecp.dev)

## Operator

The canonical Hub at jecp.dev is operated by **Tufe Company Inc.** (Tokyo, Japan).
The protocol is multi-vendor — anyone can run a federated Hub. Reference implementation is Apache 2.0.

## License

[Apache License 2.0](LICENSE)

The specification, reference Hub implementation, and TypeScript SDK are all open source under Apache 2.0.
