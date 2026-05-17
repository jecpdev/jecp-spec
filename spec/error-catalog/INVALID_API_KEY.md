# `INVALID_API_KEY`

> Public URL: https://jecp.dev/errors/invalid_api_key
> Spec source: `spec/03-errors.md` §3.1 + `spec/02-authentication.md` §4
> Last updated: 2026-05-17

## What it means

The Hub saw `(agent_id, api_key)` credentials on the request, but the api_key does not match the stored credential for that agent_id. The Hub uses bcrypt-verified storage — a leaked api_key tip is not enough; the verifier must hash to the stored bcrypt value.

HTTP status: `401 Unauthorized`.

This is distinct from `AUTH_REQUIRED` (no credentials supplied) and from `MANDATE_EXPIRED` (credentials OK but the mandate's `expires_at` has passed).

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "INVALID_API_KEY",
    "message": "Invalid API key"
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

The Hub deliberately returns an opaque message — no hint about *which* field is wrong (agent_id or api_key) and no echo of the supplied values. This is to avoid building an enumeration oracle for credential-stuffing attacks.

## Fix in 30s

### If you typo'd the key

Re-check the values in your secret store. Common gotchas:

- The api_key contains URL-unsafe characters that got mangled by a clipboard tool or env file parser.
- The agent_id is correct but you're using an api_key from a different Agent.
- You rotated the key but the new key never made it into production (the previous key may still be valid during the rotation grace window; after the window it goes invalid).
- You're hitting the wrong Hub — a staging api_key against the production Hub fails with this same code.

### If the key is genuinely lost

JECP api_keys are shown exactly once at registration. If you don't have the key any more, re-register:

```bash
jecp register --name "My Agent" --type automation
# print agent_id and api_key — store both immediately
```

The new Agent gets a fresh free-tier quota; the old Agent_id is abandoned (no admin endpoint deletes it — it just decays from cache).

### If you rotated

After `POST /v1/agents/me/rotate-key`, the *previous* api_key remains valid for the grace window (default 3600 s) unless you set `revoke_old: true`. If you saw a successful rotation but production immediately starts 401-ing, you probably:

- Used `revoke_old: true` and your old fleet hasn't picked up the new key yet — roll forward.
- Are mixing the rotated agent_id with the old key on a process that hasn't been restarted — restart the process.

## Why the Hub returns this instead of `AUTH_REQUIRED`

`AUTH_REQUIRED` means "I saw zero credentials." `INVALID_API_KEY` means "I saw credentials but they don't match." The split lets SDKs distinguish "developer forgot to wire env vars" (the AUTH_REQUIRED case) from "the credentials are wrong" (this case) — important for surfacing the right next step.

## Why the message is opaque

The Hub does NOT tell you which field is wrong. If it did, an attacker who has a list of agent_ids could send fake api_keys and use the response to confirm "this agent_id exists" — a known account-enumeration vector. The opaque "Invalid API key" message defeats that probe.

This is the same reason GitHub, AWS, and Stripe all return a single "auth failed" message regardless of which field was wrong.

## Related errors

- `AUTH_REQUIRED` — you sent no credentials at all.
- `MANDATE_EXPIRED` — credentials OK, but the mandate window closed.
- `PROVENANCE_MISMATCH` — credentials OK, but the provenance hash in the mandate didn't verify.
- `INSUFFICIENT_TRUST` — Agent identified but its trust tier is below the action's required minimum.
