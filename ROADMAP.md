# JECP Roadmap

> 12-week sprint plan from Sprint 1 (May 2026) to Sprint 12 (Aug 2026).

## Current status

- **Stage**: 0 → 1 (transitioning)
- **Sprint**: 1 (active)
- **Production**: jecp.dev acquired May 7, 2026

## Sprints

| # | Week | Theme | Status |
|---|------|-------|--------|
| 1 | May 7-13 | Namespace & infrastructure | 🟡 In progress |
| 2 | May 14-20 | Billing integration (deduct + Stripe Checkout) | ⬜ Planned |
| 3 | May 21-27 | Stripe Connect topup flow | ⬜ Planned |
| 4 | May 28 - Jun 3 | Spec v0.1 draft (6 documents) | ⬜ Planned |
| 5 | Jun 4-10 | jecp.dev documentation site (Astro) | ⬜ Planned |
| 6 | Jun 11-17 | Provider Console UI (ai.jobdonebot.com/provider) | ⬜ Planned |
| 7 | Jun 18-24 | Capability Manifest spec + @jecp/cli | ⬜ Planned |
| 8 | Jun 25 - Jul 1 | ai.jobdonebot.com → JECP routing | ⬜ Planned |
| 9 | Jul 2-8 | Second provider implementation (DeepL wrapper) | ⬜ Planned |
| 10 | Jul 9-15 | QA audit + load test (k6, 1000 rps) | ⬜ Planned |
| 11 | Jul 16-22 | Legal (ToS / Privacy) + lawyer review | ⬜ Planned |
| 12 | Jul 23-29 | Show HN launch | ⬜ Planned |

## Stage milestones

### Stage 1: Self-billing (target: end of Sprint 3)
- [x] DB schema for wallets / transactions
- [ ] Rust deduct integration
- [ ] Stripe Checkout topup
- [ ] First $1 in revenue

### Stage 2: x402 integration (target: Sprint 4-5)
- [ ] x402 USDC support in JECP server
- [ ] Crypto-native agents can pay without Stripe

### Stage 3: Marketplace (target: end of Sprint 9)
- [ ] Provider registration flow
- [ ] Capability Manifest schema
- [ ] Stripe Connect for revenue split
- [ ] First third-party provider live

### Stage 4: Ecosystem (target: 6-12 months)
- [ ] 100+ active capabilities
- [ ] $5K+ MRR
- [ ] Tier 1 standard recognition

## How to follow

- Watch this repo
- Subscribe to https://jecp.dev/blog (Sprint 5+)
- Follow [@jecpdev](https://x.com/jecpdev)

Last updated: 2026-05-07
