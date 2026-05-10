# JECP — Authentication & Authorization

**Spec Version**: 1.0.0
**Status**: Stable
**Companion**: 00-overview.md, 01-protocol.md

## 1. Abstract

This document defines authentication and authorization for JECP. It specifies API key issuance, the Mandate object for per-call budget pre-authorization, the Provenance hash for replay attack prevention, and the Trust Gate for tier-based capability access.

## 2. Authentication Schemes

JECP supports two authentication schemes:

1. **API Key (REQUIRED)**: An Agent presents `X-Agent-ID` and `X-API-Key` headers (or fields inside `mandate`) on every request.
2. **Mandate (OPTIONAL)**: An Agent issues a per-call signed authorization that limits cost and expires at a specified time.

The Hub MUST require API Key. The Hub MAY require Mandate for specific capabilities or trust tiers.

## 3. API Key

### 3.1 Format

```
agent_id:  <vendor>_ag_<24+ identifier chars>
api_key:   <vendor>_ak_<48+ identifier chars>
```

JECP credentials use a **vendor-prefix-discriminator** convention so multiple Hubs can interoperate without ID collisions. The general pattern is:

```
{vendor_prefix}_{kind}_{secure_random_identifier}
   (lowercase    (`ag`,
   2-8 chars)    `ak`,
                 `pr`,
                 `pk`)
```

Where `vendor_prefix` identifies the issuing Hub (e.g., `jdb` for JobDoneBot, `acme` for an example third-party Hub) and `kind` is one of:

| Kind | Meaning |
|------|---------|
| `ag` | Agent ID |
| `ak` | Agent API key |
| `pr` | Provider ID |
| `pk` | Provider API key |

Hubs MUST document their chosen `vendor_prefix` in `/.well-known/agent-guide.json` so consumers can validate IDs without coupling to a specific implementation.

The reference implementation (JobDoneBot Inc., `https://jecp.dev`) uses `jdb_ag_<24 hex chars>` and `jdb_ak_<48 hex chars>`. Examples in this specification use the `jdb_` prefix purely for illustration; conformant Hubs MAY use any prefix that satisfies the regex in Section 4.2.

### 3.2 Issuance

Agents are issued credentials via:

```
POST {hub_origin}/api/agent/register
Content-Type: application/json

{
  "name": "<unique agent name>",
  "agent_type": "<optional category>",
  "description": "<optional, max 500 chars>",
  "referred_by": "<optional, another agent_id>"
}
```

The Hub MUST:

- Generate `agent_id` and `api_key` using a cryptographically secure random source (e.g., `randomBytes` from RFC 4086-grade RNG).
- Return both values in the response body.
- Display `api_key` exactly once. The Hub MUST NOT support retrieval of the same `api_key` after issuance.
- Apply rate limits to prevent registration flooding (the reference implementation: 10 registrations/minute global).

The Hub SHOULD:

- Issue a free tier allowance (the reference implementation: 100 free calls per Agent).
- Track referrals via the optional `referred_by` field, awarding bonus calls to both parties.

### 3.3 Storage Requirements

The Agent owner MUST:

- Store `api_key` in backend environment variables, secret managers, or equivalent.
- NEVER include `api_key` in frontend code, mobile app constants, or public source repositories.
- Treat the key with the same operational security as a Stripe Secret Key or AWS access key.

The Hub MUST NOT:

- Log `api_key` values in plaintext.
- Include `api_key` values in URLs.
- Expose `api_key` values in error messages.

The Hub SHOULD:

- Store `api_key` hashed (bcrypt or argon2id) at rest. (The reference implementation currently stores plaintext; future versions will migrate.)

### 3.4 Rotation

Future versions of this spec will define `POST /api/agent/me/rotate-key`. v1.0 implementations MAY require re-registration to obtain a new key.

### 3.5 Validation

On every request, the Hub MUST:

1. Locate `agent_id` from `X-Agent-ID` header or `mandate.agent_id`.
2. Locate `api_key` from `X-API-Key` header or `mandate.api_key`.
3. If either is missing, return HTTP 401 `AUTH_REQUIRED`.
4. Look up the Agent record matching both values.
5. If no match, return HTTP 401 `INVALID_API_KEY` (do NOT distinguish between "agent not found" and "key mismatch" to prevent enumeration).
6. Proceed to Trust Gate check (Section 6).

