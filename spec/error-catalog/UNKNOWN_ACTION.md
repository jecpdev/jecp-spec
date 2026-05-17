# `UNKNOWN_ACTION`

> Public URL: https://jecp.dev/errors/unknown_action
> Spec source: `spec/03-errors.md` §3.3
> Last updated: 2026-05-17

## What it means

The Hub resolved the `capability` field to a known capability, but the requested `action` is not declared in that capability's published manifest. Either you typoed the action id, the action was renamed, or you're sending an action that belongs to a different capability.

HTTP status: `400 Bad Request` (reference Hub) — note: spec §3.3 maps this code to HTTP 404. The reference implementation returns 400 because the field value is the failure source. Branch on `code`, not HTTP status, for portable behavior.

This is distinct from `UNKNOWN_CAPABILITY` (the capability itself doesn't exist).

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "UNKNOWN_ACTION",
    "message": "Unknown action: trnaslate"
  }
}
```

The `error.message` echoes the unrecognized action id verbatim. The Hub does not echo the list of valid actions for the capability — that would mean a public enumeration oracle for capabilities behind trust gates. Use the catalog endpoint instead.

## Fix in 30s

### Inspect the capability's actions

```bash
jecp catalog jobdonebot/content-factory
# prints actions list with id, pricing, input_schema URL
```

Or programmatically:

```bash
jecp catalog --json | jq '.capabilities[]
  | select(.full_id == "jobdonebot/content-factory")
  | .actions[].id'
```

The catalog page at `https://jecp.dev/catalog/<namespace>/<capability>` renders the same list with each action's input schema and example payload.

### Common gotchas

- Typo (`trnaslate` → `translate`).
- Using the *display name* instead of the action id — manifests have a `name` field for humans and an `id` field for the wire. Always send the `id`.
- The action existed in an older manifest version but was removed in a later publish — the catalog reflects the currently-active manifest.
- The action exists on a different capability — confirm `capability` and `action` belong together.

### When the action *should* exist but doesn't

If you're operating the Provider and the action isn't in the catalog:

1. Check that the manifest you published actually includes the action under `actions[]`.
2. Confirm the manifest is `state: active`. Manifests in `pending` / `draft` don't serve.
3. Bump the manifest version if you're replacing an old one — the Hub keeps the previously-active manifest live until the new one is promoted.

## When it fires (precedence)

1. `UNKNOWN_CAPABILITY` — capability resolution failed; action lookup never ran.
2. **`UNKNOWN_ACTION`** (this page) — capability resolved, action did not.
3. `INPUT_SCHEMA_VIOLATION` — capability + action resolved; `input` failed the action's published schema.

## Related errors

- `UNKNOWN_CAPABILITY` — capability itself wasn't found.
- `CAPABILITY_DEPRECATED` — the whole capability is past sunset; action lookup never ran.
- `INPUT_SCHEMA_VIOLATION` — action exists but the input you sent failed its schema.
