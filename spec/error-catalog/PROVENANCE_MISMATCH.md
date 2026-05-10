# `PROVENANCE_MISMATCH`

> Public URL: https://jecp.dev/errors/provenance_mismatch
> Spec source: `spec/03-errors.md` §3.1 + `spec/02-authentication.md` §5
> Last updated: 2026-05-10 (v1.0.1)

## What it means

The Hub rejected the `mandate.provenance_hash` value you sent. The hash was either malformed, computed against the wrong inputs, signed with the wrong key, used a stale timestamp, or replays a nonce the Hub has already seen.

HTTP status: `403 Forbidden`.

## Subcause registry

The Hub's response body carries `error.details.subcause`. Use it to diagnose:

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "PROVENANCE_MISMATCH",
    "message": "...",
    "details": {
      "subcause": "<one of the values below>",
      "documentation_url": "https://jecp.dev/errors/provenance_mismatch#<subcause>",
      "drift_seconds": <signed integer, only when subcause = clock_skew>
    }
  }
}
```

### `wire_malformed`

The `provenance_hash` value does not parse as either of the two valid forms:

- v1: 64 lowercase hex characters
- v2: `v2:<unix_seconds>:<nonce_hex_>=16>:<hmac_hex_64>`

**Fix in 30s**: regenerate via the SDK helper. Don't hand-roll the wire format.

```ts
import { computeProvenanceV2 } from '@jecpdev/sdk';

const hash = computeProvenanceV2({ apiKey, agentId });
//      ^^^^ ready for mandate.provenance_hash
```

### `clock_skew`

The v2 timestamp is more than 300 seconds away from the Hub's clock. The `details.drift_seconds` field is signed: positive means the Agent's clock is *ahead*, negative means *behind*.

**Fix in 30s**: synchronize NTP on the Agent host.

```bash
# Linux
sudo timedatectl set-ntp true
# macOS
sudo sntp -sS pool.ntp.org
```

If you can't sync NTP, regenerate `provenance_hash` with a `timestamp` parameter set to "what you believe is now" — but that's a band-aid; clock drift will recur.

### `hmac_mismatch`

The HMAC tag in the wire string does not match the value the Hub recomputes from `(api_key, agent_id, timestamp, nonce)`. The most common cause is that the `apiKey` you signed with is different from the one the Hub authenticated against.

**Fix in 30s**: confirm the api_key the Agent signs with is identical to the one in `mandate.api_key`. Common gotchas:

- You rotated the key but kept signing with the old one beyond the grace period.
- You set `mandate.api_key` from one env var and `computeProvenanceV2({ apiKey })` from another.
- The Agent's process has the wrong env var loaded.

### `nonce_replay`

The `(agent_id, nonce)` tuple has already been observed within the past 600 seconds. Nonces are single-use.

**Fix in 30s**: regenerate the `provenance_hash` per request. Never reuse a nonce.

`computeProvenanceV2({ apiKey, agentId })` defaults to a fresh `randomBytes(16).toString('hex')` per call — if you're seeing this error you're probably caching the result. Move the call into the request hot path.

### `v1_legacy_mismatch`

You sent a v1 (SHA-256) `provenance_hash` and the Hub recomputed a different value. Most often, the Agent's `total_calls` counter you signed against has drifted from the Hub's view (e.g., another concurrent invocation incremented it).

**Fix in 30s**: migrate to v2. v1 cannot be made replay-safe and is being sunset 2026-11-01.

```ts
- import { computeProvenanceV1 } from '@jecpdev/sdk';
- const hash = computeProvenanceV1({ apiKey, agentId, totalCalls });
+ import { computeProvenanceV2 } from '@jecpdev/sdk';
+ const hash = computeProvenanceV2({ apiKey, agentId });
```

### `v1_unavailable`

You sent a v1 `provenance_hash` for an Agent whose plaintext `api_key` is no longer stored on the Hub (after key rotation, the plaintext column is NULLed and only the bcrypt hash remains). v1 cannot be computed without the plaintext.

**Fix in 30s**: migrate to v2. See the recipe above. Migration is mandatory for any Agent that has rotated its key.

## Migration recipe

See [02-authentication.md §5.8](../02-authentication.md#5.8) for the full v1 → v2 migration recipe. Three steps:

1. Upgrade `@jecpdev/sdk` to `0.7.0` or later.
2. Replace `computeProvenanceV1(...)` with `computeProvenanceV2({ apiKey, agentId })`.
3. Confirm — issue one call, expect `200 OK`. If you get a `clock_skew` subcause, sync NTP.

## Sunset schedule

| Date | What changes |
|------|-------------|
| 2026-05-10 | v2 stable. v1 deprecated. SDKs ship `computeProvenanceV2`. |
| 2026-08-01 | Hubs MUST attach `Deprecation: true` + `Sunset: ...` response headers when v1 is accepted. Treat these headers as the migration alarm. |
| 2026-11-01 | v1 verifier removal. Hubs MUST reject v1 wire format with `PROVENANCE_MISMATCH` + `subcause: v1_legacy_mismatch` (or `v1_unavailable`). |