## 4. Mandate

### 4.1 Purpose

A Mandate is an authorization object issued by the Agent owner that limits the cost of a single JECP call. It serves three purposes:

1. **Per-call budget enforcement**: Prevents a runaway autonomous Agent from exhausting the wallet.
2. **Time-bounded scope**: Sessions expire and require re-issuance.
3. **Replay protection** (via Provenance): Prevents captured Mandates from being reused.

### 4.2 Schema

```json
{
  "$id": "https://jecp.dev/schemas/v1/mandate.json",
  "type": "object",
  "required": ["agent_id", "api_key"],
  "properties": {
    "agent_id":         { "type": "string", "pattern": "^[a-z]{2,8}_ag_[A-Za-z0-9]{16,}$" },
    "api_key":          { "type": "string", "pattern": "^[a-z]{2,8}_ak_[A-Za-z0-9]{16,}$" },
    "budget_usdc":      { "type": "number", "minimum": 0, "maximum": 1000 },
    "expires_at":       { "type": "string", "format": "date-time" },
    "provenance_hash":  { "type": "string", "pattern": "^(v2:[0-9]+:[0-9a-fA-F]{16,}:[0-9a-f]{64}|[0-9a-f]{64})$" }
  }
}
```

The `agent_id` and `api_key` regex accept any lowercase 2–8 char vendor prefix (Section 3.1). The `provenance_hash` regex accepts both v1 (legacy 64-hex) and v2 (`v2:<ts>:<nonce>:<hmac>`) wire formats (Section 5).

> **Reference-implementation example values** (informative): the JobDoneBot Hub issues `agent_id` as `jdb_ag_<24 hex>` and `api_key` as `jdb_ak_<48 alphanumeric>`. Other Hubs can use different concrete formats as long as they match the regex above.

### 4.3 Field Definitions

#### `agent_id` / `api_key`

REQUIRED. Same as the headers (Section 3). When present in `mandate`, they take precedence over headers.

#### `budget_usdc`

- **Type**: number
- **Required**: SHOULD (RECOMMENDED for autonomous Agents)
- **Range**: 0 to 1000
- **Semantics in v1.0**: **Per-call upper bound**. The Hub MUST reject if `cost > budget_usdc` with HTTP 402 `INSUFFICIENT_BUDGET`. v1.0 does NOT track cumulative spend across multiple calls in a single Mandate.
- **Future (v1.1+)**: A separate `budget_total_usdc` field will track cumulative spend.

#### `expires_at`

- **Type**: string
- **Required**: SHOULD
- **Format**: RFC 3339 date-time (e.g., `"2026-12-31T23:59:59Z"`)
- **Semantics**: The Hub MUST reject if `expires_at < now()` with HTTP 401 `MANDATE_EXPIRED`.

If absent, the Mandate has no expiration. Hubs MAY enforce a default expiration (the reference implementation: 24 hours).

#### `provenance_hash`

- **Type**: string
- **Required**: OPTIONAL (RECOMMENDED for autonomous Agents at Trust Tier Silver+)
- **Format**: Either of:
  - **v2 (RECOMMENDED)**: `"v2:<unix_seconds>:<nonce_hex>:<hmac_hex>"` — see Section 5.2
  - **v1 (legacy, sunset 2026-11-01)**: 64 lowercase hex chars (SHA-256 output) — see Section 5.6. From 2026-08-01 Hubs attach `Deprecation` / `Sunset` response headers; final removal 2026-11-01.
- **Semantics**: See Section 5.

### 4.4 Validation Order

The Hub MUST validate Mandate fields in this order:

1. `agent_id` and `api_key` match a registered Agent (else `INVALID_API_KEY`).
2. `expires_at` is in the future (else `MANDATE_EXPIRED`).
3. `provenance_hash` matches server-computed hash (else `PROVENANCE_MISMATCH`).
4. `budget_usdc >= cost(capability, action)` (else `INSUFFICIENT_BUDGET`).

If `budget_usdc` is omitted, the Hub MUST treat it as no upper bound and proceed to standard billing (free tier → wallet → Mandate fallback).

## 5. Provenance Hash

> **v1.0 stable note**: Two Provenance schemes are defined: v2 (HMAC-SHA256, RECOMMENDED) and v1 (SHA-256, deprecated). New deployments MUST use v2; v1 verifiers are RETAINED in conformant Hubs through 2026-11-01 for backward compatibility. See Section 5.7 for the full migration timetable.

