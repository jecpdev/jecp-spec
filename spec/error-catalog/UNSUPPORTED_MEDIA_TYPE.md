# `UNSUPPORTED_MEDIA_TYPE`

> Public URL: https://jecp.dev/errors/unsupported_media_type
> Spec source: `spec/03-errors.md` §3
> v1.0.2 K2.1
> Last updated: 2026-05-16

## What it means

The Hub will only parse request bodies with `Content-Type: application/json`. You sent something else — most commonly the header was missing, was `application/x-www-form-urlencoded` (a `curl -d` default), or was the wrong JSON variant (e.g. `application/jecp+json`).

HTTP status: `415 Unsupported Media Type`.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "UNSUPPORTED_MEDIA_TYPE",
    "message": "Content-Type must be application/json",
    "details": {
      "received": "application/x-www-form-urlencoded",
      "expected": "application/json",
      "documentation_url": "https://jecp.dev/errors/unsupported_media_type"
    }
  }
}
```

## Fix in 30s

### curl

```bash
curl -X POST https://jecp.dev/v1/invoke \
  -H "Content-Type: application/json" \
  -H "X-Agent-ID: $JECP_AGENT_ID" \
  -H "X-API-Key: $JECP_AGENT_KEY" \
  --data-raw '{"jecp":"1.0","id":"...","capability":"..."}'
```

### Node fetch

```ts
await fetch('https://jecp.dev/v1/invoke', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', /* auth */ },
  body: JSON.stringify(envelope),
});
```

If you're using `@jecpdev/sdk`, this is set automatically. If you see this error from SDK code, file a bug.

## Why the Hub enforces this

The strict check is a defense against ambiguous parsing — older HTTP middlewares would happily attempt JSON parsing on form-encoded bodies, leading to silent data corruption. Per spec §3 (v1.0.2 K2.1), conformant Hubs MUST return 415 for non-JSON content types so the failure is loud and recoverable.

## Related errors

- `INPUT_SCHEMA_VIOLATION` — body parsed but failed schema validation.
