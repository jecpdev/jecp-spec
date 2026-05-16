# `RATE_LIMITED`

> Public URL: https://jecp.dev/errors/rate_limited
> Spec source: `spec/03-errors.md` §3
> v1.0.2 K2.4
> Last updated: 2026-05-16

## What it means

The Agent (or its source IP) exceeded the per-window request quota. Hubs apply rate limits at two layers — per-Agent (to protect the protocol from runaway clients) and per-IP (to protect from credential-stuffing scans). Either limit can trigger this code; from the caller's perspective the recovery is the same.

HTTP status: `429 Too Many Requests`.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "RATE_LIMITED",
    "message": "rate limit exceeded; retry after 12s",
    "details": {
      "retry_after_seconds": 12,
      "documentation_url": "https://jecp.dev/errors/rate_limited"
    }
  }
}
```

The Hub also sets the standard `Retry-After` response header to the same integer. Some SDKs parse only the header, some parse only the body; spec §3 K2.4 requires both for parity.

## Fix in 30s

Sleep for at least `retry_after_seconds`, then retry. The `@jecpdev/sdk` handles this automatically — see the `retry` module. For manual implementations:

```ts
async function withRateLimitBackoff(fn) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const res = await fn();
    if (res.status !== 429) return res;
    const sec = parseInt(res.headers.get('retry-after') ?? '1', 10);
    await new Promise((r) => setTimeout(r, sec * 1000));
  }
  throw new Error('exhausted retries');
}
```

## Do not tight-loop on 429

Retrying immediately without honoring `retry_after_seconds` will not work — the Hub uses a sliding window, so an immediate retry counts toward the same budget that just got rejected. Worse, repeated immediate retries from a single IP can trip the per-IP limit and lock you out longer. The Hub's behavior is intentional: the response carries the exact wait time so well-behaved clients can resume cleanly.

## If 429 is sustained

If you are consistently rate-limited even with proper back-off:

- Check your invocation pattern — are you sending one request per work item when you could batch?
- If you are a Pro tier customer, the per-Agent limit is higher than free. Confirm your tier with `jecp status`.
- If your workload genuinely exceeds the published limits, contact `hello@jecp.dev` to discuss raising them.

## Related errors

- `INSUFFICIENT_BALANCE` — different cause (funds, not frequency) but also blocks invocation.
