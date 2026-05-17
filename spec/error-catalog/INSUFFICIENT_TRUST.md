# `INSUFFICIENT_TRUST`

> Public URL: https://jecp.dev/errors/insufficient_trust
> Spec source: `spec/03-errors.md` §3.1
> Last updated: 2026-05-17

## What it means

The Agent is authenticated, but its trust tier is below the minimum the capability declares in its manifest's `trust_tier_required` field. Trust tiers gate access to potentially-expensive or sensitive capabilities — an Agent with no track record cannot invoke them on day one.

HTTP status: `403 Forbidden`.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "INSUFFICIENT_TRUST",
    "message": "Insufficient trust tier: platinum required, you are bronze"
  },
  "next_action": {
    "type": "earn_trust",
    "current_tier": "bronze",
    "required_tier": "platinum",
    "description": "Make more paid calls to upgrade trust tier (100/500/2000 thresholds)",
    "fallback": {
      "alternative": "Use lower-tier capabilities (content-factory, sns-engine) to build call count"
    }
  }
}
```

The `next_action.current_tier` and `next_action.required_tier` fields are the canonical machine-readable form; SDKs SHOULD surface these instead of parsing `error.message`.

## Trust tier ladder

| Tier | Threshold | Typical use |
|---|---|---|
| `bronze` | New Agent, < 100 paid calls | Evaluation, small experiments, simple capabilities |
| `silver` | ≥ 100 paid calls | Most content / utility capabilities |
| `gold` | ≥ 500 paid calls | Higher-cost calls, longer-running actions |
| `platinum` | ≥ 2000 paid calls | Workflow composites, autonomous workflows, expensive Provider calls |

Free-tier calls do not count toward the threshold — only paid calls (wallet, mandate, or x402 settlement) increment the trust counter. This is by design: the trust signal is "has this Agent's principal proven willingness to pay for outputs?"

## Fix in 30s

### Build trust on lower-tier capabilities

Pick a capability whose `trust_tier_required` matches your current tier and build call count there. Most utility capabilities (translation, summarization, simple image transforms) are `bronze`. The catalog lists each capability's required tier:

```bash
jecp catalog --json | jq '.capabilities[] | {id: .full_id, tier: .trust_tier_required}'
```

### Or use the explicit fallback

The `next_action.fallback.alternative` field names specific lower-tier capabilities that achieve a similar outcome. Treat it as a hint, not a prescription — the alternative may or may not actually substitute for your use case.

### Avoid the gaming pitfall

Running 100 trivial paid calls to clear `bronze → silver` works, but the Hub also tracks call quality (refund rate, abuse reports, mean cost-per-call). An Agent that churns 100 $0.001 calls in a minute to upgrade may trip an anomaly detector and have its tier *demoted*. Trust grows fastest with consistent, real workload.

## Why trust is gated this way

Without a trust mechanism, a freshly-registered Agent could immediately invoke `workflow.*` capabilities that cost dollars per call. Providers would absorb the loss of every refund storm, and the Hub would become an attractive vehicle for spam. The trust tier system gates the high-cost surface behind demonstrated track record — same idea as Stripe / Twilio account aging, applied to Agent autonomy.

This is a soft gate, not a hard ban: every Agent can earn their way up by making real paid calls on the low-cost surface first.

## Related errors

- `AUTH_REQUIRED` / `INVALID_API_KEY` — Agent not authenticated at all.
- `RATE_LIMITED` — Agent identified, rate exceeded (not a trust issue).
- `INSUFFICIENT_BALANCE` — Agent's tier is OK but the wallet can't cover the cost.
