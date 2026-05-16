# `INSUFFICIENT_BUDGET`

> Public URL: https://jecp.dev/errors/insufficient_budget
> Spec source: `spec/01-protocol.md` (mandate semantics)
> Last updated: 2026-05-16

## What it means

The Agent's wallet has funds, but the `mandate.budget` cap on this specific request was set below the action's quoted price. The Hub honors the mandate as the per-call ceiling: even if the wallet could pay, the Agent has explicitly said "do not spend more than X on this call."

HTTP status: `402 Payment Required`.

This is distinct from `INSUFFICIENT_BALANCE` (the wallet itself is empty/short).

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "INSUFFICIENT_BUDGET",
    "message": "mandate.budget $0.001 USDC below action price $0.005 USDC",
    "details": {
      "budget_usdc": "0.001",
      "required_usdc": "0.005",
      "documentation_url": "https://jecp.dev/errors/insufficient_budget"
    }
  }
}
```

## Fix in 30s

### Raise the budget

```bash
jecp invoke jobdonebot/content-factory translate \
  --input '{"text":"Hello","target_lang":"JA"}' \
  --budget 1.00     # raise from default to $1 USDC
```

In SDK code:

```ts
await client.invoke({
  capability: 'jobdonebot/content-factory',
  action: 'translate',
  input: { text: 'Hello', target_lang: 'JA' },
  mandate: { budget: 1.00 },
});
```

### Or pick a cheaper action

Inspect alternatives in the catalog:

```bash
jecp catalog --json | jq '.capabilities[].actions[]
  | {full: "\(.capability_id).\(.id)", price: .pricing.base}
  | select(.price < "$0.005")'
```

## Why the Hub honors the mandate even when balance is OK

The mandate is the Agent's intent declaration — a circuit-breaker for autonomy. A long-running workflow that spawns many invocations may have a wallet with thousands of dollars, but the operator wants each individual call capped so a runaway loop cannot drain the wallet. The Hub enforces the cap precisely because the wallet check alone is insufficient.

Setting `mandate.budget` to a generous-but-finite value (e.g. 100× the expected price) is the standard pattern for production workloads. Setting it equal to wallet balance defeats the purpose.

## Related errors

- `INSUFFICIENT_BALANCE` — wallet itself is short.