### 5.1 Purpose

Prevents replay attacks where an attacker captures a Mandate and reuses it. Without Provenance, a stolen Mandate is valid until `expires_at`. With Provenance, the hash cryptographically binds the Mandate to a specific time window, a fresh nonce, and possession of the `api_key`.

### 5.2 Provenance v2 — HMAC-SHA256 (RECOMMENDED)

#### Wire format

```
provenance_hash = "v2:" || timestamp || ":" || nonce || ":" || hex(hmac_tag)

hmac_tag = HMAC-SHA256(
  key  = api_key,
  msg  = agent_id || ":" || timestamp || ":" || nonce
)
```

Where:

- `timestamp` is unix seconds (decimal string, no padding).
- `nonce` is at least 16 hex characters of cryptographically secure random data, generated fresh per call by the Agent.
- `hex(hmac_tag)` is the lowercase 64-char hex encoding of the 32-byte HMAC-SHA256 output.
- `||` is byte concatenation.

#### Verification

On receiving a Mandate with a v2 `provenance_hash`, the Hub MUST:

1. Parse the wire format. If it does not match `^v2:[0-9]+:[0-9a-fA-F]{16,}:[0-9a-f]{64}$`, reject with `PROVENANCE_MISMATCH`.
2. Validate clock skew: `|now - timestamp| <= 300` seconds. Otherwise reject with `PROVENANCE_MISMATCH`.
3. Look up the canonical plaintext `api_key` for `agent_id` (the Hub already holds this from the Mandate's `api_key` field which has been authenticated against the Hub's stored bcrypt hash).
4. Recompute `hmac_tag` and constant-time-compare to the received tag. Mismatch → reject with `PROVENANCE_MISMATCH`.
5. Replay defense: Hubs SHOULD maintain an LRU cache of `(agent_id, nonce)` for at least 600 seconds. If `(agent_id, nonce)` is already in the cache, reject with `PROVENANCE_MISMATCH` and `details.subcause = nonce_replay`. Otherwise insert. (Promotion to MUST is targeted for v1.1 once cluster-wide cache semantics are specified — see §5.9.)

The 300-second clock-skew window MUST NOT be widened by conformant Hubs without coordinated spec amendment. The 600-second nonce cache window applies when the Hub implements the cache; widening past 600s is permitted as a Hub configuration choice (longer windows strengthen the defense at the cost of memory).

#### 5.2.1 Cache implementation requirements (informative)

When a Hub implements the §5.2 step 5 cache, the following requirements apply:

- **Lookup case**: nonce comparison is case-insensitive. Hubs MUST store and compare nonces in lowercase to ensure that `"AbCd"` and `"abcd"` are treated as the same nonce. SDKs SHOULD emit lowercase hex (the reference SDK does), but Hubs MUST tolerate uppercase input.
- **Atomic check-and-insert**: The lookup and insertion MUST be a single atomic operation. A naive `if !contains(k) { insert(k) }` opens a TOCTOU race window in which two concurrent invocations with the same nonce both observe an empty cache and both succeed.
- **Per-agent flood defense**: Hubs SHOULD enforce a per-agent rate limit (the reference Hub uses 60 RPM by default). At 60 RPM × 600s TTL, a single agent cannot occupy more than ~600 cache entries — well below typical global caps and unable to evict other agents' state. The rate limit, not a per-agent cache quota, is the recommended mitigation against single-agent flood attacks.
- **Single-instance vs cluster**: A single-instance, in-memory cache is sufficient for Hubs running on a single primary node. Multi-region or load-balanced Hubs MUST share the cache (e.g. via Redis) or the replay defense is bypassed by routing the replay to a different region. The reference Hub at `setsuna-jobdonebot.fly.dev` is currently single-region (Tokyo) and uses an in-memory cache; v1.1 will specify the shared-cache protocol (see §5.9).
- **Restart**: Cache contents are not durable. After a Hub restart, the cache is empty and the first 300 seconds following restart re-open the replay window. This is acceptable because a) restarts are rare, b) the timestamp window remains enforced, and c) the bcrypt-verified `api_key` is still required.

#### 5.2.2 Idempotency vs Provenance interaction (informative)

