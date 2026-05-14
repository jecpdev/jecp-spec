# ADR-0005: Cert pin downgrade (MUST → SHOULD) in v1.1.0 — errata

> **TL;DR**: v1.1.0 §6.1 was published with TLS certificate pinning as a MUST. The reference Rust Hub implementation discovered that wiring a custom `ServerCertVerifier` on `reqwest`'s default-tls backend is structurally blocked — it requires migrating to `rustls`-direct, a ~2-day spike with downstream HTTP client surface changes. Rather than block GA, this errata downgrades cert pinning from MUST to SHOULD for v1.1.0, makes Ed25519 body-signature pinning the primary integrity defense (already MUST), and commits to full cert-pin enforcement in v1.1.1.

## Status

**Resolved in v1.1.1** (2026-05-13). Originally Accepted 2026-05-11 as an errata to spec §6.1 of `06-x402-integration.md` v1.1.0. v1.1.1 ships full enforcement via a custom rustls `ServerCertVerifier`; see "Resolution" below.

## Context

The v1.1.0 trust model (§6.1) listed three independent integrity defenses for the Hub↔Facilitator channel:

1. URL pinned at boot + SSRF guard
2. TLS certificate pinned by SPKI SHA-256 (MUST)
3. Ed25519 signature pinned for every response body (MUST)

Implementation-side, three discoveries pushed the cert pin from "MUST in v1.1.0" to "SHOULD now, MUST in v1.1.1":

- **reqwest + native-tls cannot install a custom `ServerCertVerifier`.** The crate's default-TLS backend (rustls or native-tls depending on platform) does not expose verifier injection through the public API. `with_custom_certificate_verifier` exists only on the `rustls`-direct API (`rustls::ClientConfig`).
- **Switching reqwest to `rustls-tls-manual-roots`** is feasible but requires recompiling with `--no-default-features`, manually wiring webpki roots, and re-validating against Coinbase facilitator's actual cert chain. Not a 1-line change.
- **The Ed25519 body-signature pin already catches the relevant threat for v1.1.0.** An attacker who hijacks DNS for `x402.org` AND procures a valid TLS cert (via DV mis-issuance or ACME race) still cannot forge the Ed25519 signature on response bodies — they don't hold the pinned private key. The double-compromise required to defeat both defenses (TLS cert + Ed25519 key) is a higher bar than v1.1.0's threat model assumed.

What cert pinning catches that Ed25519 verify does not: an attacker who **also** steals the facilitator's Ed25519 private key would now slip through if cert pinning is absent — the body-sig pin reduces to a no-op. This is a real degradation: v1.1.0 ships with two defenses instead of three. The risk is bounded by Coinbase's Ed25519 key lifecycle, which has not historically rotated in production.

Cure53-style audit verdict (Panel B): "cert pinning is shipped as a no-op (TM-S2). Documented control not enforced — would not pass Stripe / Cloudflare release engineering." Panel B recommended either (a) wire rustls before GA OR (b) downgrade the MUST. This ADR records the choice of (b) with a v1.1.1 commitment.

## Decision

1. **§6.1 item 3 (cert pin) is downgraded from MUST to SHOULD in v1.1.0.** Conformance assertion `X402_CERT_PIN_ENFORCED` is marked "v1.1.1" in the v1.1 conformance pack and is not blocking for v1.1.0 GA.
2. **§6.1 item 4 (Ed25519 body-sig pin) remains MUST.** This is the primary integrity defense in v1.1.0.
3. **Reference Hub MUST emit a `tracing::warn!` at boot** when `JECP_X402_FACILITATOR_CERT_PIN` is configured but not enforced. Operators must see this in their logs (Better Stack / equivalent) so the gap is not silent.
4. **v1.1.1 target**: migrate `FacilitatorClient` to `rustls`-direct with a custom `ServerCertVerifier` that compares the leaf cert's SPKI SHA-256 against the pinned value. Target ship: v1.1.0 GA + 30 days.
5. **Coinbase facilitator key rotation procedure**: until cert pin lands, the operator runbook (`docs/operations/x402-facilitator-rotation.md`) MUST document the Ed25519 pubkey rotation procedure — Better Stack alert source watching `subcause = signature_pin_mismatch` lines is the canary.

## Consequences

### Positive

- v1.1.0 ships on schedule with the protocol surface complete (wire format, error codes, billing.x402, agent-guide.json, kill switch, reconciler, SSRF guard at boot).
- Implementations on stacks other than Rust (Go, Node) are no longer forced to fight their HTTP client's TLS layer at v1.1.0 — they can ship Ed25519 verify in week 1 and add cert pin in v1.1.1.
- The threat that cert pinning uniquely closes (concurrent compromise of Ed25519 key + TLS cert) is bounded and documented, not hidden.

### Negative

