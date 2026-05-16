# `DUPLICATE_REQUEST`

> Public URL: https://jecp.dev/errors/duplicate_request
> Spec source: `spec/01-protocol.md` (idempotency) + `spec/03-errors.md` §3
> v1.0.2 K2.2
> Last updated: 2026-05-16

## What it means

The `id` field on this request matched a recently completed request that had a *different* body. JECP idempotency is body-bound: the same `id` with the same body returns the cached response, but the same `id` with a different body is a programming error and gets rejected.

HTTP status: `409 Conflict`.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "DUPLICATE_REQUEST",
    "message": "request id 'xyz' was used for a different body within the idempotency window",
    "details": {
      "documentation_url": "https://jecp.dev/errors/duplicate_request"
    }
  }
}
```

## Fix in 30s

Generate a fresh `id` per logical request. The SDK does this automatically — if you set `id` manually, the standard pattern is a UUIDv4 per call:

```ts
import { randomUUID } from 'node:crypto';

const envelope = {
  jecp: '1.0',
  id: randomUUID(),
  capability: '...',
  action: '...',
  input: { /* ... */ },
};
```

## Why the Hub rejects instead of silently overwriting

Silently re-running with the new body would break the at-most-once guarantee that the cached response gives clients: a retry-loop that mutates the body would charge twice (once for the original, once for the changed). Rejecting forces the caller's code path to be explicit about whether it's retrying the same request or starting a new one.

## Idempotency window

The Hub caches `(id, body_hash) → response` for 24h after the first observation. Inside that window:

| Scenario | Result |
|---|---|
| Same `id` + same body | Replay the cached response (200, full body, including `charged`). |
| Same `id` + different body | `DUPLICATE_REQUEST` (this page). |
| Fresh `id` | Process normally. |

Outside the window the `id` may be reused. In practice every modern UUID generator avoids collisions over any 24h window so callers should not need to think about this.

## Related references

- `spec/01-protocol.md` — idempotency rules.