> See **[ADR-0001 — Idempotency–Provenance Interaction](../adr/0001-idempotency-provenance-interaction.md)** for the architecture decision rationale, the three alternatives we considered and rejected, and the wire-format guarantee this commits us to.

Hubs implement two distinct but related caches: idempotency (§9.4) and Provenance replay defense (§5.2 step 5). Their interaction is non-obvious and easy to get wrong; conformant Hubs MUST follow this ordering:

1. **Idempotency check fires first.** A request whose `id` is already in the idempotency cache returns the cached response without re-executing the handler. The cached response is returned regardless of whether the new request's `provenance_hash` matches the cached request's.
2. **Therefore, idempotency cache keys MUST include `mandate.provenance_hash`** in their canonical input hash. Without this, two requests with the same `id` and same `input` but different `provenance_hash` collide on the idempotency cache, returning a cached success response and bypassing Provenance verification on the second call. The reference Hub computes the idempotency key as `SHA256(capability || "|" || action || "|" || input || "|" || mandate.provenance_hash)`.
3. **Replay cache only sees first-time requests.** Because step 1 short-circuits idempotent retries, the replay cache observes a given `(agent_id, nonce)` exactly once even if the agent issues the same request multiple times (the legitimate retry pattern). This means the replay cache TTL (600s) does NOT need to extend to the idempotency window (24h).

#### Why v2

Compared to v1, Provenance v2 eliminates three weaknesses:

1. **No key prefix leak.** v1 mixes `api_key[..8]` into the hash *input*; the hash output therefore embeds a partial key fingerprint. v2 uses `api_key` only as the HMAC key, so output reveals nothing about the key.
2. **No collision under key prefix overlap.** Two Agents sharing the first 8 characters of their `api_key` could produce identical v1 hashes for the same `total_calls` and time window. v2 uses HMAC over per-call random nonce → collision probability is `2^-256`.
3. **Works after key rotation.** Hubs that store `api_key` only as a bcrypt hash (RECOMMENDED — see Section 3.3) cannot compute v1 because it requires the plaintext prefix from a stored value. v2 uses the `api_key` plaintext supplied by the Agent in `mandate.api_key` (authenticated against the bcrypt hash earlier in the same request), so it works even when the stored plaintext column is `NULL`.

### 5.3 When Provenance is Required

The Hub MAY enforce Provenance by capability or trust tier:

- Trust Tier Bronze: Provenance OPTIONAL
- Trust Tier Silver: Provenance OPTIONAL but RECOMMENDED
- Trust Tier Gold: Provenance RECOMMENDED
- Trust Tier Platinum: Provenance REQUIRED for `workflow.*` capability

Hubs MUST document their enforcement policy in `/.well-known/agent-guide.json`.

### 5.4 Format Discrimination

Hubs MUST dispatch verification based on the `"v2:"` prefix of the wire string:

```
if claimed.startsWith("v2:"):
    verify_v2(claimed)
else:
    verify_v1(claimed)
```

This allows v1 and v2 hashes to coexist during the migration window without breaking changes to the `mandate.provenance_hash` field type.

### 5.5 Reference Implementation Note

Pre-v1.0 design drafts published by the reference implementation (JobDoneBot Inc., `JECP-TECHNICAL-DESIGN.md`) explored a 4-part v1 input that included a `unix_timestamp_60s_window` term. The actual Rust reference implementation has always shipped the 3-part input documented in Section 5.6. v1.0 stable canonicalizes the 3-part form as the only conformant v1 wire format and supersedes it for new deployments with v2 (Section 5.2). Conformant Hubs MUST implement v2 verification. v1 verification is OPTIONAL for new Hubs and RETAINED for backward compatibility through 2026-11-01.

### 5.6 Provenance v1 — SHA-256 (DEPRECATED, sunset 2026-11-01)

> **Status**: Deprecated as of 2026-05-10. New Agents and new Hub deployments MUST use v2 (Section 5.2). v1 is documented here only for verifying hashes generated by Agents that have not yet upgraded.

#### Wire format

```
provenance_hash = lowercase_hex( SHA256(
  agent_id || ":" || total_calls || ":" || api_key[..8]
))
```

Where:

- `total_calls` is the Agent's lifetime call count (decimal string, no padding).
- `api_key[..8]` is the first 8 characters of `api_key`.

#### Verification

The Hub:

