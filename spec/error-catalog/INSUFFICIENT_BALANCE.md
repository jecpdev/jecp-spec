# `INSUFFICIENT_BALANCE`

> Public URL: https://jecp.dev/errors/insufficient_balance
> Spec source: `spec/01-protocol.md` (billing) + `spec/06-x402-integration.md`
> Last updated: 2026-05-16

## What it means

The Agent's wallet balance does not cover the action's quoted price. The Hub checks balance BEFORE forwarding the invocation to the Provider, so you are not charged and the Provider is not called.

HTTP status: `402 Payment Required`.

This is distinct from `INSUFFICIENT_BUDGET` (the wallet has funds, but `mandate.budget` was capped below the price) and from `RATE_LIMITED` (request frequency, not funds).

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "wallet balance $0.003 USDC below action price $0.005 USDC",
    "details": {
      "balance_usdc": "0.003",
      "required_usdc": "0.005",
      "documentation_url": "https://jecp.dev/errors/insufficient_balance"
    }
  }
}
```

## Fix in 30s

### Stripe (USD → wallet credit)

```bash
jecp topup 5    # add $5 USDC via Stripe Checkout
jecp topup 20   # or $20, $100
```

### x402 / on-chain (USDC on Base)

If your Agent invokes via `--pay x402`, the "balance" is the Agent's Base USDC wallet — not a Hub-side credit. Fund it:

- **Coinbase Onramp**: `pay.coinbase.com`. Card / ACH → Base USDC, delivered to the EOA address derived from `AGENT_BASE_KEY`.
- **Bridge from another chain**: use any Base bridge UI (Across, Hop, official Base bridge, etc.).

Confirm with `jecp status` — it shows both Stripe-paid balance and on-chain wallet balance.

## Why the Hub checks before forwarding

Charging after the Provider has already executed creates a race: a Provider call that succeeds but for which the Agent cannot pay would either lose the Provider money or trap the result behind a paywall the Agent cannot satisfy. JECP avoids both by quoting the price up-front, holding balance for the duration of the call, and rejecting at the gate when funds are short.

## Related errors

- `INSUFFICIENT_BUDGET` — wallet has funds but mandate cap was too low.
- `PAYMENT_REQUIRED` — x402-specific variant; see `spec/06-x402-integration.md`.
