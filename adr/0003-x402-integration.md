# ADR-0003: x402 Integration

> **TL;DR for VPs of Eng**: JECP integrates x402 (Coinbase HTTP 402 + USDC-on-Base micropayment) as a parallel-mode payment path on `/v1/invoke`, with the existing Stripe wallet path unchanged. To distribute revenue 85/10/5 (Provider / Hub / Network reserve) within a single block without the Hub holding any authorization keys on the request hot path, JECP deploys an immutable on-chain `JecpSplitter` contract on Base mainnet; the 402 challenge's `pay_to` field points at the Splitter. Capability registration on the Splitter is authorized by an **EIP-712 signature from the Provider's own wallet**; the Hub holds only a **`RELAYER` key in AWS KMS** that pays gas and orders nonces — if compromised, the attacker can DoS new registrations but cannot reassign capabilities. Trust in the x402.org facilitator is grounded by TLS cert pinning + Ed25519 response-signature pinning + a 60-second on-chain reconciler — multi-facilitator quorum is deferred to v1.2. This ADR records the five admiral-locked decisions that bound the v1.1.0 scope, the six post-approval amendments (v1.1.1) that hardened the Splitter design after two mini-panels surfaced 3 Critical defects, and the alternatives we explicitly rejected (Hub-side KMS+multisig payouts, Stripe co-charge bridging, Provider monthly settlement, Hub-server-key REGISTRAR, post-pull facilitator helper).

## Status

Accepted (2026-05-11) — amended 2026-05-11 to v1.1.1 (six Splitter amendments, Am-1 through Am-6; see Consequences §"Post-approval amendments"). Companion to ADR-0004 (idempotency × x402).

## Context

Through v1.0, JECP's only payment path was the pre-funded Stripe wallet: agents top up via Stripe Checkout in USD; the Hub deducts at invoke time; the Hub settles to Providers off-chain via Stripe Connect. This works at sub-dollar prices but suffers three structural problems that the agent-commerce thesis has to solve before it scales beyond the few hundred dogfooding deployments:

1. **Unit economics**. Stripe's $0.50 + 3.7% fixed + variable on a $5 top-up is ~5.9% effective. On a $0.20 invoke, a true sub-dollar price floor cannot exist — the rake on the funding hop dominates.
2. **Agent-native UX**. The wallet model assumes a human-in-the-loop top-up. An autonomous agent that runs out of balance mid-task either pauses for human intervention or fails — neither is the experience the protocol promises.
3. **Marketing positioning**. JECP's category-defining claim is "the first agent-commerce protocol with on-chain atomic 85/10/5 revenue split." Without a crypto path, that claim is aspirational.

