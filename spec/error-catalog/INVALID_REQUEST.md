# `INVALID_REQUEST`

> Public URL: https://jecp.dev/errors/invalid_request
> Spec source: `spec/03-errors.md` §3.2
> Last updated: 2026-05-17

## What it means

The Hub could not parse the request body as a JECP envelope. The body is either not valid JSON, missing a required top-level field (`jecp`, `id`, `capability`, `action`), or structurally malformed at the wire level before any semantic validation runs.

HTTP status: `400 Bad Request`.

This is the earliest validation gate. The Hub did not authenticate the caller, did not look up the capability, did not check balance — your request did not make it past JSON parsing or top-level structural inspection.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "INVALID_REQUEST",
    "message": "Invalid request: body is not valid JSON: expected value at line 1 column 1"
  }
}
```

The `error.message` carries a one-line diagnostic. The Hub does not echo a structured `details` object for this code — the failure happens before structured error decoration runs.

## Fix in 30s

### Valid envelope

```bash
curl -X POST https://jecp.dev/v1/invoke \
  -H "Content-Type: application/json" \
  -H "X-Agent-ID: $JECP_AGENT_ID" \
  -H "X-API-Key: $JECP_AGENT_KEY" \
  --data-raw '{
    "jecp":       "1.0",
    "id":         "req_'"$(uuidgen)"'",
    "capability": "jobdonebot/content-factory",
    "action":     "translate",
    "input":      {"text":"Hello","target_lang":"ja"}
  }'
```

### Common gotchas

- Trailing comma in JSON (`{"a": 1,}`) — strict JSON forbids this.
- Single-quoted strings (`{'a': 1}`) — JSON requires double quotes.
- Unquoted keys (`{a: 1}`) — JSON requires quoted strings.
- Forgetting `Content-Type: application/json` — produces `UNSUPPORTED_MEDIA_TYPE` (415) before this code fires.
- Empty body or `null` — Hub responds with `INVALID_REQUEST` since the top-level envelope structure cannot be derived.

If you're using `@jecpdev/sdk`, the envelope is constructed for you; this error from SDK code is a bug — file an issue.

## When it fires (precedence)

1. `UNSUPPORTED_MEDIA_TYPE` (415) — Content-Type wasn't `application/json`. Checked first.
2. `INVALID_REQUEST` (400) — body parses as JSON but fails top-level structural sanity (missing `jecp`, malformed `id`).
3. `VALIDATION_FAILED` (400) — envelope structure is fine but specific fields are wrong (e.g. `id` violates regex).
4. `INPUT_SCHEMA_VIOLATION` (400) — envelope is fine but `input` failed the action's published JSON schema.

The four codes are distinct so SDKs can surface clearer diagnostics: "fix your transport" vs. "fix your envelope" vs. "fix your input payload."

## Why the Hub returns this instead of `VALIDATION_FAILED`

`INVALID_REQUEST` covers failures that happen before the Hub can build a typed envelope — JSON parse errors, missing top-level fields, fundamentally broken structure. `VALIDATION_FAILED` covers per-field schema violations *after* the envelope parsed. Both are HTTP 400; the code split tells you whether to inspect transport / framing or specific field values.

## Related errors

- `UNSUPPORTED_MEDIA_TYPE` — body wasn't JSON.
- `VALIDATION_FAILED` — envelope parsed but a field violated its schema.
- `INPUT_SCHEMA_VIOLATION` — envelope was fine; `input` failed the action schema.
- `UNSUPPORTED_VERSION` — `jecp` field had a wrong value.
