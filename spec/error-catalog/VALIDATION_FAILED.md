# `VALIDATION_FAILED`

> Public URL: https://jecp.dev/errors/validation_failed
> Spec source: `spec/03-errors.md` §3.2
> Last updated: 2026-05-17

## What it means

The Hub parsed your request body as a JECP envelope, but a specific field inside it failed validation. Typical causes: the `id` doesn't match the required regex, `mandate.expires_at` is in the wrong timestamp format, or some other envelope-level constraint declared in `spec/01-protocol.md` was violated.

HTTP status: `400 Bad Request`.

This is distinct from `INPUT_SCHEMA_VIOLATION` (the action's `input` payload, validated against the published `input_schema`). `VALIDATION_FAILED` is envelope-level; `INPUT_SCHEMA_VIOLATION` is action-level.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Input validation failed: id must match ^[a-zA-Z0-9_\\-]{1,128}$"
  }
}
```

The Hub's reference implementation emits `error.message` as a single human-readable line. Per spec §3.2, conformant Hubs MAY also emit a structured `details.errors[]` array of `{path, reason}` entries; check `error.details` and fall back to parsing `error.message` if it's absent.

## Fix in 30s

The most common causes, in rough order of frequency:

| Field | Constraint | Recovery |
|---|---|---|
| `id` | matches `^[a-zA-Z0-9_\-]{1,128}$` | Use a UUIDv4 or hex string |
| `jecp` | exact value `"1.0"` | Sends `UNSUPPORTED_VERSION` instead if mismatched |
| `mandate.expires_at` | RFC 3339 timestamp | Use `new Date().toISOString()` in JS |
| `mandate.budget` | non-negative finite number | Pass a number, not a string |
| `capability` | non-empty string | Check for typos / accidental null |
| `action` | non-empty string | Check for typos |

```ts
import { randomUUID } from 'node:crypto';

const envelope = {
  jecp: '1.0',
  id: randomUUID(),                       // valid id
  capability: 'jobdonebot/content-factory',
  action: 'translate',
  input: { text: 'Hello', target_lang: 'ja' },
  mandate: {
    budget: 1.0,                          // number, not "1.0"
    expires_at: new Date(Date.now() + 60_000).toISOString(),
  },
};
```

If you're using `@jecpdev/sdk`, most of these fields are validated client-side before the request goes out — a `VALIDATION_FAILED` response from SDK code suggests you bypassed the builder. Use `client.invoke({...})`, not raw `fetch`.

## When it fires (precedence)

1. `UNSUPPORTED_MEDIA_TYPE` (415) — Content-Type wasn't `application/json`.
2. `INVALID_REQUEST` (400) — body didn't parse, or top-level envelope is structurally broken.
3. **`VALIDATION_FAILED` (400)** — envelope parsed but a specific field violated its constraint.
4. `INPUT_SCHEMA_VIOLATION` (400) — envelope is fine; `input` failed the action schema.

## Why the Hub splits this from `INPUT_SCHEMA_VIOLATION`

Envelope-level violations indicate a transport / framing bug in the Agent SDK; action-level violations indicate the Agent's *application logic* sent wrong values. The split lets SDK authors and Agent developers debug in the right layer without spelunking through schema paths to figure out which side of the wire boundary failed.

## Related errors

- `INVALID_REQUEST` — earlier gate; body didn't parse at all.
- `INPUT_SCHEMA_VIOLATION` — later gate; `input` failed the published action schema.
- `UNSUPPORTED_VERSION` — `jecp` field had a wrong value (handled separately for clarity).
