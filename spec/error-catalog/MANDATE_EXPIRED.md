# `MANDATE_EXPIRED`

> Public URL: https://jecp.dev/errors/mandate_expired
> Spec source: `spec/03-errors.md` §3.1 + `spec/02-authentication.md` §5
> Last updated: 2026-05-17

## What it means

The Agent attached a `mandate` block to this request, but `mandate.expires_at` is in the past relative to the Hub's clock. Mandates are short-lived intent declarations — the Agent's principal (a human or another Agent) signed them with a deliberate expiry to bound autonomy. An expired mandate cannot authorize new calls.

HTTP status: `402 Payment Required` (reference Hub implementation).

Note: spec §3.1 maps this code to HTTP 401, while the reference Hub at `jecp/src/protocol/errors.rs` returns 402 (alongside `PAYMENT_REQUIRED` / `INSUFFICIENT_BALANCE` / `INSUFFICIENT_BUDGET`). The discrepancy is tracked for v1.0.3; clients should branch on the `code` string, not the HTTP status, for now.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "MANDATE_EXPIRED",
    "message": "Mandate expired"
  },
  "next_action": {
    "type": "renew_mandate",
    "description": "Issue a new mandate with a future expires_at timestamp"
  }
}
```

The Hub attaches `next_action.type = "renew_mandate"` so SDKs can surface the recovery path without parsing the message.

## Fix in 30s

### Issue a fresh mandate

```ts
const mandate = {
  agent_id:         process.env.JECP_AGENT_ID,
  api_key:          process.env.JECP_AGENT_KEY,
  budget:           1.0,
  expires_at:       new Date(Date.now() + 60_000).toISOString(),  // 60s in the future
  provenance_hash:  computeProvenanceV2({ apiKey, agentId }),
};
```

The reference SDK generates a fresh mandate on every invocation by default. If you're seeing this error, you're caching the mandate object — move construction into the request hot path.

### Set a longer window if your workload is slow

Mandates default to 60-second windows in the reference SDK because that's the longest interval an Agent should reasonably hold an intent declaration without re-validating. If your invocations take longer than that to fire after construction (e.g., they're queued behind a slow planner), extend `expires_at` to a few minutes — but resist the temptation to set it to hours. A long mandate is a long autonomy budget; a leaked long-mandate is a long-lived security incident.

### Common gotchas

- Your server's clock is wrong. Mandates use UTC timestamps; a misconfigured local timezone won't matter because both sides serialize to RFC 3339 with Z suffix — but a *drifted* clock will. Run `timedatectl status` (Linux) or `sntp pool.ntp.org` (macOS) to confirm.
- You're computing `expires_at` from `Date.now()` in milliseconds but the wire format wants RFC 3339 — use `.toISOString()`, not the raw millisecond integer.
- You're sending `expires_at` as a string like `"2026-05-17"` (date-only). The Hub parses RFC 3339 with time component; date-only fails.

## Why the Hub enforces this at all

A mandate without expiry is an unbounded autonomy grant. The principal (the person or system that issued the mandate) signed an intent declaration that says, in effect, "spend up to budget X on capability Y in the next N seconds." After N seconds, that intent is stale — circumstances may have changed, the principal may have revoked, the budget may now be wrong. The Hub honors the expiry strictly because slop here means an expired mandate could authorize a call after the principal's intent has changed.

## When it fires (precedence)

1. `AUTH_REQUIRED` — no credentials.
2. `INVALID_API_KEY` — credentials don't match.
3. **`MANDATE_EXPIRED`** (this page) — credentials OK, mandate's `expires_at` past.
4. `PROVENANCE_MISMATCH` — credentials OK, mandate fresh, but provenance hash didn't verify.

## Related errors

- `INVALID_API_KEY` — credentials are wrong (no mandate inspected).
- `PROVENANCE_MISMATCH` — mandate is fresh but its provenance_hash didn't verify.
- `INSUFFICIENT_BUDGET` — mandate is fresh but its `budget` cap is below the action price.
