# JECP Roadmap

> Where the protocol and the reference Hub actually stand, and what gates the next release.
> Dates below are when things happened, not promises. Last updated: 2026-09-19.

## Now

| Track | State |
|---|---|
| **Spec v1.0.2** | Stable. Wire format frozen for v1.x; additions are backwards-compatible. |
| **Reference Hub** (jecp.dev) | In production. Reports `version: 1.1.1` at [`/health`](https://jecp.dev/health). Serves the v1.0.2 wire format. |
| **Payments today** | Per-agent USDC-denominated wallet, topped up via Stripe Checkout. Mandate budget caps enforced server-side. |
| **Spec v1.1.0 (x402)** | Pre-release **rc3**. Implemented in the Hub behind a feature flag, **not enabled in production**. The Splitter contract is not yet deployed to Base mainnet. |
| **TypeScript SDK** | [`@jecpdev/sdk`](https://www.npmjs.com/package/@jecpdev/sdk) 0.9.0 |
| **CLI** | [`@jecpdev/cli`](https://www.npmjs.com/package/@jecpdev/cli) 0.8.2 |

## Shipped

### v1.0 line (April–May 2026)
- [x] Invoke envelope, capability namespaces, discovery (`/v1/capabilities`, `/.well-known/agent-guide.json`)
- [x] Per-agent wallet + Stripe Checkout top-up
- [x] Mandates (`budget_usdc`) enforced by the Hub
- [x] `next_action` recovery hint on every error; public [error catalog](https://jecp.dev/errors)
- [x] Idempotency on `(agent_id, request_id)` including mandate provenance (ADR-0001)
- [x] SSRF defense for Provider endpoints (ADR-0002)
- [x] Provider self-registration, DNS verification, manifest publish/promote
- [x] Refunds, webhook subscriptions
- [x] Per-pool bulkheads observable at `/health`
- [x] Conformance suite (`conformance/v1.0`, `conformance/v1.1`)

### v1.1 design (May 2026)
- [x] x402 integration design — ADR-0003, with amendment Am-7 (Hub keeper as `AUTHORIZED_SETTLER`)
- [x] rc2 retracted and superseded by rc3 — see [RETRACT-v1.1.0-rc2.md](RETRACT-v1.1.0-rc2.md)
- [x] rc3 errata — [`spec/v1.1.0-rc3-errata.md`](spec/v1.1.0-rc3-errata.md)
- [x] Five x402 conformance assertions — [`conformance/x402/`](conformance/x402/)
- [x] `JecpSplitter` contract + Foundry test suite — [jecp-contracts](https://github.com/jecpdev/jecp-contracts) (pre-audit)

## Next: v1.1.0 GA (x402 on Base mainnet)

No date is committed. v1.1.0 goes GA only after every gate below is closed, in order:

1. [ ] Provision the Hub keeper signing key (AWS KMS, least-privilege IAM)
2. [ ] Enable the keeper on staging; run a 7-day soak with ≥1,000 settlements and zero invariant violations
3. [ ] Independent security audit — `JecpSplitter` (Solidity) first, then the Hub keeper (Rust)
4. [ ] Fix or formally accept every audit finding
5. [ ] Deploy `JecpSplitter` to Base mainnet; publish the address and `AUTHORIZED_SETTLER` for public verification
6. [ ] Tag `v1.1.0` and enable x402 in production

Until then, the Stripe wallet path is the only production payment path. When x402 ships it is opt-in and additive: existing integrations keep working unchanged.

## Later

- [ ] First third-party Provider live in the public catalog
- [ ] Spec mirror at `jecp.dev/spec/v1.x/` (today `/spec` redirects to this repository)
- [ ] Additional SDKs (Python first)
- [ ] Federated Hubs — a second, independently operated Hub interoperating with jecp.dev

## How to follow

- Watch this repository
- [Discussions](https://github.com/jecpdev/jecp-spec/discussions) for design questions and RFCs
