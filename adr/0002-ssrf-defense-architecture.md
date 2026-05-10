# ADR-0002: SSRF Defense Architecture

> **TL;DR for VPs of Eng**: JECP Hubs dereference Agent-controlled URLs in three places (Provider endpoints, webhook destinations, async callbacks). Without defense, a malicious agent can use the Hub as a proxy into its own internal network — leaking IAM credentials from cloud metadata endpoints (the well-known capital-O Original sin of SSRF). This ADR commits the protocol to a five-layer defense: scheme allowlist, host normalization, DNS resolve, deny-list CIDR check, and connect-time IP pinning. v1.1.0 ships the Rust reference implementation. Conformant Hubs MUST adopt this architecture.

## Status

Accepted (2026-05-10).

## Context

The JECP wire format gives Agents three ways to make the Hub fetch a URL on their behalf:

1. **`provider.endpoint_url`** — a Provider registers a URL via `POST /v1/providers/register`; on every `POST /v1/invoke` for that Provider's namespace, the Hub forwards the request body to `endpoint_url`. The Hub also dereferences this URL during DNS verification (`POST /v1/providers/verify-dns`).
2. **`webhook.destination_url`** — an Agent or Provider registers a URL via `POST /v1/subscriptions`; on each event matching the subscription filter, the Hub `POST`s the event body to that URL.
3. **`mandate.callback_url`** — a future async-invocation field (currently spec-only; not implemented in v1.1.0 reference Hub) where the Hub posts the eventual completion result.

All three are **Agent-controlled inputs** that the Hub uses as TARGETS for outbound HTTP requests. Without defenses, a malicious caller can submit `https://169.254.169.254/latest/meta-data/iam/security-credentials/` (the AWS instance metadata endpoint) or `http://10.0.0.7/internal-admin` and the Hub will dutifully connect to its own VPC's internals. The security literature names this class **Server-Side Request Forgery (SSRF)**; the 2019 Capital One breach (~106M customer records) was an SSRF that exfiltrated EC2 instance credentials via this exact technique.

The threat model is broader than naive IP-literal abuse:

- **Hostname indirection.** An attacker registers `evil.example.com` with a public A record, the validator approves it, and the resolver cache returns the public IP. Then between validation and connect, the attacker flips DNS to return a private IP (TTL=1 enables this in seconds). The Hub connects to private space. This is **DNS rebinding**.
- **IPv4-mapped IPv6.** `::ffff:127.0.0.1` is a literal IPv6 address that resolves at the kernel level to `127.0.0.1`. Naive deny-lists that only check IPv4 CIDRs miss this.
- **Percent-encoded hosts.** `https://%31%32%37.0.0.1/` parses (in some libraries) as `https://127.0.0.1/`. The validator may decode after the deny-list check.
- **Redirect chains.** The Hub validates `https://public.example.com`, follows the 302 to `https://10.0.0.7/internal`, and connects without re-validating. Each redirect target is a NEW Agent-controlled URL.
- **Metadata endpoints.** `169.254.169.254` (AWS / GCP), `metadata.google.internal` (GCP), `[fd00:ec2::254]` (Fly.io equivalent), and `100.100.100.200` (Alibaba) all serve cloud-provider IAM tokens to anyone who can connect from inside the VM.

JECP v1.0 informally noted "validate Agent-controlled URLs" in `02-authentication.md §9.7` but did not specify HOW. The reference Hub shipped v1.0.2 with only a `https://` scheme prefix check on registration (`routes/providers.rs:68`, `routes/subscriptions.rs:115`). This ADR commits the protocol to the full pipeline that v1.1.0 normatives in `02-authentication.md §9.7.1`.

The architectural alternatives are non-trivial because each closes a different attack surface at different cost. We considered four; we adopted (1).

## Decision

JECP-conformant Hubs MUST dereference Agent-controlled URLs through the following five-layer pipeline IN ORDER. Each layer is REQUIRED unless explicitly noted MAY.

1. **Parse + scheme allowlist.** URL MUST parse per RFC 3986. Scheme MUST be `https`. Hubs MAY accept `http` only when the operator explicitly opts in via a boot-time configuration flag (e.g., `JECP_TEST_MODE=true`); the flag MUST NOT be toggleable via the JECP API.
2. **Host normalization.** Percent-encoded host octets MUST be decoded before deny-list comparison. IDN hostnames MUST be punycode-encoded. Trailing-dot variants MUST be canonicalized.
3. **DNS resolve.** The Hub MUST resolve the host via the system resolver. ALL returned addresses (A + AAAA + IPv4-mapped IPv6) MUST be checked.
4. **Deny CIDR check.** Reject if any resolved address falls in any deny CIDR per `02-authentication.md §9.7.1.2` (10 entries: loopback / link-local / RFC 1918 / RFC 4193 / IPv4-mapped IPv6 / `0.0.0.0/8`).
5. **Connect-time pin.** The Hub MUST `connect()` to the same address it checked. Implementations MUST override the resolver for the request lifetime so that DNS rebinding between check and connect cannot redirect the request. In Rust + `reqwest`, this is `ClientBuilder::resolve(host, addr)`. Outbound clients MUST disable redirects (`Policy::none()`); each redirect target is a new Agent-controlled URL that MUST re-run this pipeline.