1. Computes the same hash with the Agent's current `total_calls` and `api_key`.
2. Constant-time compares to the received hash.
3. On mismatch, returns HTTP 403 `PROVENANCE_MISMATCH`.

v1 has no timestamp or nonce binding, so it provides no replay defense beyond `mandate.expires_at`. Hubs that accept v1 SHOULD enforce a short `expires_at` window (≤ 5 minutes) at the application layer.

### 5.7 Sunset Schedule for v1

| Date | Conformance Requirement |
|------|------------------------|
| 2026-05-10 | v1.0 stable published. Hubs MUST implement v2 verification within 30 days of v1.0 release. SDKs SHOULD ship `computeProvenanceV2` helpers. |
| 2026-08-01 | Hubs MUST attach `Deprecation: true`, `Sunset: Sat, 01 Nov 2026 00:00:00 GMT`, and `Link: <https://jecp.dev/spec/v1.0/02-authentication.md#57-sunset-schedule-for-v1>; rel="deprecation"` response headers when an invocation succeeds with a v1 hash, so Agents are notified to upgrade. Hubs MAY attach these headers earlier (the reference Hub ships the implementation in v1.0.1 behind a feature flag, defaulting off until the date below). The `Sunset` value MUST be the IMF-fixdate form per RFC 8594 §3; `Deprecation` MUST be the literal `true` per the IETF `Deprecation` HTTP Header draft (NOT the timestamp form). |
| 2026-11-01 | Hubs MUST reject v1 wire format with `PROVENANCE_MISMATCH`. v1 verifiers MAY be removed from implementations. |

### 5.8 Migrating from v1 to v2 (informative)

For an Agent currently sending v1 hashes, the migration is three steps:

1. **Upgrade SDK**. `@jecpdev/sdk` v0.6.0 ships `computeProvenanceV2`. Other-language SDKs SHOULD ship an equivalent helper before 2026-08-01.
2. **Swap the helper call**. Replace any `computeProvenanceV1({ apiKey, agentId, totalCalls })` (or hand-rolled SHA-256) with `computeProvenanceV2({ apiKey, agentId })` and pass the returned wire string into `mandate.provenance_hash` unchanged. Defaults for `timestamp` and `nonce` are sufficient for typical use.
3. **Confirm acceptance**. Issue one call against the Hub. A `200 OK` body confirms v2 acceptance. A `403 PROVENANCE_MISMATCH` with `details.subcause = clock_skew` indicates the Agent's clock is more than 300s off — sync NTP. Other subcauses are documented in 03-errors.md §3.1.

After 2026-08-01, Hubs MUST attach `Deprecation: true` and `Sunset: Sat, 01 Nov 2026 00:00:00 GMT` response headers when an Agent uses v1; treat these headers as the migration alarm.

### 5.9 Replay-defense cache — v1.1 plan (informative)

The §5.2 step 5 nonce cache is SHOULD in v1.0 and is targeted for promotion to MUST in v1.1. The remaining work is:

- Define cluster-wide cache semantics for multi-region Hubs (current Fly.io reference impl is single-primary, so single-instance LRU suffices, but a multi-region Hub would need a Redis-class shared cache to prevent regional replay).
- Specify a conformance test fixture that exercises the cache (replay rejection within 600s, success after eviction).
- Specify a `details.subcause = nonce_replay` payload on `PROVENANCE_MISMATCH` so SDKs can present a clear "duplicate request" error.

Hubs that ship the cache early are conformant; Hubs that omit it remain conformant against v1.0 but are encouraged to enable the cache as a defense-in-depth measure for any Agent issuing Mandates over networks the Hub does not fully control.

## 6. Trust Gate

### 6.1 Purpose

A staged trust system that grants more powerful capabilities and higher rate limits as an Agent accumulates a track record. Modeled on Stripe's risk gates and PayPal's seller tiers.

### 6.2 Tiers

| Tier      | Total Calls | Rate Limit (rpm) | Default Capabilities |
|-----------|-------------|------------------|----------------------|
| Bronze    | 0–99        | 10               | content-factory, sns-engine |
| Silver    | 100–499     | 30               | + document-pipeline, data-insight |
| Gold      | 500–1,999   | 100              | + file-chain |
| Platinum  | 2,000+      | 500              | + workflow (full) |

