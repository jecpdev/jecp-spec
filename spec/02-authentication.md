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
agent_id:  jdb_ag_<24 hex chars>
api_key:   jdb_ak_<48 hex chars>
```

The literal prefixes `jdb_ag_` and `jdb_ak_` are the canonical convention of the reference implementation (JobDoneBot Inc.). Independent Hubs MAY use different prefixes (e.g., `acme_ag_`, `acme_ak_`) but MUST document them.

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
    "agent_id":         { "type": "string", "pattern": "^jdb_ag_[a-f0-9]+$" },
    "api_key":          { "type": "string", "pattern": "^jdb_ak_[a-zA-Z0-9]+$" },
    "budget_usdc":      { "type": "number", "minimum": 0, "maximum": 1000 },
    "expires_at":       { "type": "string", "format": "date-time" },
    "provenance_hash":  { "type": "string", "pattern": "^[a-f0-9]{64}$" }
  }
}
```

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
- **Format**: 64 lowercase hex chars (SHA-256 output)
- **Semantics**: See Section 5.

### 4.4 Validation Order

The Hub MUST validate Mandate fields in this order:

1. `agent_id` and `api_key` match a registered Agent (else `INVALID_API_KEY`).
2. `expires_at` is in the future (else `MANDATE_EXPIRED`).
3. `provenance_hash` matches server-computed hash (else `PROVENANCE_MISMATCH`).
4. `budget_usdc >= cost(capability, action)` (else `INSUFFICIENT_BUDGET`).

If `budget_usdc` is omitted, the Hub MUST treat it as no upper bound and proceed to standard billing (free tier → wallet → Mandate fallback).

## 5. Provenance Hash

### 5.1 Purpose

Prevents replay attacks where an attacker captures a Mandate and reuses it. Without Provenance, a stolen Mandate is valid until `expires_at`. With Provenance, the hash binds the Mandate to a specific time window and Agent state.

### 5.2 Computation

```
provenance_hash = SHA256(
  agent_id || ":" ||
  total_calls || ":" ||
  api_key[..8] || ":" ||
  unix_timestamp_60s_window
)
```

Where:

- `||` is byte concatenation
- `total_calls` is the Agent's lifetime call count (decimal string, no padding)
- `api_key[..8]` is the first 8 characters of `api_key`
- `unix_timestamp_60s_window` is `floor(unix_seconds / 60) * 60` (decimal string)

### 5.3 Verification

The Hub:

1. Computes the same hash with current values.
2. Also computes hashes for `±60 seconds` (1 prior, 1 next minute window) to allow clock skew.
3. If any of the 3 candidates matches, accept.
4. Otherwise, reject with HTTP 403 `PROVENANCE_MISMATCH`.

The 60-second window MUST NOT be widened beyond `±60s` to prevent extended replay opportunities.

### 5.4 When Provenance is Required

The Hub MAY enforce Provenance by capability or trust tier:

- Trust Tier Bronze: Provenance OPTIONAL
- Trust Tier Silver: Provenance OPTIONAL but RECOMMENDED
- Trust Tier Gold: Provenance RECOMMENDED
- Trust Tier Platinum: Provenance REQUIRED for `workflow.*` capability

Hubs MUST document their enforcement policy in `/.well-known/agent-guide.json`.

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
  |  POST /v1/jecp   |                   |
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
  |  POST /v1/jecp   |                   |
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
- With Provenance: at most 120 seconds (the ±60s window).

Therefore, Provenance is RECOMMENDED for any Agent that issues Mandates over networks the Agent owner does not fully control.

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

## 10. References

- [RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119)
- [RFC 4086](https://datatracker.ietf.org/doc/html/rfc4086) — Randomness Requirements
- [RFC 6234](https://datatracker.ietf.org/doc/html/rfc6234) — SHA-256
- [RFC 8265](https://datatracker.ietf.org/doc/html/rfc8265) — String comparison

## 11. Authors

JECP Working Group. Contact: hello@jecp.dev.
