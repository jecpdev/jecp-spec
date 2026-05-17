# `SERVICE_ERROR`

> Public URL: https://jecp.dev/errors/service_error
> Spec source: `spec/03-errors.md` §3.6 + §3.7
> Last updated: 2026-05-17

## What it means

The Hub could not reach an upstream Provider, or the Provider returned a 5xx with no useful body. This is a transport-level failure: the Hub itself is healthy, but a dependency it relies on is not.

HTTP status: `500 Internal Server Error` (reference Hub) — note: spec §3.6 maps this code to HTTP 502 (Bad Gateway, the canonical "upstream is broken" code). The reference Hub currently emits 500; treat the wire status as the source of truth and branch on `code`. The catalog page tracks 502 as the migration target.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "SERVICE_ERROR",
    "message": "External service error: provider returned 503"
  }
}
```

The `error.message` may name the upstream (Provider, facilitator, database, etc.) but does NOT include hostname, raw response body, or internal IP. Per spec §3.7, Hubs must sanitize messages.

## Fix in 30s

### Retry with exponential backoff

`SERVICE_ERROR` is the most retry-safe of the 5xx codes. The standard recovery:

```ts
async function withBackoff(fn, maxAttempts = 4) {
  let delay = 1000;
  for (let i = 0; i < maxAttempts; i++) {
    try { return await fn(); }
    catch (e) {
      if (e.code !== 'SERVICE_ERROR' || i === maxAttempts - 1) throw e;
      await sleep(delay);
      delay *= 2;
    }
  }
}
```

Cap at 4 attempts with 1s / 2s / 4s / 8s delays. Beyond that, the Provider is structurally down and retrying further just wastes calls.

### When backoff doesn't help

If `SERVICE_ERROR` persists across 4 attempts spanning ~15 seconds:

1. Check the Provider's status page — capabilities link to it from the catalog.
2. Look for similar failures across Agents — `jecp status --since 1h` shows your recent calls; a coordinated cluster of `SERVICE_ERROR` means the Provider is broadly degraded.
3. Switch to an alternative capability. The catalog usually surfaces 2-3 substitutes for common categories (translate, summarize, etc.).
4. Contact the Hub operator if multiple unrelated Providers are returning `SERVICE_ERROR` — the issue may be Hub-side networking.

### Don't tight-loop

A retry every 100ms is hostile — both to the Provider and to your own rate limit. The Hub will eventually start returning `RATE_LIMITED` (429) instead of `SERVICE_ERROR`, and at that point you've made the problem worse. Honor the back-off.

## Billing

A `SERVICE_ERROR` that fires *before* the Provider call is started does not consume balance. A `SERVICE_ERROR` that fires *after* a Provider call returned but during result processing MAY be auto-refunded by the Hub — check `jecp status` for refund records.

In practice, almost all `SERVICE_ERROR` cases are pre-call (the Hub couldn't reach the Provider at all) and are not billed.

## Why this is distinct from `EXECUTION_FAILED`

| Code | Layer | Cause |
|---|---|---|
| `SERVICE_ERROR` (this page) | Transport | Provider unreachable; TCP timeout; DNS failure; Provider returned bare 5xx |
| `EXECUTION_FAILED` | Handler | Capability handler ran but couldn't classify its failure; or Provider returned a 5xx with a structured error body that didn't map to a JECP code |
| `INTERNAL_ERROR` | Hub | Hub-side bug or panic |

`SERVICE_ERROR` says "the upstream wasn't reachable / didn't respond meaningfully." `EXECUTION_FAILED` says "the upstream replied, but the reply was an unclassified failure."

## Related errors

- `EXECUTION_FAILED` — capability ran but failed with no specific error mapping.
- `INTERNAL_ERROR` — Hub-side, not Provider-side.
- `RATE_LIMITED` — different cause but you may see this if you tight-loop on `SERVICE_ERROR`.
