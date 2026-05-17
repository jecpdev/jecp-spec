# `UNKNOWN_CAPABILITY`

> Public URL: https://jecp.dev/errors/unknown_capability
> Spec source: `spec/03-errors.md` §3.3
> Last updated: 2026-05-17

## What it means

The Hub looked up the `capability` field in the request envelope and found no matching entry in its registry. Either the capability id was misspelled, the Provider isn't registered with this Hub, or the capability is namespace-qualified to a third-party Provider that this Hub doesn't broker.

HTTP status: `400 Bad Request` (reference Hub) — note: spec §3.3 maps this code to HTTP 404. The reference implementation returns 400 because the field value is the failure source; clients should branch on `code` rather than HTTP status for portable behavior.

This is distinct from `UNKNOWN_ACTION` (capability exists, the named action does not) and from `PROVIDER_NOT_FOUND` (namespace exists but its Provider record is gone).

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "UNKNOWN_CAPABILITY",
    "message": "Unknown capability: jobdonebot/transalte"
  }
}
```

The `error.message` echoes the unrecognized capability id verbatim — useful for spotting typos.

## Fix in 30s

### Inspect the catalog

```bash
jecp catalog
# or for JSON:
jecp catalog --json | jq '.capabilities[].full_id'
```

The catalog page at `https://jecp.dev/catalog` renders the same list with search. The `full_id` is the canonical form (`<namespace>/<capability>`).

### Common gotchas

- Typo in the capability segment (`transalte` → `translate`).
- Missing namespace prefix: send `jobdonebot/content-factory`, not `content-factory`.
- Wrong namespace: `jobdonebot/translate` exists; `acme/translate` may not.
- Trailing whitespace or invisible Unicode in the field — strip before sending.
- Hub is on the wrong stage: capabilities published by third-party Providers (Stage 3+) only appear once both DNS-verified and accepting traffic.

### When the capability *should* exist but doesn't

If you're operating a Provider and your capability isn't appearing:

1. Check your manifest publish ran cleanly — `jecp manifest list` (Provider auth required).
2. Confirm your Provider record is DNS-verified (`status: verified`).
3. Confirm the manifest is in `state: active` — published-but-not-yet-promoted manifests don't serve traffic.

## When it fires vs. `UNKNOWN_ACTION`

| Field state | Code |
|---|---|
| `capability` doesn't exist on this Hub | **`UNKNOWN_CAPABILITY`** (this page) |
| `capability` exists, `action` does not | `UNKNOWN_ACTION` |
| `capability` is namespace-qualified to a Provider with no record | `PROVIDER_NOT_FOUND` |

The Hub checks capability first, then action — so a request that misspells both will surface as `UNKNOWN_CAPABILITY` until the capability id is fixed.

## Related errors

- `UNKNOWN_ACTION` — capability resolved, action did not.
- `PROVIDER_NOT_FOUND` — namespace has no registered Provider.
- `CAPABILITY_DEPRECATED` — capability existed but is past its sunset date.
