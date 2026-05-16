# `CAPABILITY_DEPRECATED`

> Public URL: https://jecp.dev/errors/capability_deprecated
> Spec source: `spec/03-errors.md` §3 + `spec/04-manifest.md` (deprecation block)
> v1.0.2 K2.3
> Last updated: 2026-05-16

## What it means

The capability you invoked is past its sunset date and the Provider has chosen to stop serving it. The Hub blocks new invocations to prevent silent data drift — older clients that have not migrated should fail loudly here, not get unexpected behavior or stale responses.

HTTP status: `410 Gone`.

This is distinct from `CAPABILITY_NOT_FOUND` (404, the capability id never existed) and from a transient `PROVIDER_UNREACHABLE` (502, Provider is down but capability is still active).

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "CAPABILITY_DEPRECATED",
    "message": "capability 'oldns/translate' was sunset on 2026-01-15",
    "details": {
      "capability": "oldns/translate",
      "sunset_at": "2026-01-15T00:00:00Z",
      "successor": "newns/translate",
      "documentation_url": "https://jecp.dev/errors/capability_deprecated"
    }
  }
}
```

The `successor` field is set when the Provider declared a replacement in their `deprecation` block. It MAY be absent when the capability has been retired entirely.

## Fix in 30s

### When `successor` is set

1. Stop calling the old capability id.
2. Update your client code to call `details.successor` instead.
3. Re-issue the invocation. The successor MAY have a different `input_schema` — check `jecp catalog <successor>` before deploying.

### When `successor` is absent

The capability has been retired without replacement. Browse `/catalog` for alternatives, or contact the Provider's `support_email` (visible via `jecp catalog --json <old-namespace>`).

## Sunset signaling before 410

Per spec §1, Hubs MUST attach two response headers during the deprecation window (typically 30–180 days before sunset):

```
Deprecation: true
Sunset: Fri, 15 Jan 2026 00:00:00 GMT
```

If your client reads these proactively you will see the warning well before requests start returning 410. Treat any successful response that carries `Deprecation: true` as a migration alarm — the success itself is on borrowed time.

## Related references

- `spec/04-manifest.md` — manifest deprecation block format.
