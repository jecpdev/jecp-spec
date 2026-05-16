# JECP v1.0 Conformance Suite — INDEX

This directory holds the machine-runnable conformance suite for JECP v1.0. Every normative MUST / SHOULD in the spec maps to at least one assertion file here.

## Format

Each assertion is a single YAML file at `conformance/v1.0/<id>.yaml` with the schema:

```yaml
id:           JECP-<AREA>-<LEVEL>-<NUMBER>     # e.g., JECP-WIRE-MUST-415
level:        MUST | SHOULD | MAY               # RFC 2119 keyword
spec_section: "<doc>.md §<n>"                   # source citation
description:  "<one-sentence assertion>"
request:
  method:     GET | POST | ...
  path:       /v1/<endpoint>
  headers:    { ... }                           # optional
  body:       "..."                             # optional, raw string
expected:
  status:     <int>
  headers:    { <name>: { present: true, ... } } # optional
  body_jsonpath:                                # optional
    - { path: "$.error.code", equals: "<code>" }
```

The runner is `scripts/jecp-conformance.sh` (Phase 0 / c10) — a bash + python3 harness that walks this directory, executes each assertion against `${TARGET}` (default `https://jecp.dev`), and emits JUnit XML + Markdown report. The same logic ships as `npx @jecpdev/conformance` and `docker run ghcr.io/jecpdev/conformance:v1.x` in Phase 2.

## Status

This directory is **scaffolded** in spec v1.0.2-rc2 (commit aligning with `docs/jecp/PATH-TO-NO1.md` Phase 0). Assertion bodies land in Phase 0 / commit 10:

- Wire-format MUSTs (K2): 5 assertions for v1.0.2 (415 / 409 / 410 / Retry-After / 400 INPUT_SCHEMA_VIOLATION)
- Discovery MUSTs (K4): 1 assertion for `/.well-known/agent-guide.json`
- Bulkhead MUSTs (K3): 1 assertion for read-pool isolation
- Idempotency MUST (§5): 1 assertion for cache-key inclusion of `provenance_hash`
- Provenance v2 MUSTs: 13 assertions sourced from `fixtures/provenance-v2-vectors.json`

Until those YAML files land, treat this INDEX as a **forward reference only** — the §8 binding "Coverage policy" in `docs/jecp/phase0-locked-design.md` is honored when c10 lands.

## Assertion ID grammar

```
JECP-<AREA>-<LEVEL>-<NUMBER>

AREA   = WIRE | AUTH | PROV | DISCOVERY | OPS | META | BILLING | STREAM | COMPOSITE | PROVIDER
LEVEL  = MUST | SHOULD | MAY
NUMBER = zero-padded sequence within (AREA, LEVEL), e.g., 001, 002
```

Examples (for v1.0.2):
- `JECP-WIRE-MUST-415` — Content-Type ≠ application/json → 415
- `JECP-WIRE-MUST-409-DUP-SAME` — same id + same input replay → 409
- `JECP-WIRE-MUST-409-DUP-DIFFERENT-INPUT` — same id + different input → 400 INVALID_REQUEST (negative case)
- `JECP-WIRE-MUST-410-SUNSET` — sunset capability → 410 + Sunset header
- `JECP-WIRE-MUST-429-RETRY-AFTER` — burst → 429 + Retry-After ∈ [1, 600]
- `JECP-WIRE-MUST-400-INPUT-SCHEMA` — input violates manifest input_schema → 400 INPUT_SCHEMA_VIOLATION
- `JECP-DISCOVERY-MUST-001` — `/.well-known/agent-guide.json` returns 200 + valid schema
- `JECP-OPS-MUST-BULKHEAD-ISOLATION` — read-pool saturation does not starve invoke-pool
- `JECP-PROVIDER-MUST-REGISTER-REJECTS-INVALID-NAMESPACE` — namespace pattern violation → 400 INVALID_NAMESPACE
- `JECP-PROVIDER-MUST-REGISTER-REJECTS-HTTP-SCHEME` — endpoint_url scheme ≠ https → 422 URL_BLOCKED_SSRF
- `JECP-PROVIDER-MUST-REGISTER-REJECTS-PRIVATE-IP` — endpoint_url resolves to RFC1918 → 422 URL_BLOCKED_SSRF
- `JECP-PROVIDER-MUST-REGISTER-REJECTS-UNSUPPORTED-COUNTRY` — country ∉ Stripe Connect set → 400 UNSUPPORTED_COUNTRY
- `JECP-PROVIDER-MUST-AUTH-REQUIRED` — anonymous /v1/providers/{me, verify-dns, me/rotate-key} + /v1/manifests → 401/403
- `JECP-PROVIDER-MUST-MANIFEST-VALIDATES-SCHEMA` — empty actions array → 400 (validates against manifest.schema.json)

## Coverage policy (mirror of `docs/jecp/phase0-locked-design.md` §8)

Before any v1.x.y final tag (excluding `-rc` candidates):

- Every NEW JecpErrorCode variant MUST have ≥1 unit test + ≥1 e2e + ≥1 conformance YAML here.
- Every NEW spec MUST sentence MUST map to ≥1 conformance YAML at level=MUST.
- All conformance assertions MUST PASS against the reference Hub (`https://jecp.dev`) before tag.

This policy is unimplementable until c10 lands; `-rc` tags are exempt while assertions are being authored.
