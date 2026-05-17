# `ROTATION_24H_CAP`

> Public URL: https://jecp.dev/errors/rotation_24h_cap
> Spec source: `spec/03-errors.md` §3.9 + `spec/04-manifest.md` §8.6.3
> Last updated: 2026-05-17

## What it means

The caller invoked `POST /v1/agents/me/rotate-key` or `POST /v1/providers/me/rotate-key` but has already rotated the maximum number of times allowed in a sliding 24-hour window (default 3). The request has NO effect — the existing api_key remains unchanged.

HTTP status: `429 Too Many Requests`.

This code fires only on the rotation self-service endpoints. Regular `POST /v1/invoke` traffic never sees it.

## Response envelope

```json
{
  "jecp": "1.0",
  "status": "failed",
  "error": {
    "code": "ROTATION_24H_CAP",
    "message": "Rotation limit exceeded (3 rotations in the last 24 h). Wait for the oldest rotation to age out before rotating again. If you suspect compromise, contact hello@jecp.dev to revoke immediately."
  }
}
```

The reference Hub emits the cap value in the `error.message`. Per spec §3.9, conformant Hubs SHOULD additionally attach a `Retry-After` header and a `details.next_slot_at` RFC 3339 timestamp; check `error.details` and the response headers and fall back to message parsing if absent.

## Fix in 30s

### Wait for the next slot

The window is sliding, not fixed: the cap counts the last 24h from the moment the request fires. If you rotated three times in the last 6 hours, the oldest rotation ages out 18 hours from now and the next slot opens then.

The Hub's audit log shows your recent rotations:

```bash
jecp audit rotations --limit 10
```

The exact `next_slot_at` is in `details.next_slot_at` when the Hub emits it. Otherwise, count back: the rotation 24h before `now` ages out at `now + (24h - age_of_oldest_in_window)`.

### If you suspect compromise

If you've burned three rotations because you think a key is leaked and you need to keep rotating to evict an attacker — stop rotating and email `hello@jecp.dev`. The Hub operator can revoke immediately via the admin path; rotation is the self-service path and is deliberately capped to prevent attacker-driven rotation loops.

### If you're hitting the cap during normal development

Three rotations per day is generous for production. If you're hitting it during dev:

- You're probably running `rotate-key` from a CI loop that fires on every commit. Move it to a manual / approval-gated workflow.
- You may be rotating to recover from a "I lost the key" event repeatedly. Use a secret manager (1Password, Doppler, AWS Secrets Manager) so the key isn't lost between rotations.
- You may have two services racing on the same Agent and rotating each other out. Split into two Agents.

## Why a 24h cap

Without the cap, an attacker who has stolen an api_key can use the rotate endpoint to lock the legitimate owner out indefinitely — every time the owner rotates back, the attacker rotates forward. The 24h cap bounds that race: after three contended rotations, both sides have to wait, giving the legitimate owner time to escalate to the Hub operator.

The cap value (3 / 24h) is conservative. Operators MAY raise it via Hub config, but agents and Providers cannot override it client-side.

## Related errors

- `ROTATION_RACE` — concurrent rotation race lost (409). Different cause: not capped, just lost a row-lock.
- `INVALID_API_KEY` — wrong current key supplied to `rotate-key`.
- `DNS_VERIFICATION_FAILED` — different §3.9 code (DNS, not rotation).
