# `FREE_TIER_EXHAUSTED`

> Public URL: https://jecp.dev/errors/free_tier_exhausted
> Spec source: `spec/03-errors.md` §3.4
> Last updated: 2026-05-17

## What it means

The Agent has used up its free-tier quota. New Agents receive 100 free calls at registration for evaluation; this code fires when the 101st free-tier call is attempted with no other funding source attached. The Hub rejects before forwarding to the Provider.

HTTP status: `429 Too Many Requests`.

Note: the spec catalogs this code in §3.4 (Billing) with HTTP 402, but the reference Hub at `jecp/src/protocol/errors.rs` emits HTTP 429 (the same status used for `RATE_LIMITED`). The discrepancy is tracked for v1.0.3; treat the wire status as authoritative for now and parse the `code` string for branching.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "FREE_TIER_EXHAUSTED",
    "message": "Free tier limit reached"
  }
}
```

The Hub does not currently attach a `next_action` block to this code in the reference implementation (the wallet-topup `next_action` is reserved for 402 codes). Manual recovery via `jecp topup` is the documented path.

## Fix in 30s

### Top up the wallet

```bash
jecp topup 5      # $5 USDC equivalent via Stripe Checkout
jecp topup 20     # or $20, $100
```

Once the wallet has balance, subsequent invocations charge against it. Free tier is for evaluation only; production workloads should fund the wallet up-front.

### Or invoke a free capability

Many Providers publish free capabilities for evaluation. Discover them:

```bash
jecp catalog --free
```

The catalog page renders the same list at `https://jecp.dev/catalog?free=true`.

### Or attach a mandate with x402 settlement

If your Agent is wired to on-chain USDC payment via x402, set `--pay x402` on the next invocation and the call charges the Agent's Base USDC wallet directly, bypassing the Hub-side free-tier counter.

## Why the Hub has a free tier at all

The free tier is for evaluation: new developers should be able to register, write an integration, and verify end-to-end without dealing with Stripe Checkout or on-chain payment up front. 100 calls is enough to write and test most integrations; after that the Agent should be on a real funding source.

The Hub does not extend the free tier on request — gaming the free tier by registering many Agents is detectable and prohibited by the AUP. If your workload is genuinely educational or non-commercial, contact `hello@jecp.dev` for a credit grant instead of farming Agents.

## When it fires vs. `PAYMENT_REQUIRED`

| Scenario | Code |
|---|---|
| Free tier exhausted, no wallet, no mandate | `PAYMENT_REQUIRED` (402) |
| Free tier exhausted, wallet present but $0, no mandate | `INSUFFICIENT_BALANCE` (402) |
| Free tier exhausted, mandate cap below price | `INSUFFICIENT_BUDGET` (402) |
| Free tier exhausted, no other source explicitly checked | `FREE_TIER_EXHAUSTED` (429, this page) |

`FREE_TIER_EXHAUSTED` is emitted when the per-Agent free-tier counter is the specific gate that failed; the more generic 402 codes fire when other billing layers (wallet, mandate, x402) are involved.

## Related errors

- `PAYMENT_REQUIRED` — no funding source available at all.
- `INSUFFICIENT_BALANCE` — wallet exists but balance < price.
- `RATE_LIMITED` — different cause (rate, not funds) but same 429 status; check `code` to disambiguate.
