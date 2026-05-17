# `PAYMENT_REQUIRED`

> Public URL: https://jecp.dev/errors/payment_required
> Spec source: `spec/03-errors.md` §3.4 + `spec/06-x402-integration.md`
> Last updated: 2026-05-17

## What it means

The Hub identified the Agent, the capability, and the action — but the Agent has no way to pay for this invocation. Free tier is exhausted (or wasn't applicable), the wallet has no balance, and no mandate was supplied as a fallback. The Hub rejects at the billing gate before forwarding to the Provider.

HTTP status: `402 Payment Required`.

This is the catch-all 402. The more specific 402 variants are `INSUFFICIENT_BALANCE` (wallet was checked, came up short) and `INSUFFICIENT_BUDGET` (mandate cap was below the price). `PAYMENT_REQUIRED` fires when none of those checks even had something to compare against — the Agent has no funding source at all.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "PAYMENT_REQUIRED",
    "message": "Payment required"
  },
  "next_action": {
    "type": "topup",
    "ui": "https://jecp.dev/topup",
    "api": "https://jecp.dev/api/agents/topup",
    "method": "POST",
    "headers": ["X-Agent-ID", "X-API-Key"],
    "body_example": { "amount": 5 },
    "allowed_amounts_usd": [5, 20, 100],
    "description": "Top up your wallet with USD via Stripe Checkout"
  },
  "payment": {
    "protocol": "x402",
    "accepts": [{
      "network": "base-mainnet",
      "asset": "USDC",
      "description": "Pay with USDC on Base (Stage 2)"
    }],
    "free_alternative": {
      "discover": "https://jecp.dev/v1/capabilities?free=true",
      "description": "Discover free capabilities offered by registered providers"
    }
  }
}
```

Two recovery siblings live alongside the error:

- `next_action.type = "topup"` — Stripe Checkout for USD → wallet credit.
- `payment` (top-level, not inside `details`) — x402 challenge for on-chain USDC settlement.

Old SDKs that don't parse the `payment` field fall back to the wallet path via `next_action`. New SDKs MAY choose either.

## Fix in 30s

### Stripe (USD → wallet credit)

```bash
jecp topup 5     # add $5 USDC equivalent via Stripe Checkout
jecp topup 20    # or $20, $100
```

### x402 (on-chain USDC on Base)

Pass `--pay x402` and the SDK constructs the EIP-3009 authorization automatically:

```bash
jecp invoke jobdonebot/content-factory translate \
  --input '{"text":"Hello","target_lang":"ja"}' \
  --pay x402
```

The Agent's Base USDC wallet (derived from `JECP_AGENT_BASE_KEY`) is debited per call. Fund it via Coinbase Onramp or a Base bridge.

### Free alternative

If you don't want to pay for this specific capability, query the free-capability discovery URL in the `payment.free_alternative.discover` field and pick a substitute. Many Providers offer feature-limited free tiers for evaluation.

## Why the Hub returns this instead of `INSUFFICIENT_BALANCE`

`INSUFFICIENT_BALANCE` is emitted when the wallet was checked and the balance was specifically less than the price. `PAYMENT_REQUIRED` is the generic 402 emitted when no funding source applies at all:

- Agent has zero free-tier calls remaining AND
- Agent has no wallet balance OR no wallet at all AND
- No mandate was attached to the request

If any single funding source exists but is short, you'll get the specific code (`INSUFFICIENT_BALANCE` or `INSUFFICIENT_BUDGET`) instead.

## Related errors

- `INSUFFICIENT_BALANCE` — wallet exists but balance < price.
- `INSUFFICIENT_BUDGET` — wallet has funds, but `mandate.budget` capped below price.
- `FREE_TIER_EXHAUSTED` — free quota was the only available source and it's used up.
- `X402_PAYMENT_INVALID` — x402 path: payload didn't verify with the facilitator (v1.1.0).
