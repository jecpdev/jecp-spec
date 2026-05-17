# `AUTH_REQUIRED`

> Public URL: https://jecp.dev/errors/auth_required
> Spec source: `spec/03-errors.md` §3.1 + `spec/02-authentication.md` §3
> Last updated: 2026-05-17

## What it means

The Hub did not see any Agent credentials on this request. Both header-form (`X-Agent-ID` + `X-API-Key`) and mandate-form (`mandate.agent_id` + `mandate.api_key`) credentials were absent. The Hub cannot identify *who* is calling and rejects before any other work.

HTTP status: `401 Unauthorized`.

This is distinct from `INVALID_API_KEY` (credentials were provided but didn't match a registered Agent) and from `INSUFFICIENT_TRUST` (the Agent is known, but their tier is too low).

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "AUTH_REQUIRED",
    "message": "Authentication required"
  },
  "next_action": {
    "type": "register",
    "ui": "https://jecp.dev/register",
    "api": "https://jecp.dev/api/agents/register",
    "method": "POST",
    "body_example": { "name": "My Agent", "agent_type": "automation" },
    "description": "Register an agent to receive agent_id and api_key (100 free calls)"
  }
}
```

The Hub attaches a `next_action.type = "register"` block so an Agent can auto-recover by registering and retrying. SDKs SHOULD surface this block to the developer instead of just printing `error.message`.

## Fix in 30s

### If you've already registered

Send the credentials. Header form is the canonical path:

```bash
curl -X POST https://jecp.dev/v1/invoke \
  -H "Content-Type: application/json" \
  -H "X-Agent-ID: $JECP_AGENT_ID" \
  -H "X-API-Key: $JECP_AGENT_KEY" \
  --data-raw '{...}'
```

In SDK code:

```ts
import { JecpClient } from '@jecpdev/sdk';

const client = new JecpClient({
  hubUrl:  process.env.JECP_HUB_URL,
  agentId: process.env.JECP_AGENT_ID,
  apiKey:  process.env.JECP_AGENT_KEY,
});
```

### If you haven't registered

Follow `next_action.api`:

```bash
jecp register --name "My Agent" --type automation
# prints agent_id and api_key once — store both immediately
```

The Hub returns 100 free calls per new Agent for evaluation. After that, top up the wallet (`jecp topup 5`).

## Mandate form (alternative)

If your architecture passes credentials in the request body instead of headers (e.g., to wrap a JECP envelope in another transport that strips headers), put them in the mandate:

```json
{
  "jecp": "1.0",
  "id": "req_...",
  "mandate": { "agent_id": "agt_...", "api_key": "jdb_ak_..." },
  "capability": "jobdonebot/content-factory",
  "action": "translate",
  "input": { "text": "Hello", "target_lang": "ja" }
}
```

Either form satisfies the Hub. Mixing — header agent_id with mandate api_key, etc. — produces `AUTH_REQUIRED` because the Hub requires both fields to come from the same source.

## When it fires (precedence)

`AUTH_REQUIRED` is checked before billing, before capability lookup, before rate limiting. Per spec §3.1, the gate order is:

1. Content-Type → `UNSUPPORTED_MEDIA_TYPE`
2. Body parse → `INVALID_REQUEST`
3. Envelope field validation → `VALIDATION_FAILED`
4. **Auth presence → `AUTH_REQUIRED` (this page)**
5. Auth correctness → `INVALID_API_KEY`
6. Capability lookup → `UNKNOWN_CAPABILITY` / `UNKNOWN_ACTION`
7. Rate limit → `RATE_LIMITED`
8. Trust → `INSUFFICIENT_TRUST`
9. Funds → `INSUFFICIENT_BALANCE` / `INSUFFICIENT_BUDGET` / `PAYMENT_REQUIRED`

Auth is checked before rate limit so unauthenticated traffic cannot be used to enumerate the rate-limit state of valid Agents.

## Related errors

- `INVALID_API_KEY` — you sent credentials, but they didn't match a registered Agent.
- `MANDATE_EXPIRED` — credentials were OK, but the mandate window closed.
- `INSUFFICIENT_TRUST` — Agent is known but its tier is below the action's minimum.
