# `AGENT_NOT_FOUND`

> Public URL: https://jecp.dev/errors/agent_not_found
> Spec source: `spec/03-errors.md` §3.3
> Last updated: 2026-05-17

## What it means

The Hub received an `agent_id` (in headers or in the request body) but found no Agent record with that id. Either the id was mistyped, the Agent was registered on a different Hub, or the record was deleted.

HTTP status: `404 Not Found`.

This is distinct from `AUTH_REQUIRED` (no credentials at all) and from `INVALID_API_KEY` (id exists but the api_key didn't match). `AGENT_NOT_FOUND` fires when the id itself is unrecognized.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "AGENT_NOT_FOUND",
    "message": "Agent not found: agt_5f3a..."
  }
}
```

The `error.message` echoes the unrecognized agent_id verbatim. The Hub does NOT confirm whether the id matches the format of a valid Agent identifier (length, prefix, etc.) — that information would enable enumeration probing.

## Fix in 30s

### If you're sure you registered

Verify the agent_id with `jecp status`:

```bash
jecp status
# prints: agent_id, tier, free_calls_remaining, wallet_balance
```

If `jecp status` succeeds, your local config matches a real Agent — the failing request is using a different agent_id. Diff your env vars / config files.

### If you're not sure

Re-register:

```bash
jecp register --name "My Agent" --type automation
# prints agent_id and api_key once
```

Old Agent records are not deleted by the Hub on demand; they decay over inactivity windows. If your prior agent_id was real, it still exists — but if you don't have its api_key (which is shown only once), it's permanently inaccessible. Re-register is the practical recovery.

### Common gotchas

- You're hitting the wrong Hub (staging api_key against production, or vice versa).
- The agent_id is being read from a stale env var that points to a deleted record.
- The agent_id was URL-encoded somewhere upstream — `agt%5F5f3a...` won't decode back on the Hub side. Send the literal id.

## Why this is a 404 instead of 401

The Hub distinguishes "no such Agent" (404) from "wrong api_key for an existing Agent" (401) because they have different recovery actions. 404 → re-register. 401 → verify credentials. Conflating them would force every recovery to start with "did you register?" — wasted effort when the id was just a typo.

The Hub's 404 message is deliberately terse: no hint at *how close* you got to a real id, no echo of which prefix exists. Agent id enumeration is not a free service.

## Related errors

- `AUTH_REQUIRED` — no credentials supplied at all.
- `INVALID_API_KEY` — agent_id exists but the api_key didn't match.
- `PROVIDER_NOT_FOUND` — same shape but for Providers; emitted on Stage 3 endpoints.
