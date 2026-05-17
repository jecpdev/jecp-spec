# `EXECUTION_FAILED`

> Public URL: https://jecp.dev/errors/execution_failed
> Spec source: `spec/03-errors.md` §3.7
> Last updated: 2026-05-17

## What it means

The capability handler started executing and then threw an error the Hub could not classify into a more specific code. Either the Provider's HTTPS endpoint returned non-2xx, the in-process handler raised an unhandled exception, or some other internal failure short-circuited the call.

HTTP status: `500 Internal Server Error` (reference Hub) — note: spec §3.7 maps this code to HTTP 502 when the failure is attributed to an upstream Provider. The reference Hub emits 500 currently; clients should branch on `code` for portable behavior. The catalog page tracks the spec-canonical 502 mapping as the migration target.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "EXECUTION_FAILED",
    "message": "Capability execution failed: provider returned 502 after retry"
  }
}
```

Per spec §3.7, the Hub MUST NOT include stack traces, raw exception text, internal hostnames, or database error strings in the response. The `error.message` is sanitized to a single human-readable line. If you need deeper debugging, ask the Hub operator to share the corresponding entry from their audit logs — the Hub side has the full trace.

## Fix in 30s

### Retry once with backoff

Most `EXECUTION_FAILED` cases are transient: a momentary network blip, a single Provider VM restarting, a brief DB connection drop. The standard recovery is one retry after 1-2 seconds:

```ts
async function withSingleRetry(fn) {
  try { return await fn(); }
  catch (e) {
    if (e.code === 'EXECUTION_FAILED') {
      await sleep(1500);
      return fn();
    }
    throw e;
  }
}
```

Do not loop indefinitely. `EXECUTION_FAILED` that persists across two attempts is structural, not transient — see below.

### When it persists

If the same invocation fails repeatedly:

1. The capability may be broken at the Provider level. Check the Provider's status page or `support_email` from the catalog.
2. Your `input` may be triggering a specific failure path. Try with a minimal valid input — if that succeeds, the larger input is the issue.
3. The Hub may be degraded. Compare against another Hub or wait 5-10 minutes and try again.

### Don't retry expensive calls

For calls that cost meaningful money (workflow composites, long Provider executions), do NOT auto-retry. The original call may have partially succeeded — a retry could double-charge or trigger a second side effect. Inspect manually first.

## Billing

When the Hub returns `EXECUTION_FAILED`:

- If the failure happened *before* the Hub forwarded to the Provider, no charge is applied.
- If the failure happened *during or after* Provider execution, the Hub MAY refund automatically (the refund decision is logged). Check `jecp status --since 1h` for refund entries.

The Provider's own refund policy may also apply — check the capability's manifest for refund-on-error semantics.

## Why this is distinct from `SERVICE_ERROR` and `INTERNAL_ERROR`

| Code | Locus | When |
|---|---|---|
| `EXECUTION_FAILED` (this page) | Capability handler / Provider call | Provider returned non-2xx or handler threw a classified-but-not-billable error |
| `SERVICE_ERROR` | External dependency | Provider is unreachable or returned 5xx; differs from EXECUTION_FAILED in being a transport-level failure rather than a handler outcome |
| `INTERNAL_ERROR` | Hub itself | Hub-side bug, panic, unexpected condition that didn't originate from the Provider |

The split tells you where to look: `EXECUTION_FAILED` → Provider docs / Provider-side logs. `SERVICE_ERROR` → transient network conditions, retry. `INTERNAL_ERROR` → Hub-operator escalation.

## Related errors

- `SERVICE_ERROR` — upstream Provider unreachable or returned 5xx (transport-level).
- `INTERNAL_ERROR` — Hub-side bug; not the Provider's fault.
- `COMPOSITE_STEP_FAILED` — workflow composite step failed; carries the underlying error envelope.