`total_calls` includes both successful free-tier calls and successful paid calls. Failed calls do NOT count.

### 6.3 Promotion

Promotion is automatic upon reaching the threshold. The Hub MUST evaluate the Agent's tier on every request.

Demotion does NOT occur in v1.0. Future versions MAY introduce demotion for fraud or refunds.

### 6.4 Capability Requirements

A Hub MAY define per-capability `trust_tier_required`. If an Agent's tier is below the requirement, the Hub MUST return HTTP 403 `INSUFFICIENT_TRUST` with:

```json
{
  "error": {
    "code": "INSUFFICIENT_TRUST",
    "details": {
      "required": "platinum",
      "current": "bronze"
    }
  },
  "next_action": {
    "type": "earn_trust",
    "current_tier": "bronze",
    "required_tier": "platinum",
    "fallback": { /* lower-tier alternatives */ }
  }
}
```

### 6.5 Rate Limiting

Rate limits MUST be enforced as a sliding window over the last 60 seconds. The Hub MUST return HTTP 429 `RATE_LIMITED` with `Retry-After` header on overage.

The default per-tier limits in Section 6.2 are minimums. Hubs MAY apply stricter limits to specific capabilities (e.g., `workflow.*` may use 50% of tier limit).

## 7. Authorization for Providers (Stage 3)

For third-party Providers (Stage 3 feature), additional authentication applies between Hub and Provider:

- Hub-to-Provider: `X-JECP-Signature` header with HMAC-SHA256 over the request body, using a shared secret issued at Provider registration.
- Provider-to-Hub callbacks (async mode): same scheme.
- DNS verification at registration: Provider proves domain ownership via TXT record.

Full Provider authentication is specified in 04-manifest.md.

## 8. Sequence Diagrams

### 8.1 Bronze Agent — First Call

```
Agent              Hub               Database
  |  POST /v1/invoke |                   |
  |----------------->|                   |
  |                  | Auth (API key)    |
  |                  |------------------>|
  |                  | OK                |
  |                  |<------------------|
  |                  | Trust Gate: Bronze allowed|
  |                  | Free call: yes (97/100)   |
  |                  | Decrement free_calls       |
  |                  |------------------>|
  |                  | Execute capability        |
  |                  | ...                |
  |  200 OK          |                   |
  |<-----------------|                   |
```

### 8.2 Mandate-Authorized Call

```
Agent              Hub               Database
  |  POST /v1/invoke |                   |
  |  + mandate       |                   |
  |----------------->|                   |
  |                  | Auth (mandate.api_key)|
  |                  |------------------>|
  |                  | OK                |
  |                  |<------------------|
  |                  | Validate mandate:|
  |                  |   expires_at? OK  |
  |                  |   budget>=cost? OK|
  |                  |   provenance? OK  |
  |                  | Trust Gate: OK    |
  |                  | Charge wallet     |
  |                  |------------------>|
  |                  | balance_after=...  |
  |                  |<------------------|
  |  200 OK + billing|                   |
  |<-----------------|                   |
```

## 9. Security Considerations

### 9.1 API Key Compromise

If an `api_key` is exposed:

1. The owner MUST contact the Hub operator immediately.
2. The owner SHOULD migrate to a new Agent registration as v1.0 has no rotation API.
3. The Hub SHOULD immediately revoke the compromised key by setting `agent_profiles.metadata.revoked = true`.

### 9.2 Mandate Theft

If a Mandate is captured in transit (mitigated by HTTPS), the attacker has limited time:

- Without Provenance: until `expires_at`.
- With Provenance v1 (legacy): no nonce binding, so an attacker can replay the captured Mandate freely until `expires_at`. v1 alone does not defend against replay.
- With Provenance v2 + nonce cache (RECOMMENDED Hub configuration): at most 300 seconds (the clock-skew window) AND the attacker cannot replay the same Mandate twice because the second replay collides with the cached `(agent_id, nonce)` pair. Outside the 300s window the timestamp validation rejects the Mandate even if the nonce has aged out of the cache.
- With Provenance v2 without nonce cache (Hub default in v1.0): at most 300 seconds. Within the 300s window the attacker can replay the same Mandate. Hubs that require strict single-use semantics MUST implement §5.2 step 5 — see §5.9 for the v1.1 plan to upgrade this to a cross-Hub MUST.

