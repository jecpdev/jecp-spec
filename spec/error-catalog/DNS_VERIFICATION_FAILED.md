# `DNS_VERIFICATION_FAILED`

> Public URL: https://jecp.dev/errors/dns_verification_failed
> Spec source: `spec/03-errors.md` §3.9 + `spec/04-manifest.md` §8.6.2
> Last updated: 2026-05-17

## What it means

A registered Provider called `POST /v1/providers/verify-dns` but the Hub could not find a matching `_jecp.<domain>` TXT record carrying `jecp-verify=<token>`. Either the record is absent, the token mismatches, or DNS propagation has not completed.

HTTP status: `422 Unprocessable Entity`.

This code fires only on Stage 3 (Provider self-service) endpoints. Agents calling `POST /v1/invoke` never see it. Hubs that don't yet implement Provider acceptance never emit it.

Note: the reference Hub at `jecp/src/routes/providers.rs::verify_dns` does not currently emit this code as an error envelope — it returns `200 OK` with `{ "verified": false, "status": "<current>", "message": "..." }` in the body to allow polling without paying error-handling overhead. The catalog page documents the spec-canonical behavior; Hub patches to match the spec are tracked for v1.0.3.

## Response envelope (spec-canonical)

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "DNS_VERIFICATION_FAILED",
    "message": "DNS TXT record not found at _jecp.acme.example",
    "details": {
      "domain": "acme.example",
      "expected_token_prefix": "a1b2c3d4",
      "reason": "txt_record_missing",
      "documentation_url": "https://jecp.dev/errors/dns_verification_failed"
    }
  }
}
```

## Subcause registry — `error.details.reason`

| `reason` | Meaning | Provider fix |
|---|---|---|
| `txt_record_missing` | No `_jecp.<domain>` TXT record exists. | Publish the TXT record at the registrar / DNS provider. |
| `txt_record_mismatch` | TXT record exists but the value doesn't match `jecp-verify=<your-token>`. | Re-check the token issued at register; rewrite the TXT record. |
| `nxdomain` | DNS resolver returned NXDOMAIN — the domain itself isn't resolvable. | Confirm the domain has an authoritative DNS provider. |

### `txt_record_missing`

The DNS resolver returned a successful answer but no TXT record at `_jecp.<domain>` matches. Common causes:

- The record was added to the wrong zone. The TXT must live at the *exact* domain extracted from `provider.endpoint_url` — if your `endpoint_url` is `https://api.acme.example/v1`, the TXT must live at `_jecp.api.acme.example`, not `_jecp.acme.example`.
- The record was added at a wildcard (`_jecp.*`) but resolvers don't expand wildcards uniformly. Use an explicit `_jecp.<host>` record.
- TTL on the negative cache is high (typically 5 min) — your registrar shows the record live but the resolver still serves the old "not found" answer. Wait one TTL window.

### `txt_record_mismatch`

The TXT record exists but the value doesn't contain `jecp-verify=<your-token>`. Common causes:

- You used the dns_verification_token from a different Provider registration.
- The token was truncated by your registrar's web UI (some UIs limit TXT value length silently).
- You added the literal string `<your-token>` because you copy-pasted the template without substitution.

### `nxdomain`

DNS resolution of the domain itself failed — the domain has no authoritative answer at all. This is upstream of the JECP layer entirely.

- Confirm the domain has nameservers configured.
- `dig +short NS <domain>` should return at least one nameserver.
- If the domain was registered moments ago, allow up to 24h for global propagation.

## Fix in 30s

1. Find your `dns_verification_token` (returned in the register response, also retrievable via `GET /v1/providers/me`).
2. Add the TXT record at your DNS provider:

   ```
   Type:   TXT
   Name:   _jecp.<the-domain-from-your-endpoint_url>
   Value:  jecp-verify=<your-token>
   TTL:    300
   ```

3. Wait ~60s for propagation (longer for traditional registrars).
4. Re-call `POST /v1/providers/verify-dns`. The Hub re-resolves and marks `status: verified` on success.

### Verify from your shell first

Before retrying the Hub, confirm the record is live:

```bash
dig +short TXT _jecp.acme.example
# expected output: "jecp-verify=a1b2c3d4..."
```

If `dig` returns nothing, the record isn't propagated yet. Retrying the Hub will fail the same way.

## Why DNS verification at all

Provider namespace is a public identifier — any Provider can claim a namespace at register time, but they cannot prove ownership of the domain backing their `endpoint_url` without a side-channel signal. DNS TXT verification is the standard side-channel (used by Google Search Console, AWS ACM, Let's Encrypt, etc.) because only the domain owner can publish TXT records under that domain.

Without this gate, a malicious Provider could register `namespace=acme` with `endpoint_url=https://malicious.example` and intercept traffic intended for the real Acme. DNS verification closes that hole.

## Related errors

- `ENDPOINT_NOT_SET` — Provider was registered without a valid `endpoint_url`; verification can't run.
- `URL_BLOCKED_SSRF` — Provider's `endpoint_url` was rejected by the SSRF deny-list at register time.
- `ROTATION_24H_CAP` — different §3.9 code (rotation rate-limit, not DNS verification).
