# JECP Specification

> **Joint Execution & Commerce Protocol** — the open protocol for AI agent commerce.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-stable-brightgreen.svg)](https://jecp.dev/spec)
[![Version](https://img.shields.io/badge/version-1.0.2-blue.svg)](https://jecp.dev/spec)
[![Pre-release](https://img.shields.io/badge/pre--release-1.1.0--rc3-orange.svg)](spec/v1.1.0-rc3-errata.md)
[![npm](https://img.shields.io/npm/v/@jecpdev/sdk?label=%40jecpdev%2Fsdk)](https://www.npmjs.com/package/@jecpdev/sdk)

> **rc3 status banner** — v1.1.0-rc3 is the current pre-release for the x402 (USDC on Base) integration. **v1.1.0-rc2 is SUPERSEDED** — its facilitator-trust settlement model was incorrect. New integrations MUST target rc3 (Hub keeper EOA as `AUTHORIZED_SETTLER`). See [`spec/v1.1.0-rc3-errata.md`](spec/v1.1.0-rc3-errata.md) and ADR-0003 Am-7 ([`adr/0003-x402-integration.md`](adr/0003-x402-integration.md)).

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

- [Specification v1.0](spec/00-overview.md) — full RFC-2119 spec
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

**v1.0.2 — Stable** (May 2026). Backwards-compatible additions ship as v1.x; breaking changes will require v2.0.
**v1.1.0-rc3 — Pre-release** (May 2026). x402 integration + Hub keeper trust model. Not yet GA — see [RC3-GA-GATE-CHECKLIST](https://github.com/jecpdev/JobDoneBot/tree/main/docs/jecp/release-prep/RC3-GA-GATE-CHECKLIST.md) (private).

### Version table

| Version | Status | Tag | Notes |
|---|---|---|---|
| 1.1.0-rc3 | locked design, in implementation | `v1.1.0-rc3` (pending) | current — Hub keeper integration (AUTHORIZED_SETTLER = Hub keeper EOA) |
| 1.1.0-rc2 | **SUPERSEDED** | `v1.1.0-rc2` (annotated) | facilitator-trust settlement model retracted; do NOT use for new integrations |
| 1.0.2     | GA | `v1.0.2` | current stable wire-format release |
| 1.0.0     | GA | `v1.0.0` | initial wire-stable release |

### rc2 → rc3 in one paragraph

An external review (2026-05-16) surfaced three design flaws in the rc2 facilitator trust model: (a) x402.org runs a **multi-operator facilitator fleet** (not a single EOA), so wiring `AUTHORIZED_SETTLER` to a fixed facilitator address is non-implementable; (b) treating the facilitator as a trust root contradicts the [x402 design principles](https://github.com/x402-foundation/x402/blob/main/README.md); (c) rc2 assumed a facilitator-initiated post-pull contract call that does not exist in x402's wire protocol. rc3 fixes all three by moving settlement recording into a **Hub-operated keeper service** (AWS KMS-backed). The Splitter contract is unchanged, the wire format is unchanged, and SDK / CLI need no changes. ADR-0003 Am-7 documents the redesign; [`spec/v1.1.0-rc3-errata.md`](spec/v1.1.0-rc3-errata.md) contains the normative deltas.

### rc2 retraction notice

The git tag `v1.1.0-rc2` (commit `19e687b`) has been **annotated SUPERSEDED** with a rationale pointing at rc3 — run `git show v1.1.0-rc2` to see the full retraction notice. The GitHub Releases page for v1.1.0-rc2 will be updated to prepend `(SUPERSEDED by v1.1.0-rc3)` to its title and a SUPERSEDED warning to its body once rc3 is tagged and released. Implementations that integrated against rc2's facilitator-trust model MUST upgrade to rc3 before mainnet deploy (wire format unchanged; the change is on-chain trust root + Hub keeper service).

### v1.0.2 Phase 0 errata (2026-05-10)

- **K1** endpoint reconciliation — `/v1/invoke` canonical, `/v1/jecp` retained legacy alias with RFC 8594 `Deprecation` / `Sunset` headers (sunset 2026-11-01).
- **K2** wire-format MUSTs — HTTP 415 `UNSUPPORTED_MEDIA_TYPE`, HTTP 409 `DUPLICATE_REQUEST`, HTTP 410 `CAPABILITY_DEPRECATED` + Sunset/Deprecation/Link, HTTP 429 `RATE_LIMITED` + `Retry-After`, HTTP 400 `INPUT_SCHEMA_VIOLATION`.
- **K3** in-process bulkhead — invoke / read / provider / background pools observable at `/health.pool_assignments`; saturation on one pool MUST NOT starve another.
- **K4.1** discovery — `/.well-known/agent-guide.json` MUST per `schemas/v1/agent-guide.json` (K4.2 spec mirror to jecpdev/website deferred to v1.1).
- **K5 / ADR-0001** — idempotency cache key MUST include `mandate.provenance_hash`; same `(agent_id, request_id)` with different provenance ⇒ HTTP 409 (not silent overwrite).

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