Therefore, Provenance v2 is RECOMMENDED for any Agent that issues Mandates over networks the Agent owner does not fully control. Provenance v1 alone is insufficient for replay defense and is scheduled for removal in 2026-11-01 (Section 5.7).

### 9.3 TLS Requirements

- All JECP traffic MUST use TLS 1.2 or higher.
- Hubs SHOULD enable HSTS with `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`.
- Hubs MUST validate certificates if calling Providers (Stage 3).

### 9.4 Replay Attacks

Beyond Provenance:

- The Hub MUST enforce idempotency (Section 5 of 01-protocol.md): a successful response is cached, second call returns cached result without re-charging.
- Idempotency window is at least 24 hours.

### 9.5 Brute Force

Registration endpoints MUST be rate-limited (recommended: 10/minute per IP).

API key validation: the Hub MUST use constant-time comparison to prevent timing attacks.

### 9.6 Privilege Escalation

The Trust Gate MUST be enforced server-side. Clients MUST NOT be trusted to declare their own tier.

### 9.7 Server-Side Request Forgery (SSRF) on Agent-Controlled URLs

Multiple JECP fields accept URLs that the Hub may dereference at request time (`callback_url` for async invocations, Provider `endpoint_url` during routing — see 04-manifest.md, webhook destinations — see 01-protocol.md §5). If the Hub fetches these URLs without restriction, an attacker can use the Hub as a proxy into the Hub's internal network.

Conformant Hubs MUST validate every Agent-controlled URL before issuing the outbound request. Validation MUST reject all of the following:

| Class | Example | Rationale |
|-------|---------|-----------|
| Loopback addresses | `http://127.0.0.1`, `http://[::1]`, `http://localhost` | Reach internal services on the Hub host |
| Link-local addresses | `http://169.254.169.254`, `http://[fe80::]` | EC2 / GCP / Azure instance metadata endpoints leak IAM credentials |
| Private IPv4 ranges | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | Reach internal services on the Hub VPC |
| Private IPv6 ranges | `fc00::/7` (ULA) | IPv6 equivalent of private IPv4 |
| Non-HTTPS schemes | `gopher://`, `file://`, `ftp://`, `dict://` | Bypass HTTP semantics; some can read local files |
| Hostnames that resolve to any of the above | DNS rebinding using a TTL-1 record | Bypasses single-resolution-time checks |

Hubs MUST resolve hostnames at request time and MUST re-check the resolved IP against the deny list immediately before connecting. Hubs SHOULD pin the resolved IP for the duration of the request to prevent DNS-rebinding (the IP used for the `connect()` call MUST equal the IP that passed the deny-list check).

Hubs MUST enforce these rules on every URL field, including but not limited to:

- `mandate.callback_url` (when used)
- `provider.endpoint_url` (in Provider manifests — see 04-manifest.md)
- `webhook.destination_url` (when registered — see 01-protocol.md §5)
- `referred_by` if it ever takes a URL form (currently scalar Agent ID)

Hubs MAY maintain an additional explicit allowlist of public Provider domains for `provider.endpoint_url`, but the deny list above is the minimum baseline.

Conformant Hubs SHOULD log SSRF attempts (URLs that hit the deny list) with sufficient detail to detect coordinated probing.

### 9.7.1 Composite enforcement (v1.0.2 errata, normative)

This section specifies the wire-format requirements for SSRF defense. Hubs claiming v1.0.2 (or later) conformance MUST implement the controls below. v1.1.0 ships the reference implementation in `protocol/url_guard.rs`; ADR-0002 records the architecture decision.

#### 9.7.1.1 Validation pipeline

For every Agent-controlled URL the Hub dereferences, the Hub MUST run the following pipeline IN ORDER. Stopping at the first rejection is RECOMMENDED for performance; rejecting on the strictest signal is REQUIRED for correctness.

