# `INTERNAL_ERROR`

> Public URL: https://jecp.dev/errors/internal_error
> Spec source: `spec/03-errors.md` §3.7
> Last updated: 2026-05-17

## What it means

The Hub hit an internal bug or unexpected condition while processing your request. This is not a Provider failure, not a transport issue, not a credential problem — it's the Hub itself failing to do its job. The Hub operator owns the fix.

HTTP status: `500 Internal Server Error`.

Per spec §3.7, the Hub MUST NOT include stack traces, internal hostnames, raw exception text, or database error strings in `error.message`. If you need the trace to file a bug, the Hub operator's audit log has it — share the request `id` and timestamp with them.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "INTERNAL_ERROR",
    "message": "Internal server error"
  }
}
```

The `error.message` is intentionally terse. A more descriptive message would risk leaking implementation details. The Hub records the full trace internally and correlates it to the request `id` your client logged.

## Fix in 30s

### Retry once after a few seconds

Most `INTERNAL_ERROR` instances are transient: a momentary DB hiccup, a deploy rollover, a transient panic in a single worker. One retry after 2-5 seconds is the standard recovery:

```ts
async function withOneRetry(fn) {
  try { return await fn(); }
  catch (e) {
    if (e.code === 'INTERNAL_ERROR') {
      await sleep(3000);
      return fn();
    }
    throw e;
  }
}
```

### When it persists

If `INTERNAL_ERROR` fires across multiple retries, the Hub is sustained-broken. Steps:

1. Check `https://jecp.dev/status` (or your Hub operator's equivalent). A red status confirms a known incident.
2. Look at the Hub's recent commits / deploy timeline. A `INTERNAL_ERROR` that appears immediately after a deploy is a regression — the operator may roll back.
3. File a bug to the Hub operator with your request `id`, the timestamp, and the failing capability. Without the request id the operator cannot correlate to internal logs.

### Don't blame your input

Unlike `INPUT_SCHEMA_VIOLATION` or `VALIDATION_FAILED`, `INTERNAL_ERROR` is not your input's fault. The same input that triggers `INTERNAL_ERROR` today may succeed tomorrow with no change on your end. Do not try to "fix" your input by mutating it — that risks producing genuinely-invalid input that then fails for a different reason and obscures the real bug.

## Billing

`INTERNAL_ERROR` is never billed. The Hub auto-refunds any partially-completed charge attributable to its own bug. Check `jecp status` to confirm; if you see a charge for a failed `INTERNAL_ERROR` invocation, that's itself a bug — escalate to the Hub operator.

## Why the Hub returns an opaque message

A response body that leaked stack traces, internal IPs, database queries, or version strings would be a free intelligence-gathering surface for an attacker. The opaque "Internal server error" message is intentional: clients need to know that retry is the next step, not *what* failed internally.

This is the same posture every production API takes (Stripe, GitHub, AWS — all return generic 500s with no internal detail). Debugging requires the operator's logs, which require the request `id`.

## Related errors

- `SERVICE_ERROR` — failure attributable to upstream Provider, not the Hub itself.
- `EXECUTION_FAILED` — capability handler failed (could be Provider or Hub).
- `DB_UNAVAILABLE` — Hub-internal, narrower variant (some Hubs emit this on DB-specific failures).