x402 (Coinbase, 2026-04) is the first credible HTTP-native micropayment standard with a working facilitator at `x402.org`, a real on-chain leg (USDC on Base), and a serializable wire envelope. Integrating it solves all three problems. But it adds three trust boundaries the wallet path does not have: (a) a public on-chain ledger, (b) an out-of-process facilitator the Hub blindly trusts to attest settlement, and (c) operator-controlled hot wallets holding revenue in a bearer asset. Done naively, the integration introduces a critical custody risk (Hot wallet key compromise drains the Hub's transit balance plus pending Provider payouts) and a critical oracle risk (Spoofed/MITM facilitator forges settlement attestations).

The cross-panel design sprint (Panel 1 protocol-designer, Panel 2 threat-modeler, Panel 3 factory-architect, Panel 4 product-manager) generated four parallel proposals across five tensions. The admiral closed the sprint with five locked decisions; this ADR records them as the contract for STEP 3 implementation.

## Decision

JECP v1.1.0 ships x402 as an **additive, parallel** payment path on `/v1/invoke`. The five admiral-locked decisions are:

### A. Trust model — single facilitator + cert pin + Ed25519

The Hub trusts `x402.org`'s `/verify` and `/settle` endpoints for the request-path fast path. To detect facilitator compromise:

- TLS cert pinning (SPKI SHA-256 hash) on the facilitator hostname.
- Facilitator response signature verified against a pinned Ed25519 public key (rotated quarterly via operator-controlled `feature_flags`).
- A 60-second background reconciler cross-checks every settlement on Base via `eth_getTransactionReceipt`; on mismatch the settlement is `flagged` and any pending Provider payout is frozen.
- A runtime kill switch (`feature_flags.x402_enabled = false`) halts all x402 invokes within 60 seconds without redeploy; the existing wallet path is unaffected.

Multi-facilitator quorum (Panel 2's preferred model) is **deferred to v1.2**. The three independent defenses (cert pin + signature verify + reconciler) form an acceptable residual for v1.1 with the kill switch as the operator's escape hatch.

### B. Custody model — Splitter Contract on Base (Hub holds no authorization key on hot path)

x402 v1/v2 specifies a single `payTo` per challenge. To achieve single-block-atomic 85/10/5 revenue distribution without Hub authorization-key custody:

- JECP deploys a `JecpSplitter` smart contract on Base mainnet. The contract is immutable except for a single `relayer` address (rotatable via `setRelayer()` under multisig admin); all other state and authorization roles are immutable. One Splitter address, all settlements route here.
- The 402 challenge's `pay_to` field MUST be the Splitter address. Per-capability split parameters are registered on-chain at capability publish time.
- **Capability registration is authorized by a Provider EIP-712 signature** (Am-1). The Provider signs the `(capabilityId, provider, providerBps, hubBps, reserveBps, nonce, deadline)` tuple with its own wallet key; the Hub-controlled `RELAYER` merely submits the transaction and pays gas. The Hub holds **no key with authority to register, reassign, or split** — only a gas-payer key.
- **The `RELAYER` key lives in AWS KMS** via `alloy-signer-aws` (Am-5). The plaintext key never appears in the Hub binary, environment variables, or process memory; signing requests round-trip to KMS (+80-120 ms; ~3 MB binary delta). KMS API enforces per-call rate limits and CloudTrail-logs every invocation.
- **Settlement uses a two-call ledger pattern** (Am-2, updated by Am-7). The x402 facilitator pulls USDC into the Splitter via EIP-3009 `transferWithAuthorization`; the **Hub-operated keeper EOA** (the `AUTHORIZED_SETTLER`, AWS KMS-backed per Am-7) then calls `recordSettlement(capabilityId, amount)` from a bounded background loop, updating an `accountedBalance[capabilityId]` ledger. Anyone may then call `splitFor(capabilityId, payer)` which reads the ledger, zeroes it (CEI), and distributes shares. `splitFor()` accepts no caller-supplied amount and cannot be tricked into draining opportunistic balance. The facilitator never calls `recordSettlement()` directly — the rc2 facilitator-as-settler model is retracted (see Am-7).
- **Provider payout uses a pull-pattern escrow with try/catch** (Am-3). If a direct USDC transfer to the Provider reverts (USDC blacklist, contract that reverts on receive, gas griefing), the share routes to `providerEscrow[provider]` and the Provider recovers it later via `withdraw()` from any address it controls. Treasury and Reserve are always paid; one griefing Provider cannot block the rest of the split.
- **Capability registration is lazy-on-promote** (Am-6). The on-chain `register()` transaction fires when a Provider publishes via `POST /v1/manifests/{id}/promote` — not at every `publish` call. Gas cost is $0.03–0.06 per call, recovered after ~25 paid invokes.
- Hub treasury and Network reserve are Gnosis Safe 2-of-3 multisigs (`HUB_TREASURY`, `NETWORK_RESERVE`); the `RELAYER_ADMIN` (which can rotate the `RELAYER` via `setRelayer()`) is a separate Gnosis Safe 2-of-3 with separation-of-duties from treasury signers. **The Hub-server process holds no signing key for any of the multisigs.**
- "Single-block atomic" = the `recordSettlement` transaction and the `splitFor` transaction are submitted in the same Base block (~2 s apart). The x402.org facilitator does not currently support post-pull contract calls within the same transaction, so the canonical implementation is two transactions in one block, not one transaction. Marketing copy MUST use "single-block atomic", not "same-tx atomic" (Am-4).

This eliminates Panel 2's `TM-E1` Critical (hot-wallet authorization-key compromise on Hub) and the Splitter mini-panel's `SC-C1` Critical (REGISTRAR-key compromise) — the original draft's `REGISTRAR` role gave a Hub-controlled EOA full authority to register and reassign capabilities, which contradicted the "Hub holds no key" thesis. The amended design moves authorization to the Provider's own wallet via EIP-712.

New work added: Solidity contract (~400-500 LOC after amendments), Foundry tests (~600 LOC), audit ($15-30k from Spearbit / Cure53 / Trail of Bits), Base mainnet deploy, contract verification on Basescan, multisig setup (3 Safes: Treasury, Reserve, Relayer-Admin), and `alloy-signer-aws` integration in the Hub Rust crate for KMS signing. Splitter v1 state is immutable except for `relayer`: if a bug is found, deploy v2 + Provider re-registration migration.

### C. Refund model — 24h manual + Hub temporary loss absorption

If `/v1/invoke` proceeds past settlement and the Provider's capability execution fails (5xx, timeout, business-logic error), the Hub returns the original failure to the agent and absorbs the 85% Provider share as opex. Manual refund flow within 24h via support ticket. Defenses against DoS:

- Per-agent rate limit on refunds: max 10 refunds / 24h / agent; 11th opens an investigation hold.
- Capability-level auto-disable if failure rate > 5% over 1h.
- Manual review for amounts > $10.
- Hub absorption capped at $500/week; beyond that, refunds queue for human approval.

Trigger to escalate to a v1.2 automated refund pool: ≥3 incidents/month of >10 refund requests, OR ≥1 incident of >$100 Hub absorption.

### D. `accepts[]` order — Stripe first, x402 second

Within the 402 response's `accepts[]` array, the Hub MUST list `stripe-wallet` first and `exact` (x402) second on capabilities that accept both. Rationale: Stripe is more recoverable (chargeback / dispute paths exist), and Panel 2 `TM-MC` flagged mode-confusion attacks where agents misinterpret order and consume the wrong signed authorization. x402-native marketing positioning lives in LP / agent-guide / share-kit copy, NOT in protocol field order.

### E. SDK auto-mode — try x402 on first 402 (aggressive)

When the SDK is constructed with `payment: { mode: 'auto', signer }`:

- First invoke arrives, Hub returns 402 with both methods.
- SDK checks: signer present? facilitator reachable (cached health)? capability accepts x402? → if all yes, attempt x402 first.
- If x402 attempt fails (settlement timeout, insufficient balance, etc.) → fallback to wallet path automatically (if wallet has balance).
- If neither path works → return `INSUFFICIENT_PAYMENT_OPTIONS` to caller.

Cold-start latency: +200-300ms on first invoke (facilitator round-trip). Acceptable trade-off for zero-config UX. Subsequent invokes amortize via the facilitator client connection pool. Opt-out: `mode: 'wallet'` forces Stripe always; `mode: 'x402'` forces x402 always.

## Consequences

**Positive**

- True sub-dollar pricing becomes possible (≤1% on-chain gas vs. 5.9% Stripe top-up rake).
- Agents that pre-fund USDC on Base can run autonomously with zero human-in-the-loop top-ups.
- The "first agent-commerce protocol with on-chain single-block-atomic 85/10/5 revenue split" claim becomes load-bearing — the Splitter contract is observable and auditable on Basescan.
- The wallet path remains untouched; existing agents experience zero behavioral change. v1.1.0 conformance does NOT require x402 support.
- Old SDKs degrade gracefully on x402-enabled capabilities — they ignore the new `payment` sibling field, see the existing `next_action.type = "topup"`, and continue using the wallet.
- Hub authorization-key custody risk on the hot path is eliminated by B-1 (Splitter contract) plus Am-1 (Provider EIP-712 signs registration) plus Am-5 (KMS-only RELAYER for gas). The remaining custody surface (Hub treasury, Network reserve, Relayer-Admin multisigs) is operationally segmented across three Gnosis Safes with separation-of-duties.

**Negative**

- Solidity contract scope adds 2-3 weeks (audit is the long pole; total elapsed 4-6 weeks vs. original 2-3 week wallet-only estimate).
- Audit cost ($15-30k) is the largest single line item; v1.1.1 amendments expanded the audit surface to also cover EIP-712 sig recovery, the `AUTHORIZED_SETTLER` trust model, `accountedBalance` invariants, and pull-pattern `withdraw()` correctness.
- Single facilitator (`x402.org`) is a real concentration risk. Mitigations (cert pin + Ed25519 + reconciler + kill switch) form acceptable residuals but do not match a multi-facilitator quorum's robustness; quorum is the v1.2 upgrade.
- Hub absorbs Provider share on capability-execution failures during the 24h manual refund window. Per-agent rate limit + per-week absorption cap bound the loss; if the rate exceeds the threshold, v1.2 automated refund pool becomes mandatory.
- Splitter v1 state is immutable except for the `relayer` address (rotatable via `setRelayer()` under multisig admin, per Am-1). Any other bug fix or feature change requires deploying v2 and migrating Providers via re-registration — the explicit trade-off for not introducing proxy attack surface.
- **"Atomic" is qualified to "single-block atomic"** (Am-4). The x402.org facilitator does not currently support a post-pull contract call within the same transaction, so the canonical settlement flow is two transactions in one block (`recordSettlement` then `splitFor`, ~2 s apart). All marketing copy and documentation MUST use "single-block atomic", never "same-tx atomic". A custom JECP facilitator that bundles pull + split into one tx is on the v1.2 roadmap (B-5 alternative).
- KMS signing for the `RELAYER` adds +80-120 ms per `register()` call and ~3 MB to the Hub binary (`alloy-signer-aws` crate). Acceptable for a non-hot-path operation that fires only at `POST /v1/manifests/{id}/promote` (lazy-on-promote per Am-6), not on every invoke.
- Operator wallet addresses (Hub treasury, Network reserve, Provider payout, RELAYER, RELAYER_ADMIN) are visible on the Base public ledger. Provider revenue flow is observable to determined analysts. Documented as inherent to USDC/Base choice.

### Post-approval amendments (v1.1.x: v1.1.1 amendments Am-1..Am-6 dated 2026-05-11; v1.1.0-rc3 amendment Am-7 dated 2026-05-16)

- **v1.1.1 amendments (Am-1 through Am-6)**: post-Splitter mini-panels, 2026-05-11. The Splitter contract scope (B-1) was sent to two mini-panels (`threat-modeler-splitter` and `factory-architect-splitter`). They surfaced 3 Critical design defects and 3 quality refinements; the admiral approved all six without exception. Locked-design canonical record: `docs/jecp/x402-integration-locked-design.md` §14.
- **v1.1.0-rc3 amendment (Am-7)**: rc3 trust-model redesign, 2026-05-16. External review surfaced that the rc2 `AUTHORIZED_SETTLER = facilitator EOA` assumption contradicted both x402.org's actual fleet architecture and the x402 README design principles. Am-7 supersedes the rc2 OQ at the bottom of this table by redefining `AUTHORIZED_SETTLER` as a Hub-operated keeper EOA (AWS KMS-backed). Body section "Am-7" below. Companion errata: `spec/v1.1.0-rc3-errata.md`.

| ID | Pre-amendment | Post-amendment | Risk closed |
|---|---|---|---|
| **Am-1** | `address public immutable REGISTRAR` (Hub server EOA) had full authority to register and reassign capabilities — directly contradicted the "Hub holds no key" thesis (mini-panel `SC-C1` Critical). | Renamed to `address public relayer` (mutable, rotatable via `setRelayer()` under `RELAYER_ADMIN` multisig). `register()` now requires a Provider EIP-712 signature recovered to the declared `provider` address; the RELAYER pays gas only. | If the RELAYER key leaks, the attacker can DoS new registrations (refuse to relay) — they cannot reassign existing capabilities or steal future settlements. |
| **Am-2** | `splitFor(id, payer, amount)` was permissionless and accepted a caller-supplied amount — any caller could trigger a drain by passing the full contract balance (mini-panel `SC-A1` Critical). | New `recordSettlement(capabilityId, amount)` is gated to `AUTHORIZED_SETTLER` (per Am-7: the Hub-operated keeper EOA, AWS KMS-backed) and updates an `accountedBalance[capabilityId]` ledger. `splitFor(capabilityId, payer)` reads the ledger only, zeroes it (CEI), and accepts no caller-supplied amount. EIP-712 nonce replay defense added via `usedNonces` mapping. | Permissionless drain via crafted `amount` is structurally impossible. |
| **Am-3** | Direct `USDC.transfer()` to `cap.provider` in `splitFor()` would revert the entire split if the provider was USDC-blacklisted, used a contract that reverts on receive, or griefed via gas (mini-panel `SC-A3` High). | `splitFor()` calls Provider transfer via external self-call inside `try/catch`. On failure, the share routes to `providerEscrow[provider]`; the Provider recovers it later via `withdraw()` (pull pattern). Treasury and Reserve are always paid. | One griefing Provider cannot block settlement for any other actor; recoverable via Provider self-service withdraw. |
| **Am-4** | Marketing claim used "atomic 85/10/5 in same tx" — but the x402.org facilitator does not support a post-pull contract call within the same transaction, making the literal claim false. | Wording corrected to **"single-block atomic"**: `recordSettlement` and `splitFor` execute in the same Base block (~2 s apart) but are two separate transactions. The "single-block" property is what we can defend; "same-tx" is what only a custom JECP facilitator (v1.2 roadmap) could deliver. | Marketing claim aligned with on-chain reality; no audit gap on a false atomicity invariant. |
| **Am-5** | Hub-side signing infrastructure was unspec'd; an in-process key (env var or filesystem) was the implicit fallback (integration mini-panel finding). | The `RELAYER` key lives in **AWS KMS** via `alloy-signer-aws`; the plaintext key never appears in Hub binary, env vars, or process memory. KMS signing adds +80-120 ms and ~3 MB binary delta — acceptable on a lazy-on-promote path. | Key extraction via Hub RCE, log leak, or memory dump is structurally impossible — KMS releases signatures, not keys. |
| **Am-6** | Capability registration timing was unspec'd; eager-on-publish was the implicit assumption (every publish hits the chain). | Lazy-on-promote: on-chain `register()` fires only at `POST /v1/manifests/{id}/promote`, not at every `publish`. Gas cost $0.03-0.06 per call, recovered after ~25 paid invokes. | Predictable gas cost; latency on first invoke unaffected; failed/abandoned manifests cost zero gas. |
| **Am-7** | rc2 set `AUTHORIZED_SETTLER` to the x402.org facilitator's settlement EOA — but external review (2026-05-16) found x402.org operates a multi-operator facilitator fleet (not a single EOA), the x402 README design principles forbid the facilitator from moving funds outside client intentions, and the x402 wire protocol does not include a facilitator-initiated post-pull contract call. The premise was non-implementable and trust-model-inverting. | `AUTHORIZED_SETTLER` is redefined as a **Hub-operated keeper EOA** (AWS KMS-backed) that is the ONLY address permitted to call `recordSettlement()`. The x402 facilitator's role is reduced to USDC pull only (per spec). New Invariant I-7 enforces amount attribution across facilitator pull event ↔ keeper `recordSettlement` ↔ Splitter event log. Five new conformance assertions in `conformance/x402/`: `X402_HUB_KEEPER_AUTHORIZED_SETTLER_MATCH`, `X402_FACILITATOR_NOT_TRUSTED_AS_SETTLER`, `X402_RECORD_SETTLEMENT_IDEMPOTENT`, `X402_RECORD_SETTLEMENT_LATENCY_BOUND`, `X402_AMOUNT_ATTRIBUTION_INVARIANT`. Splitter contract is unchanged (immutable preserved). Wire format is unchanged (SDK/CLI compatible). See `spec/v1.1.0-rc3-errata.md` and the "Am-7" body section below for the full normative redefinition. | Trust root is Hub-controlled and rotation-policy-owned end-to-end; x402 design principle (facilitator MUST NOT move funds outside client intentions) honored; the rc2 OQ ("AUTHORIZED_SETTLER must be set to x402.org's actual settlement contract address") is resolved by abandoning the premise rather than answering the question. |

**rc2 OQ (resolved by Am-7, 2026-05-16)**: the v1.1.1 amendment table left the `AUTHORIZED_SETTLER` immutable address as an Open Question — "must be set to x402.org's actual settlement contract address on Base (or, if facilitator uses a recoverable EOA, that EOA)." Am-7 supersedes this OQ entirely: `AUTHORIZED_SETTLER` is now defined as a Hub-operated keeper EOA, not any facilitator-controlled address. The Hub keeper drives `recordSettlement()` from a bounded background loop after the facilitator's settle leg confirms on-chain; the Splitter constructor is set to the keeper EOA at deploy time (see §1.5 of the GA gate for AWS KMS provisioning).

## Alternatives Considered

**B-1: Splitter Contract (chosen).**
Immutable on-chain contract receives full USDC and atomically distributes 85/10/5 within the same tx; Hub holds no signing key on hot path.
*Chosen because:* eliminates the Critical hot-wallet-key threat (`TM-E1`); per-tx atomicity is the load-bearing claim for the marketing position; per-tx cap of $1000 bounds blast radius even if audit misses something. Audit cost is justified by the claim it enables.

**B-2: Hub-side KMS-signed multisig payouts.**
Hub holds a hot wallet key in AWS KMS / HashiCorp Vault; KMS API enforces per-tx amount limits; sweep to cold wallet (Gnosis Safe 2-of-3) every 24h or on $1k threshold; payouts to Providers signed via KMS API; key never leaves HSM.
*Rejected because:* KMS bounds the loss but does not eliminate it. Compromised IAM creds → attacker drains up to the per-tx limit ($10/tx in Panel 2's recommendation) per call until cold wallet sweep cycles. The "Hub holds no key" claim becomes "Hub holds a bounded key" — defensible but no longer load-bearing for the moat. Operationally heavier (KMS region failover, IAM rotation drills, cold wallet ceremony) and still requires the same audit budget. Splitter wins on both threat model and marketing.

**B-3: Stripe co-charge bridging.**
The Hub continues to charge in USD via Stripe; a back-end converter buys USDC and pays Providers on a configurable cadence. Agents see no crypto.
*Rejected because:* re-introduces the 5.9% Stripe rake the integration was meant to eliminate. Defeats the unit-economics goal entirely. Worth keeping as the wallet path (already shipped) but not as the "x402 path".

**B-4: Provider monthly USDC settlement (no Splitter).**
Hub receives USDC into a Hub-controlled multisig; once a month, Hub batch-settles to Providers off-chain via Coinbase commerce.
*Rejected because:* Hub holds Provider funds for up to a month — a custody profile that is squarely in the regulatory crosshair (money transmission, lender-of-record for unsettled balances, possible MSB licensure trigger). The settlement schedule introduces a 30-day reconciliation window during which a Hub compromise drains 30 days of Provider revenue, not 24 hours. Splitter's atomicity (or 1-block atomicity) is strictly better on every axis.

**B-5: Custom facilitator that pulls + splits in one tx.**
JECP runs its own x402 facilitator that bundles the EIP-3009 `transferWithAuthorization` call with the Splitter `splitFor()` call into a single transaction.
*Rejected for v1.1 (kept on v1.2 roadmap):* requires JECP to operate facilitator infrastructure (EVM node + indexer + signature verifier + uptime SLO). v1.1 trusts the x402.org facilitator; per Am-4 the resulting atomicity guarantee is "single-block" (two transactions in one Base block, ~2 s apart) rather than "same-tx", because the x402.org facilitator does not support post-pull contract calls. v1.2 operator runs a custom facilitator as the long-term sovereignty play, the path to true same-tx atomicity, and the basis for multi-facilitator quorum.

**B-6: Hub-server-key `REGISTRAR` (the original v1.1 draft, rejected after Splitter mini-panel).**
The original draft of the Splitter contract gave a single immutable `REGISTRAR` address — held by the Hub-server EOA — full authority to call `register()` and `deactivate()`. Provider opt-in flowed through the Hub.
*Rejected post-mini-panel (Am-1, mini-panel `SC-C1` Critical):* the design directly contradicted ADR-0003's "Hub holds no key on the request hot path" thesis. Anyone with the Hub-server key (env-var leak, RCE, supply-chain compromise of a Hub dependency) could call `register(capabilityId, attackerWallet, 8500, 1000, 500)` for any existing capability and reassign all future revenue to themselves. Storing the REGISTRAR key in KMS bounds the operational surface but does not eliminate the authority — the key still has full reassignment power. The amended design (Am-1) moves authorization to the Provider's own wallet via EIP-712 signature recovery; the Hub-controlled `RELAYER` becomes a pure gas-payer with no authority over capability state. If the RELAYER is compromised, the worst case is a DoS on new registrations — capability ownership and revenue routing remain protected by Provider-held keys.

## References

- `docs/jecp/x402-integration-locked-design.md` (the canonical commander-center synthesis; this ADR is its public-facing distillation). v1.1.1 §14 is the authoritative Amendment register; v1.1.1 §7.2 holds the canonical `JecpSplitter.sol` source.
- `docs/jecp/x402-design/panel-1-protocol.md` — protocol-designer wire format
- `docs/jecp/x402-design/panel-2-threat.md` — threat-modeler STRIDE + 19-subcause registry
- `docs/jecp/x402-design/panel-3-architecture.md` — factory-architect Rust module structure
- `docs/jecp/x402-design/panel-4-ux.md` — product-manager Agent / Provider / Developer UX
- `docs/jecp/x402-design/splitter-panel-threats.md` — threat-modeler-splitter mini-panel (Solidity-specific STRIDE; the source of `SC-A1`, `SC-A3`, `SC-C1` Criticals that motivated Am-1, Am-2, Am-3)
- `docs/jecp/x402-design/splitter-panel-integration.md` — factory-architect-splitter mini-panel (Hub ↔ Splitter integration; the source of Am-5 KMS-signing and Am-6 lazy-on-promote)
- `spec/06-x402-integration.md` — normative integration spec (§8 carries the v1.1.1 Splitter contract surface)
- `spec/03-errors.md` §3.8 — 5 new error codes + 19-subcause registry
- `spec/04-manifest.md` §5 — `pricing.payment_methods`
- `spec/05-discovery.md` §4.4.1 — `payment_methods_supported` in agent-guide
- ADR-0001 — Idempotency × Provenance interaction (companion to ADR-0004)
- ADR-0002 — SSRF defense architecture (applied to facilitator URL at boot per 06 §6.1)
- ADR-0004 — Idempotency × x402 (this ADR's companion)
- [x402 spec v1](https://x402.org)
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712) — typed structured data hashing and signing (Provider-signed `register()` per Am-1)
- [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) — `transferWithAuthorization`
- [USDC on Base](https://basescan.org/token/0x833589fcd6edb6e08f4c7c32d4f71b54bda02913)
- [`alloy-signer-aws`](https://docs.rs/alloy-signer-aws) — Rust AWS KMS Ethereum signer used by the RELAYER per Am-5
- Capital One 2019 SSRF post-mortem (canonical reference for `TM-X1` defense)
- Stripe / Coinbase / Cloudflare custody patterns (cross-reference for B-2 alternative)

---

## Am-7: AUTHORIZED_SETTLER is a Hub-controlled keeper EOA, immutable in Splitter v1 (2026-05-16)

### Decision

`JecpSplitter.AUTHORIZED_SETTLER` is redefined from "the x402 facilitator's settlement contract address (or EOA)" to a **Hub-controlled keeper EOA** whose private key is held exclusively in AWS KMS, immutable on the v1 Splitter (constructor-set, no setter, no proxy — verified on-chain: `JecpSplitter.sol` line 61 declares `address public immutable AUTHORIZED_SETTLER`). The on-chain settlement flow becomes a deterministic two-step **pull-to-treasury** sequence: (1) the x402 facilitator pulls USDC into the Splitter via EIP-3009 `transferWithAuthorization` per the unchanged x402 wire protocol, then (2) the Hub `services/x402_keeper.rs` driver (newly broken out from the v1.1.1 reconciler watcher) actively calls `recordSettlement(capabilityId, amount)` from the keeper EOA, after which `splitFor(capabilityId, payer)` distributes 85/10/5. Key rotation is emergency-only and executed as a **Splitter v2 deploy + capability re-registration ceremony**, not as a key swap on v1.

### Rationale

Am-7 supersedes the OQ deferred at the end of v1.1.1 ("AUTHORIZED_SETTLER must be set to x402.org's actual settlement contract address on Base"). External review on 2026-05-16 surfaced three defects in that premise:

1. **x402.org operates a multi-operator facilitator fleet, not a single contract.** BaseScan labels show facilitator EOAs run by multiple operators — observed: Canza, Coinbase, Daydreams, X402rs — under the shared label pattern `x402 Facilitator N`. Coinbase-operated EOAs use non-consecutive numbering (e.g., 3, 4, 7), confirming the fleet is multi-organization and dynamic. A single immutable hardcode is structurally incompatible with the deployed reality.
2. **x402's published design principle forbids facilitator-initiated post-pull contract calls.** The x402 README states the facilitator "must not move funds outside client intentions"; the `/verify` + `/settle` API surface confirms this — there is no facilitator hook for post-pull `recordSettlement`. Any v1.1 design that relies on the facilitator to call into the Splitter is non-implementable against x402.org as it exists.
3. **The "Hub holds no key on the request hot path" thesis remains intact under Am-7.** `recordSettlement` is off the synchronous `POST /v1/invoke` path; the keeper driver fires in a bounded background loop after the facilitator's settle leg confirms on-chain. The hot path still ends at the agent's `X-Payment` retry → facilitator `/settle` → 200 with `X-Payment-Response`. The keeper EOA signs only the bookkeeping ledger update, never a fund-movement authorization (CEI in `splitFor` guarantees `accountedBalance` is the only fund-routing input).

Three alternatives were considered and rejected:

- **(i-rejected) `AUTHORIZED_SETTLER` as a setter-mutable address on v1.** Mutability concentrates upgrade authority in whoever holds the rotator key, expanding the audit surface (re-entrancy in the setter, ACL on the setter, event integrity on rotation) without materially improving rotation hygiene — AWS KMS asymmetric-key auto-rotation generates a new public key, which under EVM semantics is a new address; rotation is therefore a migration, not a swap, regardless of whether the slot is mutable. Mutability buys nothing and costs audit hours.
- **(ii-rejected) Proxy pattern (UUPS / Transparent).** Over-engineering for v1.1 scope; introduces a delegate-call surface to audit and a new contract to deploy. Deferred to v1.2 as the upgrade-path option if rotation cadence in production exceeds once per 18 months.
- **(iii-rejected) Allowlist set of settler addresses.** Equivalent to (i) with a larger surface; same conclusion.

The chosen design (immutable v1 + emergency v2 deploy) follows the well-established blockchain pattern for identity-bound keys: rotation by redeploy + migration ceremony, since on-chain address identity precludes silent key swap. The audit surface remains bounded to constructor-set immutables already in scope, and the Provider-signed EIP-712 registration model (Am-1) is preserved intact across rotations.

### On-chain defense-in-depth (verified against `jecp-contracts/src/JecpSplitter.sol`)

The "immutable + emergency ceremony" model does not stand alone; it is layered with on-chain caps and CEI ordering:

- **`PER_TX_CAP` on `recordSettlement`** (L293): every keeper call MUST satisfy `amount <= PER_TX_CAP` or revert `AmountExceedsCap`. Bounds the blast radius of a compromised keeper key to one cap per transaction. Combined with Hub-side per-day call cap and feature_flag soft-kill (`x402_keeper_enabled = false`, ≤60 s effect), the on-chain primitive provides a hard ceiling no off-chain control can override.
- **`accountedBalance`-only distribution** (L309): `splitFor` distributes only what the keeper has declared via `recordSettlement`, never the raw contract balance. Direct USDC transfers to the Splitter address (dust / griefing) accumulate as unattributed contract balance — annoying for the reconciler (raises `X402_RECONCILER_MISMATCH_FLAGGED`) but **not exploitable** for value theft. AV-1 (dust attack) is mitigated by this invariant.
- **CEI in `splitFor`** (L313): `accountedBalance[capabilityId] = 0` is set before any external transfer, eliminating reentrancy as a path to double-spend. AV-3 (reaper griefing) becomes a non-attack — anyone may pay gas to call `splitFor`, but the outcome is deterministic.
- **Provider escrow on push failure** (L328-333): a USDC-blacklisted or reverting Provider does not block treasury / reserve transfers; the Provider share is escrowed and the Provider can pull via `withdraw()` once unblocked.

These on-chain primitives are the audit firm's anchor: Am-7 changes the *meaning* of `AUTHORIZED_SETTLER` and the *off-chain caller* of `recordSettlement`, but every on-chain invariant the v1.1.1 Splitter design already enforced remains enforced. No Solidity edit is required for rc3.

### Rotation procedure (emergency only, SLA < 72 h)

Triggered if and only if the keeper EOA's KMS key is suspected compromised or its CloudTrail audit chain is broken. Routine cadence is **never**.

1. **T+0h — Detect & freeze.** Operator flips `feature_flags.x402_enabled = false` (existing kill switch, ≤60 s effect). All new x402 invokes return `X402_NOT_ACCEPTED` subcause `x402_disabled`. In-flight settlements (already `/settle`'d at facilitator, awaiting `recordSettlement`) are flagged in the keeper-driver and held; Hub absorbs any Provider payout delay under the existing 24 h refund SLA.
2. **T+4h — Deploy Splitter v2.** Compile and deploy `JecpSplitter` with new `AUTHORIZED_SETTLER` = new keeper EOA (new KMS asymmetric key, fresh public key derived). All other immutables (`HUB_TREASURY`, `NETWORK_RESERVE`, `PER_TX_CAP`, EIP-712 domain separator with `chainId` and new `verifyingContract`) re-set. Verify on BaseScan.
3. **T+8h — Capability migration ceremony.** For every active capability `c` registered on Splitter v1, the Provider re-signs the EIP-712 `register()` payload against Splitter v2's domain separator. Hub coordinates via a one-shot migration endpoint (`POST /v1/manifests/{id}/migrate-splitter`); Providers who do not sign within T+48 h are marked `inactive` and their capabilities return 404 until re-registered. The migration list is published as a JSON file at `https://jecp.dev/.well-known/jecp-splitter-migration-v1-to-v2.json` (immutable, content-addressed by Splitter v2 address).
4. **T+24h — Update Hub config.** Hub `JECP_SPLITTER_ADDRESS` env var points at Splitter v2; `JECP_HUB_KEEPER_KMS_KEY_ID` points at the new KMS key. Rolling deploy across Fly.io regions; keeper driver picks up the new address on next health-check tick.
5. **T+48h — Drain Splitter v1.** Hub treasury multisig coordinates with each capability owner to call `splitFor` for any residual `accountedBalance`; remaining unattributed contract balance (if any) is acknowledged as locked-by-design (no admin sweep exists on v1 — this is intentional and documented).
6. **T+72h — Flip kill switch back.** `feature_flags.x402_enabled = true`. Post-mortem published within 7 days at `https://jecp.dev/security/incidents/`.

The ceremony is **disruptive by design**: rotation friction forces public accountability and aligns operator incentives with key-hygiene best practices for on-chain identity-bound keys.

### Decommissioning policy

Splitter v1 is **never deleted**, only decommissioned. Post-migration, v1 retains immutable history of all `recordSettlement` and `splitFor` events for audit and forensic analysis. The Hub MAY mark v1 as `decommissioned` in its public capability registry; clients MUST treat any `pay_to = Splitter_v1_address` in a 402 challenge as a Hub bug (return `X402_NOT_ACCEPTED` subcause `network_unsupported` if encountered post-migration). BaseScan verification metadata, Foundry source, and audit reports for v1 remain published in perpetuity at `github.com/jecpdev/jecp-contracts` under the `v1.1.x` tag.

### AV disposition (post-Outside-Observer verification)

Outside Observer review (2026-05-16) raised 4 attack vectors against the (b) design. Disposition:

- **AV-1 (Splitter dust attack)**: ✅ mitigated by `accountedBalance`-only distribution (L309). Unattributed dust is locked, not exploitable. Reconciler raises informational mismatch.
- **AV-2 (Base reorg double-record)**: ✅ mitigated by keeper-driver waiting ≥1 confirmation before calling `recordSettlement`; the on-chain `usedNonces` (Am-2) guarantees idempotency even on reorg replay. Conformance YAML `X402_RECORD_SETTLEMENT_IDEMPOTENT` enforces.
- **AV-3 (splitFor reaper griefing)**: ✅ no-op attack. CEI ordering + deterministic distribution make front-running outcome-equivalent to admin-run. Gas cost falls on attacker.
- **AV-4 (keeper key compromise → unlimited recordSettlement)**: ✅ bounded by `PER_TX_CAP` (L293) + Hub-side per-day call cap + feature_flag soft-kill + KMS audit-trail via CloudTrail. Worst case: 1 × `PER_TX_CAP` × (calls-before-detection). Detection target: ≤5 min via Better Stack alarm on call-rate anomaly. Rotation per this Am-7 procedure.

### Consequences

**Positive**

- **Implementation aligns with x402.org's deployed multi-operator facilitator fleet.** No dependency on a non-existent single facilitator contract address; the Hub keeper drives `recordSettlement` regardless of which facilitator EOA performed the pull.
- **Audit surface bounded to constructor-set immutables already in v1.1.1 scope.** Splitter v1 has no rotator function, no allowlist mapping, no upgrade slot — the audit (Spearbit / Cure53 / Trail of Bits per BS-4 3-scope split) covers the same primitives already in scope for v1.1.1 plus one renamed role.
- **Rotation discipline is enforced by ceremony cost.** Operator cannot quietly swap keys; every rotation is a public, content-addressed event with Provider sign-off.

**Negative**

- **Rotation requires Provider coordination.** Capability re-signing is a 24–48 h Provider-side operation. Providers offline during the ceremony experience capability downtime. Mitigation: the `feature_flags.x402_enabled` kill switch holds the system in a degraded-but-safe state with Stripe wallet path unaffected; existing 24 h refund SLA covers in-flight settlements.
- **Splitter v2 deploy is a non-trivial operation under time pressure.** Foundry build + Base mainnet deploy + BaseScan verify + Hub config rollout + Provider coordination is realistically 48–72 h of operator wall-clock, not minutes. The 72 h SLA is the worst-case bound, not the target. v1.2 MAY introduce a proxy pattern to reduce ceremony cost if rotation frequency observed in v1.1 production exceeds once per 18 months.

### References

- **Am-7** (this amendment) — supersedes the v1.1.1 OQ on `AUTHORIZED_SETTLER` address resolution.
- **Am-1** — Provider EIP-712 registration; unaffected by Am-7 (Provider signatures bind to the Splitter's `verifyingContract`, which is re-derived per Splitter version).
- **Am-2** — `recordSettlement` + `accountedBalance` ledger; semantics unchanged, caller redefined from "facilitator settlement helper" to "Hub keeper EOA driver".
- **x402 specification v1** (https://x402.org) — `/verify` + `/settle` API surface; confirmation that no post-pull contract call hook exists in the facilitator.
- **x402 README design principles** (https://github.com/coinbase/x402/blob/main/README.md) — "facilitator must not move funds outside client intentions"; the principle Am-7 honors.
- **BaseScan facilitator fleet observation** (2026-05-16) — multiple operators (Canza, Coinbase, Daydreams, X402rs) labelled as `x402 Facilitator N`; basis for rejecting the single-address premise.
- **`jecp-contracts/src/JecpSplitter.sol`** — line 61 verified immutable; line 293 PER_TX_CAP enforcement; line 309 accountedBalance-only distribution. R-2/R-3 verified.
