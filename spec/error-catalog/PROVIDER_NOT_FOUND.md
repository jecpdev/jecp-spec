# `PROVIDER_NOT_FOUND`

> Public URL: https://jecp.dev/errors/provider_not_found
> Spec source: `spec/03-errors.md` §3.3
> Last updated: 2026-05-17

## What it means

The Hub looked up the namespace portion of a fully-qualified `<namespace>/<capability>` reference and found no registered Provider. The namespace was never claimed, the Provider was deregistered, or the request is targeting the wrong Hub.

HTTP status: `404 Not Found`.

This code is specific to Stage 3 deployments — Hubs that broker third-party Providers via the Provider Marketplace. Stage 1 / Stage 2 Hubs that only serve first-party capabilities never emit it.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "PROVIDER_NOT_FOUND",
    "message": "Provider not found: acme"
  }
}
```

The `error.message` echoes the unrecognized namespace verbatim. The Hub does NOT enumerate similar namespaces — that would enable Provider-name fishing.

## Fix in 30s

### Inspect the Provider catalog

```bash
jecp catalog --json | jq '.capabilities[].full_id' | cut -d'/' -f1 | sort -u
# lists every namespace this Hub has Providers for
```

The catalog page at `https://jecp.dev/catalog` filters by namespace too. If the namespace you want isn't there, the Provider either:

- Hasn't registered yet
- Registered but DNS verification is still pending (`status: pending_dns`)
- Was deregistered (operator action or self-service deletion)

### If you're the Provider

If your namespace should appear but doesn't:

1. `jecp provider status` — confirms your Provider record exists and shows current `status`.
2. If `status: pending_dns`, follow the DNS-verification flow in `spec/04-manifest.md §8.2`.
3. If `status: verified` but no capabilities appear, you haven't published a manifest yet. Use `jecp manifest publish`.

### Common gotchas

- Typo in the namespace (`acme` vs `acmeai`).
- Using the *display name* (`"Acme AI Inc."`) instead of the registered namespace id (`acme`). Namespaces are lowercase, hyphenated, registered once at `POST /v1/providers/register`.
- Targeting the wrong Hub — a namespace registered on Hub A is not visible on Hub B unless both Hubs share a registry (federation is not part of v1.0).

## Why this is distinct from `UNKNOWN_CAPABILITY`

`UNKNOWN_CAPABILITY` means "I parsed `<namespace>/<capability>` and the capability segment is not in my registry — but the namespace might be valid." `PROVIDER_NOT_FOUND` means "the namespace segment itself is unrecognized." Same HTTP status (404) but the recovery is different: capability typo vs. wrong-Hub or unregistered-Provider.

The Hub returns whichever fits the failure mode. A request that gets the namespace right but the capability wrong gets `UNKNOWN_CAPABILITY`; a request that gets the namespace wrong gets `PROVIDER_NOT_FOUND` and never inspects the capability segment.

## Related errors

- `UNKNOWN_CAPABILITY` — namespace OK, capability segment unknown.
- `AGENT_NOT_FOUND` — same shape but for Agents instead of Providers.
- `CAPABILITY_DEPRECATED` — Provider and capability both known, but past sunset.
