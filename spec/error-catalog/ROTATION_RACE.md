# `ROTATION_RACE`

> Public URL: https://jecp.dev/errors/rotation_race
> Spec source: `spec/03-errors.md` §3.9 + `spec/04-manifest.md` §8.6.3
> Last updated: 2026-05-17

## What it means

The caller invoked `POST /v1/agents/me/rotate-key` (or `/v1/providers/me/rotate-key`) and authenticated successfully, but the Agent/Provider record was modified or deleted by a concurrent administrative action mid-transaction. The atomic rotation transaction failed at the row-lock layer; no new key was issued and the existing key is unchanged.

HTTP status: `409 Conflict`.

This code fires only on the rotation self-service endpoints. Regular `POST /v1/invoke` traffic never sees it.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "ROTATION_RACE",
    "message": "Key changed between authentication and rotation. Retry with current key."
  }
}
```

Per spec §3.9, conformant Hubs SHOULD attach a `details.reason` enum (`row_locked` | `provider_disappeared`). The reference Hub emits only the message string; check `error.details` and fall back to message inspection.

## Fix in 30s

### Just retry

This is a transient race. Wait 100-500 ms and re-issue the rotation. If a concurrent operator finished a different rotation, your retry will succeed.

```ts
async function rotateWithRaceRetry(client, opts) {
  for (let i = 0; i < 3; i++) {
    try { return await client.rotateKey(opts); }
    catch (e) {
      if (e.code !== 'ROTATION_RACE' || i === 2) throw e;
      await sleep(200 + i * 200);
    }
  }
}
```

Three attempts is enough — repeated `ROTATION_RACE` across three retries indicates a serious problem (the record may have been deleted, or two operators are actively fighting), not a normal race.

### `provider_disappeared` variant

If the Hub attaches `details.reason = "provider_disappeared"`, the Provider record has been deleted between the time the authenticated request reached the Hub and the time the rotation transaction committed. Retry will fail the same way because the record is gone. Recovery: re-register the Provider from scratch.

This case is rare in practice — Providers are not deleted by the Hub on demand, only by the Provider owner via the delete endpoint or by the Hub operator. If you see `provider_disappeared` unexpectedly, check whether another team member triggered a delete.

### `row_locked` variant

A different rotation transaction held the row lock when yours arrived. Retry after backoff — the contending transaction will release the lock within ms.

## Why this code exists at all

Rotation is an atomic transaction: the Hub authenticates the current key, validates the cap, writes the new key, audits the rotation — all in a single SQL transaction with row-level locking on the Agent/Provider record. If a concurrent transaction modifies the same row mid-flight, the optimistic-lock check at commit time fails and the Hub aborts safely.

Returning `409 ROTATION_RACE` instead of `500 INTERNAL_ERROR` lets the client know this is a transient retry-safe condition, not a server bug. The Hub deliberately exposes the contention rather than retrying silently, because a silent retry could mask a deeper issue (e.g., two systems both believing they own the Agent and rotating each other out).

## When this is NOT `ROTATION_24H_CAP`

| Failure | Code | Retry-safe? |
|---|---|---|
| Hit the 3-rotation/24h limit | `ROTATION_24H_CAP` | Yes, after `next_slot_at` |
| Row-level contention with another transaction | **`ROTATION_RACE`** (this page) | Yes, immediately with backoff |
| Wrong current api_key in the request | `INVALID_API_KEY` | No, until you supply the right key |
| Provider/Agent record deleted | `ROTATION_RACE` with `details.reason = "provider_disappeared"` | No, you must re-register |

## Related errors

- `ROTATION_24H_CAP` — different §3.9 cause: rate limit on rotations.
- `INVALID_API_KEY` — current key didn't authenticate.
- `INTERNAL_ERROR` — unrelated Hub-side bug; not retry-safe in the same way.