- A single-source-of-failure window opens on the Ed25519 private key for the v1.1.0 → v1.1.1 transition (~30 days). Mitigation: quarterly rotation cadence (already in Coinbase's operator runbook); alerting on `signature_pin_mismatch`.
- Stripe / Cloudflare-style audit firms reading "cert pin MUST" in the spec but seeing it as a no-op in the reference Hub would flag it. This ADR records the gap so audit firms can verify the downgrade is documented.
- v1.1.1 must ship within 30 days or the bounded risk window grows. Operator runbook tracks this with a calendar reminder.

## Implementation Notes

Reference Hub (Rust):

- `jecp/src/services/x402_facilitator.rs:11-17` — module doc records the deferred state.
- `jecp/src/services/x402_facilitator.rs:50-57` — `cert_pin_sha256: [u8; 32]` field is parsed + validated to be 32 bytes; `#[allow(dead_code)]` annotation marks it as unwired.
- `jecp/src/config.rs::X402Config::from_env` — emits `tracing::warn!("cert_pin_sha256 stored but not enforced — see ADR-0005")` at boot when x402 is enabled.

v1.1.1 implementation plan:

1. Add `rustls = "0.23"` (or matching version) as a direct dep.
2. Replace `reqwest::Client::builder().https_only(true).build()` with a `reqwest::ClientBuilder::use_preconfigured_tls(rustls_config)` where `rustls_config` is built via `ClientConfig::builder().with_custom_certificate_verifier(...)`.
3. Custom verifier implements `rustls::client::danger::ServerCertVerifier::verify_server_cert` — extracts the leaf cert's SPKI, computes SHA-256, compares against `cert_pin_sha256`. Mismatch → return `Error::InvalidCertificate(CertificateError::BadEncoding)` mapped to `X402Error::FacilitatorUnreachable { subcause: "cert_pin_mismatch", ... }`.
4. Test with a wiremock-rs server using a self-signed cert; assert that pin mismatch produces the canonical error envelope.

## Resolution (v1.1.1, 2026-05-13)

H-1 ships in Hub Rust v1.1.1. The custom `ServerCertVerifier` is implemented in `jecp/src/services/x402_cert_pin.rs` (~340 LOC including hand-rolled DER walker + tests) and wired into `FacilitatorClient::new()` via `reqwest::ClientBuilder::use_preconfigured_tls(rustls::ClientConfig)`.

### Approach

1. **Direct rustls dep, no new transitive bloat.** `rustls 0.23.36` and `webpki-roots 0.26.11` were already in the dep tree transitively via `sqlx-postgres → rustls`. Adding them as direct deps in `jecp/Cargo.toml` added zero new transitive crates and zero binary-size delta. Switching the facilitator client (and *only* the facilitator client — other reqwest clients remain on native-tls) was done by adding the `rustls-tls` feature to `reqwest` and calling `.use_preconfigured_tls(...)` per-builder rather than globally.

2. **Custom verifier delegates standard chain validation to `WebPkiServerVerifier`** (Mozilla trust roots from `webpki-roots`), then asserts SPKI SHA-256 match. Both checks must pass; failing webpki returns the standard webpki error (preserves operator diagnosability for legitimate cert problems), failing the SPKI pin returns `TlsError::General("x402: SPKI pin mismatch ...")` which `FacilitatorClient` maps to the canonical `X402_FACILITATOR_UNREACHABLE` envelope with `details.subcause = "cert_pin_mismatch"`.

3. **Hand-rolled DER walker for SPKI extraction** (~80 LOC). Avoids adding `x509-parser` (~250 KB) or `x509-cert` family (~200 KB + transitive `der`/`spki`/`asn1` crates). The walker navigates `Certificate.tbsCertificate.subjectPublicKeyInfo` by skipping the preceding TBSCertificate fields (handling both v1 certs without the `[0] EXPLICIT version` tag and v3 certs with it), then takes the SPKI SEQUENCE TLV bytes and SHA-256s them. Tests cover both v1/v3 forms, truncation, non-SEQUENCE input, and long-form length encoding.

4. **Constant-time compare** via the `subtle` crate (already in tree transitively via `bcrypt` / `ed25519-dalek`).

### Backward compatibility

When `X402_FACILITATOR_CERT_PIN` is the all-zeros sentinel (`0000…0000`), `FacilitatorClient::new()` falls back to the default rustls validation path — existing v1.1.0 deploys that have the env var set structurally but have not yet provisioned a real SPKI hash continue to work without breaking. A loud `tracing::warn!` at boot from `X402Config::from_env` flags the gap so operators see it in Better Stack / equivalent. The v1.1.0 unconditional "stored but not enforced" warning has been removed; it is replaced by the conditional zero-sentinel warning.

### Verification

- 16 new tests in `services::x402_cert_pin::tests` and `services::x402_facilitator::tests`: SPKI extraction for v1/v3 certs, truncation rejection, pin match / mismatch, zero-pin sentinel detection, verifier construction (proves rustls/webpki-roots wiring), TlsConfig error variant round-trip, cert-pin marker string stability.
- Full `cargo test --bin jecp`: 203/203 pass.
- Conformance assertion `X402_CERT_PIN_ENFORCED` upgrades from `SHOULD` (v1.1.0 deferred) to `MUST` (v1.1.1 enforced).

### Ship

Hub Rust v1.1.1, this PR. Commit hash to be added by admiral on merge.

## References

- Spec: `spec/06-x402-integration.md` §6.1
- Audit: `docs/jecp/x402-design/postimpl/audit-B-security.md` §1.2 (TM-S2)
- Audit: `docs/jecp/x402-design/postimpl/audit-A-protocol.md` §1.1.A-M7
- Implementation: `jecp/src/services/x402_cert_pin.rs`, `jecp/src/services/x402_facilitator.rs`
- rustls docs: https://docs.rs/rustls/latest/rustls/client/danger/trait.ServerCertVerifier.html
- reqwest issue tracking custom verifier: https://github.com/seanmonstar/reqwest/issues/1119
