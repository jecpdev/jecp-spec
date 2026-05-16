# `INPUT_SCHEMA_VIOLATION`

> Public URL: https://jecp.dev/errors/input_schema_violation
> Spec source: `spec/03-errors.md` §3.2 + `spec/04-manifest.md` (input_schema)
> v1.0.2 K2.5
> Last updated: 2026-05-16

## What it means

The Hub parsed your request body as valid JSON, but the `input` field failed the capability's published `input_schema`. The Hub validates against the schema in the Provider's manifest (JSON Schema 2020-12 subset, per spec §4) before forwarding to the Provider — so the Provider never sees malformed input, and you get a precise error pointing at the failed field.

HTTP status: `400 Bad Request`.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "INPUT_SCHEMA_VIOLATION",
    "message": "input failed schema validation (2 errors)",
    "details": {
      "errors": [
        {
          "instance_path": "/text",
          "schema_path": "/properties/text/maxLength",
          "reason": "string is 6000 chars, max is 5000"
        },
        {
          "instance_path": "/target_lang",
          "schema_path": "/properties/target_lang/pattern",
          "reason": "value 'EN-US' does not match pattern ^[a-z]{2}$"
        }
      ],
      "documentation_url": "https://jecp.dev/errors/input_schema_violation"
    }
  }
}
```

## Fix in 30s

Every entry in `details.errors[]` tells you exactly what failed:

| Field | Meaning |
|---|---|
| `instance_path` | JSON pointer into your *input* (the value the Hub saw). |
| `schema_path` | JSON pointer into the *schema* (which assertion failed). |
| `reason` | Plain-text explanation suitable for surfacing to end users. |

Apply the per-error fix and re-issue the request. Do not trust just the human `message` field — when several assertions fail, the message lists the count but `errors[]` is the authoritative source.

## Where to find the schema

```bash
jecp catalog --json | jq '.capabilities[] | select(.full_id == "namespace/capability")'
# or per-action:
# .actions[] | select(.id == "action_id") | .input_schema
```

The same schema is rendered on the Hub's web catalog at `/catalog/<namespace>/<capability>` with examples from the manifest.

## Why the Hub validates before forwarding

The Provider's HTTPS endpoint stays oblivious to invalid input — fewer crash classes in the Provider runtime, no half-charged invocations from validation 500s mid-call, and a uniform error shape across every Provider on the Hub. Per spec §3.2, the failed-assertion array is mandatory and must use these three exact field names; a Hub that does not return them is non-conformant.

## Conformance

Conformant Hubs at v1.0.2 and later MUST pass `JECP-WIRE-MUST-400-INPUT-SCHEMA` (see `conformance/v1.0/`).

## Related errors

- `UNSUPPORTED_MEDIA_TYPE` — body was not JSON at all.
