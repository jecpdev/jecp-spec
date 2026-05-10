# `URL_BLOCKED_SSRF`

> Public URL: https://jecp.dev/errors/url_blocked_ssrf
> Spec source: `spec/02-authentication.md` §9.7 + §9.7.1
> ADR: `adr/0002-ssrf-defense-architecture.md`
> Last updated: 2026-05-10 (v1.1.0)

## What it means

The Hub refused to dereference an Agent-controlled URL because the URL hits the JECP SSRF deny-list. The URL itself was structurally well-formed — a valid HTTP URL syntactically — but its scheme, host, or resolved IP violated the policy specified in spec §9.7.1.

HTTP status: `422 Unprocessable Entity`.

This is a security policy rejection, not a wire-format validation failure (`400 INPUT_SCHEMA_VIOLATION`) and not a transient transport error (`502 PROVIDER_UNREACHABLE`).

## When it fires

| Field | Where it's accepted | Where the deref happens |
|---|---|---|
| `provider.endpoint_url` | `POST /v1/providers/register`, `POST /v1/providers/verify-dns` | `POST /v1/invoke` (sync forward + SSE forward) |
| `webhook.destination_url` | `POST /v1/subscriptions`, `PATCH /v1/subscriptions/{id}` | webhook delivery loop |
| `mandate.callback_url` | `POST /v1/invoke` body (when async invocations exist) | post-completion HTTP POST to the callback URL |

The Hub MUST run the validation pipeline at BOTH register-time (so legitimate Providers / Agents get fast feedback) AND deref-time (so DNS-rebinding between register and use is caught).

## Subcause registry — `error.details.reason`

The Hub's response carries `error.details.reason` to disambiguate WHY the URL was blocked:

| `reason` | Meaning | Caller fix |
|---|---|---|
| `parse_error` | URL did not parse per RFC 3986 | Send a syntactically valid HTTP URL |
| `scheme` | Scheme was not `https` (or `http` outside test mode) | Use `https://` in production |
| `host_syntax` | Host was percent-encoded or otherwise malformed | Normalize to plain ASCII / IDN-decoded form |
| `resolved_to_deny_cidr` | Hostname resolved to a deny-list CIDR | Use a domain name that resolves to a public IP, OR ask the Hub operator to extend the allowlist |
| `connect_pin_violation` | Resolver returned a different address at `connect()` than at validation (DNS rebinding) | Stop using TTL-1 / split-horizon DNS; ensure A/AAAA records are stable |

## Example response

```json
{
  "jecp":   "1.0",
  "status": "failed",
  "error": {
    "code":    "URL_BLOCKED_SSRF",
    "message": "URL blocked by SSRF policy",
    "details": {
      "field":             "endpoint_url",
      "blocked_url":       "https://internal.dev/api/inbound",
      "reason":            "resolved_to_deny_cidr",
      "documentation_url": "https://jecp.dev/errors/url_blocked_ssrf#resolved_to_deny_cidr"
    }
  }
}
```

For asynchronous deref paths (webhook delivery), the Hub does not return this envelope to the caller — the originating subscription request already returned 200. Instead, the Hub:

1. Marks the outbox row `abandoned_at = NOW(), reason = 'SSRF_DENIED'`
2. Logs the rejection in `ssrf_attempts` (per §9.7.1.4)
3. Stops retrying the delivery

Hub operators can surface the audit trail to subscribers via dashboard or webhook delivery report endpoints.

## Recovery actions

### As an Agent / Provider operator

1. Verify your URL resolves to a public, routable address. Use `dig +short <hostname>` to inspect every A/AAAA record. If any record points at a private/loopback IP, fix DNS.
2. If you legitimately need to reach a private host (e.g., for staging integration), ask the Hub operator to extend the allowlist for your namespace. Extensions are operator-specific and not part of the protocol.
3. Confirm your URL uses `https://`. Most Hubs do not permit `http://` outside test mode.

### As a Hub operator

1. Ensure the validation pipeline runs at BOTH register-time and deref-time. A common bug is enforcing only at register, then dereferencing without re-checking after DNS state changes.
2. Use IP-pinning (`reqwest::Client::resolve(host, addr)` in Rust) to close the rebinding window between check and `connect()`.
3. Disable HTTP redirects on the outbound client (`redirect(Policy::none())`); each redirect target is a new Agent-controlled URL that MUST re-run the pipeline.
4. Persist rejections to an `ssrf_attempts` audit table per §9.7.1.4. Coordinated probing across multiple Agent IDs is the strongest signal of a deliberate attack.

## Related errors

- `INVALID_ENDPOINT` — register-time URL was syntactically invalid (scheme allowlist failure may surface here too on older Hubs).
- `PROVIDER_UNREACHABLE` — Hub reached the URL but the Provider returned an error or timed out (5xx); not a policy block.
- `INVALID_REQUEST` — the request body itself was malformed (not just the URL field).

## Implementation reference

The reference v1.1.0 implementation lives at `jecp/src/protocol/url_guard.rs` in the JobDoneBot Hub source. ADR-0002 records the design tradeoffs.

## Conformance

Conformant Hubs at v1.0.2 and later MUST pass:

- `JECP-OPS-MUST-SSRF-DENY-IP-LITERAL`
- `JECP-OPS-MUST-SSRF-DENY-RESOLVED`
- `JECP-OPS-MUST-SSRF-PIN-RESOLVED-IP`

Run `bash scripts/jecp-conformance.sh https://<hub-url>` against your Hub to verify.
