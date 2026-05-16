# JECP v1.1 Conformance Suite — INDEX

This directory holds the machine-runnable conformance suite for the x402 integration layer of JECP (spec/06-x402-integration.md). Every normative MUST in §6 maps to at least one assertion file here.

## Format

Each assertion is a single YAML file at `conformance/v1.1/<id>.yaml` with a self-contained schema (preconditions / steps / expect / postconditions / failure_action / rationale). Fixture JSON blobs live alongside the YAMLs (see "Fixtures" below). Format basis: `docs/jecp/x402-design/panel-2-threat.md` §6.1 in the reference Hub repo.

Fixture references inside YAMLs:
- `${fixtures.x402.<name>}` — placeholder consumed by the conformance harness, resolved from the JSON files in this directory.
- `conformance/v1.1/fixtures/<file>` — direct relative path (used by the rc3 keeper assertions for `idempotency-pull-event.json` and `facilitator-fleet-eoas.txt`). Both fixtures are committed as PLACEHOLDER (2026-05-16) — `idempotency-pull-event.json` uses a deterministic `tx_hash` and a `${TEST_AGENT_EOA}` substitution placeholder for `payer`; `facilitator-fleet-eoas.txt` lists known operators behind `#`-prefixed comment lines pending BaseScan verification (see `feedback_verify_facilitator_on_chain.md` in the JobDoneBot release-prep notes). The harness MAY run the YAMLs that reference them, but the keeper batch is only declared "runnable for GA gate" once the comment-only EOA lines are uncommented after on-chain verification.

## Assertion list

### Discovery / wire-format
- `X402_AGENT_GUIDE_DISCLOSES_X402.yaml` — `/.well-known/agent-guide.json` advertises x402 when configured (MUST)
- `X402_PAYMENT_METHODS_FIELD_OPTIONAL.yaml` — `payment_methods` array is optional but valid when present
- `X402_PAYMENT_RESPONSE_HEADER.yaml` — successful x402 invoke returns `X-Payment-Response` header
- `X402_WWW_AUTHENTICATE_HEADER.yaml` — 402 challenge sets `WWW-Authenticate` correctly
- `X402_CACHE_CONTROL_NO_STORE.yaml` — x402-bearing responses set `Cache-Control: no-store`
- `X402_CORS_EXPOSE_HEADERS.yaml` — CORS exposes `X-Payment-Response` to browsers
- `X402_SUNSET_HEADER_PRESENT.yaml` — sunset capabilities advertise `Sunset` header
- `X402_OLD_SDK_GRACEFUL_DEGRADE.yaml` — pre-x402 SDK clients degrade gracefully
- `X402_SPLITTER_ADDRESS_IN_PAYTO.yaml` — `pay_to` field in 402 challenge equals Splitter address

### Verify / settle / payment validation
- `X402_VERIFY_BEFORE_SETTLE.yaml` — verify step MUST complete before settle is attempted
- `X402_AMOUNT_MISMATCH_REJECTED.yaml` — amount drift between header and challenge rejected
- `X402_NONCE_REUSE_REJECTED.yaml` — replayed nonce rejected
- `X402_TX_HASH_REUSE_REJECTED.yaml` — replayed tx hash rejected at verify time
- `X402_RESPONSE_SIG_VERIFIED.yaml` — facilitator response signature verified by Hub
- `X402_CERT_PIN_ENFORCED.yaml` — facilitator TLS cert pin enforced

### Facilitator failure modes
- `X402_FACILITATOR_TIMEOUT_GRACEFUL.yaml` — facilitator timeout returns deterministic error code, no leak
- `X402_KILL_SWITCH_HALTS_NEW.yaml` — operator kill-switch blocks new x402 invokes
- `X402_KILL_SWITCH_PRESERVES_WALLET.yaml` — kill-switch leaves wallet fallback path intact
- `X402_REFUND_RATE_LIMIT_ENFORCED.yaml` — refund endpoint rate-limit enforced per agent

### Reconciler / observability
- `X402_RECONCILER_CHAIN_CONFIRM.yaml` — reconciler upgrades `facilitator_attested` → `chain_confirmed` on N confirmations
- `X402_RECONCILER_MISMATCH_FLAGGED.yaml` — amount/payer mismatch between DB and chain raises drift alert
- `X402_RECONCILER_ORPHAN_DETECTED.yaml` — chain settlement with no matching DB row raises orphan alert

### rc3 keeper assertions (ADR-0003 Am-7, 2026-05-16) — NEW in v1.1

These five assertions cover the rc3 trust-root redesign: AUTHORIZED_SETTLER is the Hub-operated keeper (KMS-backed), facilitator is trust-minimized. See `spec/v1.1.0-rc3-errata.md` for the full motivation.

| Assertion | Purpose | Severity |
|---|---|---|
| `X402_HUB_KEEPER_AUTHORIZED_SETTLER_MATCH.yaml` | Positive trust-root — keeper EOA matches Splitter AUTHORIZED_SETTLER | critical |
| `X402_FACILITATOR_NOT_TRUSTED_AS_SETTLER.yaml` | Negative trust-root — facilitator fleet cannot call recordSettlement | critical |
| `X402_RECORD_SETTLEMENT_IDEMPOTENT.yaml` | Idempotency on (chain_id, tx_hash, log_index) — Sprint 12 P0 #1 locked | critical |
| `X402_RECORD_SETTLEMENT_LATENCY_BOUND.yaml` | Liveness — p99 ≤ 30s for keeper recordSettlement | high |
| `X402_AMOUNT_ATTRIBUTION_INVARIANT.yaml` | Invariant I-7 — chain ≡ DB ≡ ledger amount agreement | critical |

## Fixtures

JSON fixtures resolved via `${fixtures.x402.<name>}`:

- `manifest-minimal-valid.json` — smallest valid x402-capable manifest
- `provenance-v2-vectors.json` — provenance v2 test vectors
- `x402-happy-path-pure.json`, `x402-happy-path-wallet-fallback.json`
- `x402-error-facilitator-unreachable.json`, `x402-error-not-accepted.json`, `x402-error-payment-invalid.json`, `x402-error-settlement-reused.json`, `x402-error-settlement-timeout.json`

Fixture files referenced by path (rc3 keeper batch — committed 2026-05-16, PLACEHOLDER pending verification):

- `conformance/v1.1/fixtures/idempotency-pull-event.json` — deterministic pull-event fixture for replay test (PLACEHOLDER `payer` uses `${TEST_AGENT_EOA}` substitution)
- `conformance/v1.1/fixtures/facilitator-fleet-eoas.txt` — observed facilitator EOA list (Coinbase x402 Facilitator 1-8, Canza, Daydreams, X402rs, plus newly-observed entries). All entries currently `#`-commented; uncomment after BaseScan verification per `feedback_verify_facilitator_on_chain.md`.

## Coverage policy

The five rc3 keeper assertions are part of the v1.1.0 GA gate. Per `RC3-GA-GATE-CHECKLIST` §1.2 in the reference Hub, all five MUST PASS against the dogfeed Hub for 7 consecutive days before the v1.1.0 final tag.