1. **Parse**. The URL MUST parse per RFC 3986. Malformed URLs MUST be rejected.
2. **Scheme allowlist**. The scheme MUST be `https` in production. Hubs MAY permit `http` only when the Hub operator explicitly opts in for testing (e.g., `JECP_TEST_MODE=true` env flag, never toggleable via API).
3. **Host syntax**. The host MUST be either a registered domain name (RFC 1123) or an IP literal. Percent-encoded hosts (e.g., `%31%32%37.0.0.1` for `127.0.0.1`) MUST be normalized before deny-list comparison.
4. **DNS resolve**. The Hub MUST resolve the host via the system resolver (or an equivalent). If resolution returns more than one address, every returned address MUST be checked against the deny CIDRs in §9.7.
5. **Deny-list check**. If any resolved address falls in any deny CIDR, the Hub MUST reject the URL.
6. **Pin**. The Hub MUST `connect()` to the SAME address it checked. Implementations SHOULD use `reqwest::Client::resolve(host, addr)` (Rust) or equivalent to override the resolver for the request lifetime. Re-resolving between check and `connect()` allows DNS-rebinding bypass.
7. **No redirects**. Outbound clients MUST NOT follow HTTP redirects automatically. Each redirect target is a NEW Agent-controlled URL that MUST run through this pipeline before being followed. Implementations SHOULD disable redirects (`Policy::none()`) and surface them to the caller for explicit re-validation.

#### 9.7.1.2 Required deny CIDRs

The minimum deny set for IPv4 + IPv6:

```
0.0.0.0/8           # "any" / unspecified
10.0.0.0/8          # RFC 1918
127.0.0.0/8         # Loopback (covers 127.0.0.1)
169.254.0.0/16      # Link-local (AWS / GCP / Azure metadata at 169.254.169.254)
172.16.0.0/12       # RFC 1918
192.168.0.0/16      # RFC 1918
::1/128             # IPv6 loopback
fe80::/10           # IPv6 link-local
fc00::/7            # IPv6 ULA (RFC 4193)
::ffff:0.0.0.0/96   # IPv4-mapped IPv6 (catches ::ffff:127.0.0.1)
```

Hubs MAY extend this set with operator-specific CIDRs (e.g., the Hub's own VPC CIDR).

#### 9.7.1.3 `URL_BLOCKED_SSRF` wire-format error

When the Hub rejects an Agent-controlled URL, it MUST return the JECP envelope below (regardless of whether the rejection happens at register-time, at deref-time, or during webhook delivery):

```json
{
  "jecp":   "1.0",
  "status": "failed",
  "error": {
    "code":    "URL_BLOCKED_SSRF",
    "message": "URL blocked by SSRF policy",
    "details": {
      "field":             "<endpoint_url | callback_url | webhook_destination_url>",
      "blocked_url":       "<the URL the Hub rejected, with credentials redacted>",
      "reason":            "<scheme | host_syntax | resolved_to_deny_cidr | parse_error>",
      "documentation_url": "https://jecp.dev/errors/url_blocked_ssrf"
    }
  }
}
```

HTTP status: **422 Unprocessable Entity** (the URL is structurally a valid HTTP URL but violates Hub policy).

For asynchronous deref paths (webhook delivery, scheduled retries), the Hub MUST mark the queued row as abandoned with the same reason rather than retrying indefinitely.

#### 9.7.1.4 Audit logging (RECOMMENDED)

Hubs SHOULD persist every rejection in an `ssrf_attempts` audit table with:

- `timestamp`
- `agent_id` (or `provider_id` if the URL came from a Provider register / DNS-verify path)
- `field_name` (which URL field carried the blocked value)
- `blocked_url` (with credentials redacted)
- `reason`

The audit log enables correlation across actors during a coordinated probing window.

#### 9.7.1.5 Conformance assertions

The reference v1.0 conformance suite in `conformance/v1.0/` ships three MUST assertions for §9.7.1:

- `JECP-OPS-MUST-SSRF-DENY-IP-LITERAL` — register/subscribe with deny-CIDR IP literal returns 422 `URL_BLOCKED_SSRF`.
- `JECP-OPS-MUST-SSRF-DENY-RESOLVED` — hostname whose A/AAAA falls in a deny CIDR rejected at deref time.
- `JECP-OPS-MUST-SSRF-PIN-RESOLVED-IP` — TTL-1 toggle resolver fixture; Hub MUST connect to the pinned (validated) address.

## 10. References

- [RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119)
- [RFC 4086](https://datatracker.ietf.org/doc/html/rfc4086) — Randomness Requirements
- [RFC 6234](https://datatracker.ietf.org/doc/html/rfc6234) — SHA-256
- [RFC 8265](https://datatracker.ietf.org/doc/html/rfc8265) — String comparison

## 11. Authors

JECP Working Group. Contact: hello@jecp.dev.
