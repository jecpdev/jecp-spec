# `UNSUPPORTED_VERSION`

> Public URL: https://jecp.dev/errors/unsupported_version
> Spec source: `spec/03-errors.md` §3.2
> Last updated: 2026-05-17

## What it means

The `jecp` field on your request envelope is not a version this Hub supports. The reference Hub speaks v1.0 only — clients sending `"0.9"`, `"2.0"`, or any non-`"1.0"` value are rejected at the wire-format gate.

HTTP status: `400 Bad Request`.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "UNSUPPORTED_VERSION",
    "message": "Unsupported protocol version: 0.9"
  }
}
```

The `error.message` echoes the version string you sent. The reference Hub does not currently emit a structured `details.supported` array (the spec recommends `{ "supported": ["1.0"], "received": "<value>" }`); a future Hub patch will add it for spec compliance. For now, treat the supported set as v1.0 only and check the Hub's release notes when in doubt.

## Fix in 30s

Send `"1.0"`:

```json
{
  "jecp": "1.0",
  "id":   "req_abc123",
  "capability": "jobdonebot/content-factory",
  "action":     "translate",
  "input":      { "text": "Hello", "target_lang": "ja" }
}
```

The SDK hard-codes the supported version, so this error from SDK code is a bug (either the Hub is ahead of the SDK or the SDK is corrupted). Pin the SDK version against the Hub version explicitly.

### When this fires unexpectedly

- You're targeting a Hub that's running an older or newer release than the SDK was tested against.
- The `jecp` field got serialized as a number (`1.0` → `1`) by some JSON serializer that strips trailing zeros. Cast to string explicitly.
- A proxy or transformation layer is rewriting the body — check the request payload right before it leaves your process.

## Why the Hub enforces strict version match

The `jecp` field is the version handshake. Backwards-compatible reads of unknown-future versions are explicitly disallowed because a Hub that "tolerates" v2.0 by treating it as v1.0 would corrupt the meaning of any field that v2.0 adds. Strict matching here is the same idea as HTTP/1.1 vs HTTP/2 — the parser is version-keyed at the protocol layer, not the data layer.

This is enforced even on minor versions: v1.0 and v1.1 are wire-compatible (additions only), but each Hub release advertises a single canonical version string. Future Hubs may accept both v1.0 and v1.1 envelopes; for now, send v1.0.

## When it fires vs. `INVALID_REQUEST`

`INVALID_REQUEST` fires if `jecp` is absent or the body doesn't parse at all. `UNSUPPORTED_VERSION` fires if `jecp` is present and parseable but is the wrong value. The split lets SDKs surface "send a version" vs "send the right version."

## Related errors

- `INVALID_REQUEST` — body didn't parse, or `jecp` field is missing entirely.
- `VALIDATION_FAILED` — `jecp` is `"1.0"` but some other field violated its constraint.
- `CAPABILITY_DEPRECATED` — wire version OK, but the capability's manifest is past sunset.