Hubs MUST emit `URL_BLOCKED_SSRF` (HTTP 422) with `error.details.reason ∈ {parse_error, scheme, host_syntax, resolved_to_deny_cidr, connect_pin_violation}` per `02-authentication.md §9.7.1.3`. For asynchronous deref paths (webhook delivery), Hubs MUST mark the queued row abandoned with the same reason rather than retry.

Hubs SHOULD persist rejections in an `ssrf_attempts` audit table per §9.7.1.4.

The reference v1.1.0 implementation lives at `jecp/src/protocol/url_guard.rs` in the JobDoneBot Hub source.

## Consequences

**Positive**

- Cloud metadata endpoints (the post-Capital One canonical SSRF target) are unreachable through any JECP wire-format field.
- DNS rebinding is closed by IP pinning. An attacker cannot use TTL=1 to swap addresses between validation and connect.
- IPv4-mapped IPv6 is closed by including `::ffff:0.0.0.0/96` in the deny list.
- Redirect chains are closed by `Policy::none()`. The Hub cannot be tricked into following a 302 into private space.
- Conformance assertions (`JECP-OPS-MUST-SSRF-DENY-IP-LITERAL` / `-DENY-RESOLVED` / `-PIN-RESOLVED-IP`) make the policy machine-verifiable across third-party Hubs.
- Audit logging enables coordinated-probing detection.

**Negative**

- **Operator pain for legitimate private targets.** Some Agents legitimately want webhook delivery to a private VPN endpoint or staging host. Those operators must either (a) run their own Hub or (b) ask the JECP operator to extend the allowlist. The protocol does not specify per-namespace allowlist extensions because operator-policy is out of scope.
- **Latency cost.** Every outbound URL adds one DNS resolve + one IP-pinning override per request. Measured on the reference Hub: ~3-12ms p50 for cached resolutions, ~30-60ms p99 for cold cache. Acceptable for webhook delivery (already async) and for invoke forward (network hop dominates).
- **Connection pool bypass.** Pinning the IP per-host disables `reqwest`'s default connection pooling (each pinned address is a distinct host key). For high-volume webhook delivery, operators may want a custom pool keyed by `(host, pinned_addr)` — outside the protocol scope but worth documenting in implementation notes.
- **No defense against allowed-but-malicious public targets.** A Provider that registers `https://exfiltrate.example.com` (a real public domain owned by the attacker) bypasses SSRF checks because it resolves to a public IP. Defending this requires Provider reputation / allowlists / WAF — out of scope for this ADR.

## Alternatives Considered

**Alternative 1: Hostname allowlist only (no resolve+pin).**
The Hub maintains a hand-curated list of allowed Provider domains; rejection is name-based.
*Rejected because:* Operationally infeasible at protocol scope. JECP is a multi-vendor protocol; the canonical Hub at `jecp.dev` cannot maintain a per-namespace allowlist of every Provider's preferred domain. Hubs that want this MAY layer it on top of the deny-list (per §9.7), but the protocol's minimum baseline cannot rely on it.

**Alternative 2: Network-level egress proxy (Squid / Envoy).**
Run all outbound HTTP through a proxy whose deny-list lives in the network layer; application code makes no policy decisions.
*Rejected because:* (a) deployment cost — every Hub operator must run an extra proxy; (b) opaque to conformance assertions — a black-box proxy can't be verified by the conformance harness from outside; (c) DNS rebinding still exists if the proxy uses its own resolver (the proxy must implement the same pin step we're requiring of the application). The proxy is an OPERATIONAL improvement v1.2 may add for additional defense-in-depth (specifically, alongside M3 Composite Workflows where fan-out increases blast radius), but it is not the protocol-level minimum.

**Alternative 3: Hostname-only check (no DNS resolve).**
Reject URLs whose host MATCHES `localhost` or any literal in the deny CIDRs; otherwise allow.
*Rejected because:* Trivially bypassed by registering a public domain whose A record points at `127.0.0.1`. The DNS resolve step is essential. Without it, this defense detects nothing more than a typo.

**Alternative 4: Single-resolve, no pin (validate-then-connect with default resolver).**
Resolve at validation time, check the result against the deny list, then call `client.post(url)` without overriding the resolver — letting `reqwest`'s default resolver re-resolve at connect time.
*Rejected because:* This is the **DNS rebinding bypass**. An attacker uses TTL=1 to flip A records between validation and connect; the second resolve returns a private IP; the Hub connects to private space without ever triggering the deny-list check. The pin is the difference between "we tried" and "we actually defended."

## References

- `spec/02-authentication.md` §9.7 + §9.7.1 (normative requirements ratified by this ADR)
- `spec/error-catalog/URL_BLOCKED_SSRF.md` (wire-format error contract)
- `conformance/v1.0/JECP-OPS-MUST-SSRF-{DENY-IP-LITERAL,DENY-RESOLVED,PIN-RESOLVED-IP}.yaml`
- [OWASP SSRF Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html)
- [Capital One 2019 incident postmortem](https://www.capitalone.com/about/newsroom/cyber-incident/) — canonical reference for SSRF-via-metadata-endpoint
- [RFC 1918](https://datatracker.ietf.org/doc/html/rfc1918) — Private IPv4 ranges
- [RFC 4193](https://datatracker.ietf.org/doc/html/rfc4193) — IPv6 ULA
- [RFC 6890](https://datatracker.ietf.org/doc/html/rfc6890) — Special-purpose address registry
- Reference impl: `jecp/src/protocol/url_guard.rs` (lands in v1.1.0)
