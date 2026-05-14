# JECP — x402 Integration

**Spec Version**: 1.1.0
**Status**: Stable (additive over v1.0.x)
**Companion**: 01-protocol.md, 03-errors.md, 04-manifest.md, 05-discovery.md
**ADRs**: [ADR-0003 — x402 Integration](../adr/0003-x402-integration.md), [ADR-0004 — Idempotency × x402](../adr/0004-idempotency-x402.md)

## 1. Abstract

This document defines the normative integration of [x402](https://x402.org) — Coinbase's HTTP 402 + USDC-on-Base micropayment protocol — as a **second, parallel payment path** on `POST /v1/invoke`. The existing pre-funded wallet path (01-protocol.md §4.1) remains unchanged and is the default. Capabilities opt in to x402 via the `payment_methods` manifest field (04-manifest.md). Hubs that do not configure an x402 facilitator remain v1.1.0-conformant — they simply never advertise x402 in any 402 response, and all error codes in this section remain dormant.

The protocol invariants are:

- The 402 challenge response carries an OPTIONAL `payment` sibling field on the existing error envelope (no new envelope shape).
- The agent retries with `X-Payment` (request header, base64-encoded x402 envelope, ≤8 KB).
- The Hub MUST verify the payment with its configured x402 facilitator BEFORE settlement.
- Settlement targets the JECP-deployed `JecpSplitter` smart contract on Base mainnet, which distributes 85% / 10% / 5% to (Provider / Hub treasury / Network reserve) **within a single Base block**. The canonical implementation is two transactions in the same block (~2 s apart): an `AUTHORIZED_SETTLER`-gated `recordSettlement(capabilityId, amount)` that updates an on-chain ledger, followed by an open `splitFor(capabilityId, payer)` that reads the ledger and distributes shares. The x402.org facilitator does not currently support a post-pull contract call within the same transaction; "atomicity" in this spec MUST be read as "single-block atomic", not "same-tx atomic". **The Hub holds no authorization key on the request hot path** — the Hub-controlled `RELAYER` is a gas-payer only (AWS KMS-signed; never plaintext), and on-chain capability registration is authorized by a Provider-held EIP-712 signature.
- The Hub returns `X-Payment-Response` (response header, base64-encoded settlement receipt) on every 2xx response that consumed an x402 payment.
- Old SDKs degrade gracefully: they ignore unknown response fields, never send `X-Payment`, and continue using the wallet path on capabilities that accept it.

## 2. Payment Requirements Response (the 402 envelope)

When a request to `POST /v1/invoke` requires payment and the resolved capability accepts x402, the Hub MUST return HTTP 402 with the existing JECP error envelope (03-errors.md §2) plus a sibling `payment` field that carries the x402 challenge. The error `code` MUST remain `PAYMENT_REQUIRED` (03-errors.md §3.4); a new variant MUST NOT be introduced for this case.

### 2.1 Wire shape

```http
HTTP/1.1 402 Payment Required
Content-Type: application/json
Cache-Control: no-store
Retry-After: 30
WWW-Authenticate: x402 realm="jecp.dev", network="base", asset="USDC"

{
  "jecp": "1.0",
  "id": "req_abc123",
  "status": "failed",
  "error": {
    "code": "PAYMENT_REQUIRED",
    "message": "Wallet balance 0.000 USDC < required 0.200 USDC. Top up the wallet, or settle this call directly with x402.",
    "details": {
      "required_usdc": 0.200,
      "remaining_usdc": 0.000,
      "subcause": "x402_or_wallet"
    },
    "documentation_url": "https://jecp.dev/errors/payment_required"
  },
  "payment": {
    "x402Version": 1,
    "accepts": [
      {
        "scheme": "stripe-wallet",
        "amount_usd": 0.20,
        "topup_url": "https://jecp.dev/account/topup?return=req_abc123"
      },
      {
        "scheme": "exact",
        "network": "base",
        "asset": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        "asset_symbol": "USDC",
        "asset_decimals": 6,
        "max_amount_required": "200000",
        "pay_to": "0xJECP_SPLITTER_CONTRACT_ADDRESS",
        "resource": "https://jecp.dev/v1/invoke",
        "description": "Payment for capability jobdonebot/bg-remover-pro",
        "mime_type": "application/json",
        "max_timeout_seconds": 60,
        "extra": {
          "name": "USD Coin",
          "version": "2",
          "splitter_capability_id": "0x<bytes32 capability id>",
          "facilitator_url": "https://x402.org/facilitator"
        }
      }
    ],
    "ttl_seconds": 30,
    "next_action": {
      "type": "x402_settle",
      "hint": "Construct an EIP-3009 transferWithAuthorization signature for the asset above, base64-encode the X-Payment envelope (see §3), and retry this request with the X-Payment header."
    }
  },
  "next_action": {
    "type": "topup",
    "ui": "https://jecp.dev/account/topup",
    "api": "https://jecp.dev/api/agents/topup",
    "method": "POST",
    "headers": ["X-Agent-ID", "X-API-Key"],
    "body_example": { "amount": 5 },
    "allowed_amounts_usd": [5, 20, 100],
    "alternative": "Or settle in-band via x402 — see `payment.next_action`."
  }
}
```

### 2.2 Field requirements

| Field | Required | Description |
|---|---|---|
| `payment.x402Version` | MUST | Integer literal `1` for x402 v1. Bumping requires a v1.x JECP minor release. |
| `payment.accepts` | MUST | Non-empty array of payment-requirement objects. Order is significant: see §2.3. |
| `payment.accepts[].scheme` | MUST | One of `"stripe-wallet"` (JECP-defined) or `"exact"` (x402 v1 — only x402 scheme accepted in v1.1.0). |
| `payment.accepts[].network` | MUST (for `exact`) | Lowercase token. v1.1.0 mandates `"base"` for production; `"base-sepolia"` MAY be used in test mode. |
| `payment.accepts[].asset` | MUST (for `exact`) | ERC-20 contract address (40-hex with `0x` prefix). Base mainnet USDC = `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`. |
| `payment.accepts[].max_amount_required` | MUST (for `exact`) | **Atomic units of the asset** as decimal string (USDC has 6 decimals → `"200000"` = 0.200 USDC). MUST NOT be a USD float. |
| `payment.accepts[].pay_to` | MUST (for `exact`) | EVM address — MUST be the JECP Splitter contract address (see §8). MUST NOT be a Hub-controlled EOA, MUST NOT be a Provider-controlled EOA. |
| `payment.accepts[].resource` | MUST | Absolute URL of the resource being accessed. Hubs MUST emit the canonical `/v1/invoke` URL. |
| `payment.accepts[].max_timeout_seconds` | MUST (for `exact`) | Maximum seconds the agent's signed authorization MAY remain valid. Hubs SHOULD emit `60`. |
| `payment.accepts[].extra.name` / `version` | SHOULD | EIP-712 domain separator fields. USDC uses `name="USD Coin", version="2"`. Required for facilitator signature verification. |
| `payment.accepts[].extra.splitter_capability_id` | MUST (for `exact`) | The 32-byte (`0x`-prefixed 64-hex) identifier of the capability's split registration in the Splitter contract. See §8.2. |
| `payment.accepts[].extra.facilitator_url` | MUST (for `exact`) | The facilitator URL the Hub will use for verification. Allows agents to optimize wallet pre-funding. |
| `payment.ttl_seconds` | MUST | Seconds the entire `payment` block remains valid. Hubs SHOULD emit `30`. |
| `payment.next_action` | SHOULD | Recovery hint per 03-errors.md §4. New `type` value: `"x402_settle"`. |
| `WWW-Authenticate` header | SHOULD | Standard HTTP challenge per RFC 7235. Allows non-JSON-aware clients to surface the requirement. |
| `Cache-Control: no-store` | MUST | Prevents CDN caching of paid challenge responses. |

### 2.3 `accepts[]` order

When both `stripe-wallet` and `exact` (x402) entries are present, the Hub MUST list `stripe-wallet` first. Rationale: Stripe is more recoverable (chargeback / dispute paths exist). This is a normative requirement to mitigate mode-confusion attacks (Panel 2 TM-MC: agents that misinterpret order may consume the wrong signed authorization). x402-native positioning lives in marketing surfaces, not in protocol field order.

Capabilities that omit `payment_methods` from their manifest (default `["stripe"]`) MUST emit only the `stripe-wallet` entry. Capabilities that declare `payment_methods: ["x402"]` MUST emit only the `exact` entry. Capabilities that declare `payment_methods: ["stripe", "x402"]` MUST emit both, in the order above.

### 2.4 Negotiation matrix

When the agent later retries `/v1/invoke` (with or without `X-Payment`), the Hub's path-selection rule is:

| Capability `payment_methods` | Agent sent `X-Payment` | Hub action |
|---|---|---|
| `["stripe"]` (or omitted) | No | Wallet path. |
| `["stripe"]` (or omitted) | Yes | HTTP 422 `X402_NOT_ACCEPTED`. Hub MUST NOT consume the signed authorization. |
| `["stripe", "x402"]` | No | Wallet path. On insufficient balance → 402 with both methods. |
| `["stripe", "x402"]` | Yes | x402 path. Wallet untouched. |
| `["x402"]` | No | 402 with x402-only `accepts[]`; `next_action.type = "x402_settle"`. |
| `["x402"]` | Yes | x402 path. |

The Hub MUST select exactly one payment path per request. Submitting both `Authorization`/wallet credentials AND `X-Payment` MUST NOT result in dual-charge — the Hub MUST treat `X-Payment` as the authoritative selector and ignore wallet deduction for that request.

## 3. X-Payment Request Header

When an agent settles a call via x402, it MUST send:

```
X-Payment: <base64(JSON-utf8(payload))>
```

Where `payload` is the canonical x402 v1 envelope:

```json
{
  "x402Version": 1,
  "scheme": "exact",
  "network": "base",
  "payload": {
    "signature": "0x<130-hex-chars>",
    "authorization": {
      "from":        "0x<40-hex>",
      "to":          "0x<Splitter address>",
      "value":       "200000",
      "validAfter":  "1762689600",
      "validBefore": "1762689660",
      "nonce":       "0x<64-hex>"
    }
  }
}
```

The inner `payload.authorization` object is the EIP-3009 `transferWithAuthorization` parameters — the standard meta-transaction primitive that USDC supports natively. The agent constructs this off-chain, signs it with the wallet that owns `from`, and hands it to the Hub.

### 3.1 Encoding requirements

The agent MUST:

1. Construct the JSON object above. Hubs MUST tolerate any key order per RFC 8259.
2. Serialize as UTF-8 with NO trailing newline, NO BOM.
3. Base64-encode using **standard alphabet with padding** (RFC 4648 §4, NOT URL-safe).
4. Set as `X-Payment: <base64-string>` request header. Single-line, no whitespace inside the value.

### 3.2 Size constraint

Hubs MUST reject any `X-Payment` header longer than **8 KB** (well above the ~600-byte typical envelope; bounds DoS via header floods). On exceed: HTTP 422 `X402_PAYMENT_INVALID` with `details.subcause = "header_too_large"`.

### 3.3 Header normalization

Hubs MUST normalize the header name to lowercase before lookup. Hubs MUST reject requests that present multiple `X-Payment` headers (any case-folded variant) with HTTP 422 `X402_PAYMENT_INVALID` and `details.subcause = "duplicate_payment_header"`. Rationale: header confusion (`X-Payment` vs `x-payment` vs `X-PAYMENT`) is a smuggling vector across the proxy / Hub framework boundary (Panel 2 TM-S5).

### 3.4 Idempotency interaction

See ADR-0004. The Hub's idempotency cache key MUST include both the existing `mandate.provenance_hash` (per ADR-0001) AND the SHA-256 of the `X-Payment` payload (when present), AND the resulting settlement `tx_hash` (when known). Two requests with the same `(agent_id, request_id)` and a *different* `X-Payment` MUST return HTTP 409 `DUPLICATE_REQUEST`. Two requests with the same `(agent_id, request_id)` and the *same* `X-Payment` MUST return the cached response without re-calling the facilitator and without re-charging.

## 4. Hub → Facilitator Interaction

The Hub MUST call the facilitator's `/verify` endpoint BEFORE calling `/settle`. This catches malformed signatures cheaply, before any on-chain commitment. A Hub MUST NOT call `/settle` without a successful `/verify` for the same payload.

### 4.1 Sequence

```
Agent ──POST /v1/invoke + X-Payment──▶ Hub
                                        │ 1. parse + validate X-Payment envelope (size, header normalization)
                                        │ 2. check x402_settlements (nonce / tx_hash uniqueness)
                                        │ 3. POST to facilitator: /verify  (cheap, ~50-100ms)
                                        │ 4. POST to facilitator: /settle  (on-chain, 1-3s on Base)
                                        │ 5. verify Ed25519 signature on facilitator response
                                        │ 6. forward to Provider; record settlement; emit X-Payment-Response
Agent ◀───────── 200 OK + X-Payment-Response ── Hub
```

### 4.2 `/verify` request

```http
POST /verify HTTP/1.1
Host: x402.org
Content-Type: application/json

{
  "x402Version": 1,
  "paymentPayload": {
    "x402Version": 1,
    "scheme": "exact",
    "network": "base",
    "payload": { /* same as X-Payment inner payload */ }
  },
  "paymentRequirements": {
    "scheme": "exact",
    "network": "base",
    "max_amount_required": "200000",
    "resource": "https://jecp.dev/v1/invoke",
    "pay_to": "0xJECP_SPLITTER_CONTRACT_ADDRESS",
    "asset": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    "extra": { "name": "USD Coin", "version": "2", "splitter_capability_id": "0x..." }
  }
}
```

Expected response:

```json
{ "isValid": true, "invalidReason": null, "payer": "0x<from-address>" }
```

If `isValid === false` the Hub MUST return HTTP 422 `X402_PAYMENT_INVALID` with `details.subcause` derived from `invalidReason` per the registry in 03-errors.md §3.8. The Hub MUST NOT call `/settle`.

### 4.3 `/settle` request

If `/verify` returned `isValid: true`, the Hub MUST call `/settle`:

```http
POST /settle HTTP/1.1
Host: x402.org
Content-Type: application/json

{
  "x402Version": 1,
  "paymentPayload":      { /* same as /verify */ },
  "paymentRequirements": { /* same as /verify */ }
}
```

Expected response:

```json
{
  "success": true,
  "errorReason": null,
  "transaction": "0x<64-hex tx hash>",
  "network": "base",
  "payer": "0x<from-address>"
}
```

### 4.4 Failure handling

| Facilitator response | Hub action |
|---|---|
| HTTP 200, `success: true` | Proceed to capability execution. Persist `tx_hash` for receipt + idempotency. |
| HTTP 200, `success: false`, `errorReason = "insufficient_funds"` | HTTP 422 `X402_PAYMENT_INVALID` `details.subcause = "insufficient_funds"`. |
| HTTP 200, `success: false`, `errorReason = "expired"` | HTTP 422 `X402_PAYMENT_INVALID` `details.subcause = "expired"`. |
| HTTP 200, `success: false`, other reasons | HTTP 422 `X402_PAYMENT_INVALID` with mapped subcause; see registry. |
| HTTP 5xx from facilitator | Retry once (50ms backoff). On second failure → HTTP 502 `X402_FACILITATOR_UNREACHABLE`. |
| Network timeout > 5s | HTTP 504 `X402_SETTLEMENT_TIMEOUT`. |
| Connection error / DNS fail | Retry once. On second failure → HTTP 502 `X402_FACILITATOR_UNREACHABLE`. |

Hubs MUST set both `Retry-After: 30` and `next_action` on `X402_SETTLEMENT_TIMEOUT` and `X402_FACILITATOR_UNREACHABLE` responses; the recovery hint SHOULD point the agent at the wallet (`stripe-wallet`) path as a fallback.

### 4.5 Atomicity

The Hub MUST treat `(settlement-succeeded + capability-executed + settlement-recorded)` as one logical unit. If capability execution fails after settlement succeeded:

1. Hub returns the original failure to the agent.
2. Hub records the orphaned settlement to `x402_settlements` with status `facilitator_attested`.
3. Hub initiates the manual refund flow (24h SLA): the agent contacts support; Hub absorbs the Provider's 85% share as opex and reimburses the agent the full gross.

Per ADR-0003, automated refund pools are deferred to v1.2; v1.1.0 mandates the manual SLA + per-agent rate limit (max 10 refunds / 24h / agent; 11th opens an investigation).

## 5. X-Payment-Response Response Header

On every 2xx response that consumed an x402 payment, the Hub MUST emit:

```
X-Payment-Response: <base64(JSON-utf8(receipt))>
```

Where `receipt` is:

```json
{
  "success":     true,
  "transaction": "0x<settlement tx hash>",
  "network":     "base",
  "payer":       "0x<from address>"
}
```

Hubs MUST add `X-Payment-Response` to `Access-Control-Expose-Headers` on every CORS-eligible response. Browsers strip non-default response headers from JS access by default; without this exposure, browser-based agents cannot read the receipt.

### 5.1 Body mirror

The same data MUST also appear in the response body's `billing.x402` sub-object for clients that do not read response headers:

```json
{
  "jecp": "1.0",
  "id": "req_abc123",
  "status": "completed",
  "result": { /* ... */ },
  "billing": {
    "method": "x402",
    "cost_usdc": 0.20,
    "transaction_id": "<JECP UUID for the x402_settlements row>",
    "x402": {
      "settlement_tx": "0x<64-hex>",
      "network": "base",
      "payer": "0x<40-hex>",
      "facilitator": "https://x402.org/facilitator"
    }
  },
  "execution": { /* ... */ }
}
```

`billing.method` becomes a discriminator over the open enum `"wallet" | "x402" | "free_call" | "mandate"`. Adding `"x402"` is a minor-version-safe extension per 03-errors.md §7.

### 5.2 Cache-Control

Settled responses MUST emit `Cache-Control: no-store`. A cached x402-settled response replayed from a CDN would deliver the result without a second settlement; the Hub's idempotency cache prevents this on its own server, but no part of the spec currently bars CDN caching, and a misconfigured edge is one Cloudflare Page Rule away from a paid-call leak.

## 6. Trust Model

### 6.1 Single-facilitator + cert pin + Ed25519 (v1.1.0 / v1.1.1)

v1.1.0+ conformant Hubs configured to support x402 MUST:

1. Pin the facilitator URL at boot via operator-controlled environment variable (e.g., `JECP_X402_FACILITATOR_URL`). The URL MUST NOT be agent-controllable.
2. Pass the facilitator URL through the composite SSRF defense (ADR-0002 / 02-authentication.md §9.7.1) at boot. If the URL fails the pipeline (resolves to a deny CIDR, scheme ≠ `https`, etc.) the Hub MUST refuse to start.
3. Pin the facilitator's Ed25519 response signing public key (e.g., `JECP_X402_FACILITATOR_PUBKEY`). Verify the signature on every `/verify` and `/settle` response body before trusting any field. Mismatch = HTTP 502 `X402_FACILITATOR_UNREACHABLE` with `details.subcause = "signature_pin_mismatch"`.

v1.1.1+ conformant Hubs MUST (downgraded to SHOULD in v1.1.0 only; restored to MUST in v1.1.1 per ADR-0005 resolution):

4. Pin the facilitator's TLS certificate by SPKI SHA-256 (e.g., `JECP_X402_FACILITATOR_CERT_PIN`) and enforce the pin inside a custom TLS verifier that runs **after** standard chain validation. Mismatch at TLS handshake = abort + alert + emit HTTP 502 `X402_FACILITATOR_UNREACHABLE` with `details.subcause = "cert_pin_mismatch"`. The reference Rust implementation (Hub v1.1.1+) installs a `rustls::client::danger::ServerCertVerifier` that delegates to `WebPkiServerVerifier` for chain/hostname/expiry, then compares the leaf cert's SPKI SHA-256 against the pinned value with a constant-time check (see ADR-0005 Resolution + `jecp/src/services/x402_cert_pin.rs`). v1.1.0 Hubs that ship cert pin as SHOULD remain conformant to v1.1.0 only; v1.1.1+ Hubs MUST enforce.

Multi-facilitator quorum (Panel 2's preferred model) is **deferred to v1.2** per ADR-0003. v1.1.1's locked baseline is signature verify + cert pin enforced + reconciler + SSRF guard (see §6.3). See ADR-0005 for the full v1.1.0 → v1.1.1 history.

### 6.2 Reconciler

Conformant Hubs MUST run a background task that, every ≤60 seconds, verifies all `facilitator_attested` settlements against the on-chain receipt via Base RPC (`eth_getTransactionReceipt`). State transitions:

- Receipt found, status = success, value/recipient match → mark `chain_confirmed`.
- Receipt found, status = failure → mark `failed`; emit operator alert; queue refund.
- Receipt not found after 10 minutes → mark `orphaned`; emit operator alert.
- Receipt found, but value/recipient/blockHash differ from facilitator attestation → mark `mismatched`; freeze any pending Provider payout; emit P0 alert.

The reconciler MUST be a supervised task (panic boundary; restart on crash). The reconciler MUST NOT share an HTTP client pool with the request-path facilitator client (bulkhead isolation).

### 6.3 Kill switch

Hubs MUST expose a runtime feature flag (e.g., `feature_flags.x402_enabled` row in the DB) that disables all x402 acceptance without redeploy:

- When `false`: `payment.accepts[]` MUST omit the `exact` (x402) entry on all 402 responses.
- When `false`: any `X-Payment` request MUST return HTTP 422 `X402_NOT_ACCEPTED` with `details.subcause = "x402_disabled"`.
- When `false`: the existing wallet path MUST remain operational and unaffected.

The flag flip MUST take effect within 60 seconds without a deploy. This is the operator's primary lever during a facilitator outage or compromise (Panel 2 TM-E3).

## 7. Capability Manifest Extension

04-manifest.md §5 (`Action.pricing`) gains one OPTIONAL field:

```yaml
actions:
  - id: bg-remover-pro
    pricing:
      base: "$0.20"
      currency: USD
      model: per_call
      payment_methods: ["stripe", "x402"]   # NEW; default ["stripe"] if omitted
```

### 7.1 Field definition

- **Type**: array
- **Required**: OPTIONAL (default `["stripe"]`)
- **Items**: enum, one of `"stripe" | "x402"`
- **Constraints**: `minItems: 1`, `uniqueItems: true`
- **Description**: Declares which payment methods this action accepts. New in v1.1.0. Hubs MUST honor the declaration; agents that present an unsupported method receive HTTP 422 `X402_NOT_ACCEPTED` (03-errors.md §3.8).

### 7.2 Examples

- `["stripe"]` — wallet only (default; matches v1.0 behavior, MUST be assumed when the field is absent).
- `["stripe", "x402"]` — both methods accepted; agent chooses. Recommended default for x402-aware Providers.
- `["x402"]` — x402 only; the Hub MUST NOT bill the wallet for this action.

### 7.3 Discoverability

`/v1/capabilities` and `/v1/capabilities/{id}` responses (05-discovery.md §6/§7) MUST include `payment_methods` per action when the manifest declares it. When absent in the manifest, Hubs SHOULD emit `["stripe"]` explicitly in the catalog for clarity, but MAY omit (clients MUST then assume `["stripe"]`).

`/.well-known/agent-guide.json` (05-discovery.md §4) gains a top-level OPTIONAL `payment_methods_supported` array enumerating which methods the Hub itself supports across its catalog. v1.1.0 reference Hubs SHOULD emit `["stripe", "x402"]` once the facilitator is configured.

## 8. Splitter Contract Integration

### 8.1 Architecture

x402 v1 specifies a single `payTo` address per challenge. To achieve single-block-atomic 85% / 10% / 5% revenue split without Hub authorization-key custody, JECP introduces an on-chain helper: the **`JecpSplitter` smart contract** on Base mainnet. The Splitter address replaces a Hub-controlled or Provider-controlled EOA in the `pay_to` field of every x402 challenge.

The Splitter is **immutable except for a single rotatable `relayer` address**; all other authorization roles, recipient addresses, and split state are immutable. The Hub-server process holds no signing key for any role on the contract — capability registration is authorized by a Provider-held EIP-712 signature, settlement is gated to an immutable `AUTHORIZED_SETTLER`, and the Hub-controlled `RELAYER` (a gas-payer only) is signed by AWS KMS.

The settlement flow is two on-chain calls in a single Base block:

1. The x402 facilitator pulls USDC into the Splitter via EIP-3009 `transferWithAuthorization`.
2. The `AUTHORIZED_SETTLER` calls `recordSettlement(capabilityId, amount)`, which updates an on-chain `accountedBalance[capabilityId]` ledger.
3. Anyone (typically the same `AUTHORIZED_SETTLER`, or the Hub's RELAYER, or even the agent) calls `splitFor(capabilityId, payer)`, which reads the ledger, zeroes it (CEI), and distributes shares. Hub treasury and Network reserve receive direct USDC transfers; the Provider share routes via try/catch — direct transfer on success, escrow on failure.
4. The Splitter emits `PaymentSplit(capabilityId, payer, amount, providerAmount, hubAmount, reserveAmount)` for off-chain audit and reconciliation.

The Hub's role on the request hot path is purely off-chain orchestration — verification, idempotency, and recording. No Hub-controlled private key signs any USDC transaction. The Hub's `RELAYER` key (AWS KMS-backed, see §8.5) signs only `register()` submission transactions at `POST /v1/manifests/{id}/promote` time (lazy-on-promote); it has no authority over capability state because the on-chain authorization comes from the Provider's EIP-712 signature carried inside the call.

### 8.2 Roles and immutability

The Splitter MUST be deployed with the following immutable constructor parameters:

| Role / parameter | Type | Purpose |
|---|---|---|
| `USDC` | `IERC20` (immutable) | Canonical Circle-issued USDC contract on Base mainnet (`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`). |
| `HUB_TREASURY` | `address` (immutable) | Gnosis Safe 2-of-3 multisig that receives the 10% Hub share. |
| `NETWORK_RESERVE` | `address` (immutable) | Gnosis Safe 2-of-3 multisig that receives the 5% Network reserve share. |
| `AUTHORIZED_SETTLER` | `address` (immutable) | The x402 facilitator's settlement contract address (or, if the facilitator uses an EOA, that EOA). The ONLY caller permitted to invoke `recordSettlement()`. |
| `RELAYER_ADMIN` | `address` (immutable) | Gnosis Safe 2-of-3 multisig with separation-of-duties from Treasury and Reserve signers. The ONLY caller permitted to invoke `setRelayer()`. |
| `PER_TX_CAP` | `uint256` (immutable) | Per-`recordSettlement` USDC ceiling in atomic units (e.g., `1_000_000_000` = $1000). Bounds blast radius if the facilitator misbehaves. |
| `EIP712_DOMAIN_SEPARATOR` | `bytes32` (immutable) | Bound to `chainId` and contract address at construction; prevents cross-chain and cross-contract signature replay. |

The single mutable storage slot is:

| Field | Type | Mutability |
|---|---|---|
| `relayer` | `address` (mutable, RELAYER_ADMIN-only via `setRelayer()`) | The Hub-controlled gas-payer key. The contract does NOT gate any authorization function on `msg.sender == relayer`; rotation is for operational hygiene (KMS key rotation) and is not load-bearing for security. |

### 8.3 Provider-signed capability registration (EIP-712)

Each x402-accepting capability MUST be registered on the Splitter **at `POST /v1/manifests/{id}/promote` time** (lazy-on-promote, NOT at every `publish`). Registration is authorized by a Provider EIP-712 signature recovered to the declared `provider` address; submission is open (typically performed by the Hub's RELAYER, which pays gas).

The Splitter exposes:

```solidity
function register(
    bytes32 capabilityId,
    address provider,
    uint16 providerBps,    // 8500 (= 85%)
    uint16 hubBps,         //  1000 (= 10%)
    uint16 reserveBps,     //   500 (=  5%)
    bytes32 nonce,         // Provider-chosen, single-use
    uint256 deadline,      // unix seconds
    bytes calldata providerSig
) external;
```

The triple `(providerBps + hubBps + reserveBps)` MUST sum to `10000` (basis points). The contract MUST revert if `block.timestamp > deadline`, if `usedNonces[nonce] == true`, if the capability is already active, or if EIP-712 signature recovery does not yield exactly the declared `provider` address.

The EIP-712 typehash MUST be:

```
Register(bytes32 capabilityId,address provider,uint16 providerBps,uint16 hubBps,uint16 reserveBps,bytes32 nonce,uint256 deadline)
```

The EIP-712 domain MUST be:

```
EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)
  name              = "JecpSplitter"
  version           = "1.1.1"
  chainId           = 8453   (Base mainnet) or 84532 (Base Sepolia)
  verifyingContract = <Splitter address>
```

The `bytes32 capabilityId` MUST be reproducible off-chain by both Hub and Provider for verification: `keccak256(utf8(provider_namespace + ":" + action_id))`.

Re-registration of an `active` capability MUST revert (`CapabilityAlreadyExists`). To change split parameters or the Provider address, the current Provider MUST first call `deactivate(capabilityId)` — gated to `msg.sender == cap.provider`; the RELAYER cannot deactivate. The Hub then collects a fresh Provider signature and submits a new `register()` call.

### 8.4 `recordSettlement` — settlement ledger

The Splitter exposes a single function for the facilitator's settlement helper to register that USDC has been pulled into the contract:

```solidity
function recordSettlement(bytes32 capabilityId, uint256 amount) external;
```

The contract MUST revert if:

- `msg.sender != AUTHORIZED_SETTLER` (`UnauthorizedSettler`),
- `amount == 0` (`AmountZero`),
- `amount > PER_TX_CAP` (`AmountExceedsCap`),
- `capabilities[capabilityId].active == false` (`CapabilityNotActive`).

On success, the contract MUST add `amount` to `accountedBalance[capabilityId]` and emit no event of its own (the corresponding `PaymentSplit` event from `splitFor()` carries the audit signal).

`recordSettlement` is the ONLY path that increments `accountedBalance`. The Splitter does not infer accounted balance from raw `USDC.balanceOf(this)` — opportunistic transfers (donations, mistaken sends, faucets) sit unaccounted and cannot be split.

### 8.5 `splitFor` — distribution

The Splitter exposes:

```solidity
function splitFor(bytes32 capabilityId, address payer) external;
```

`splitFor` is **permissionless on `msg.sender`** but it MUST be a no-op for any `capabilityId` whose `accountedBalance` is zero (`AmountZero` revert). The function MUST:

1. Read `cap = capabilities[capabilityId]`; revert `CapabilityNotActive` if `!cap.active`.
2. Read `amount = accountedBalance[capabilityId]`; revert `AmountZero` if zero.
3. Set `accountedBalance[capabilityId] = 0` BEFORE any external call (CEI).
4. Compute `providerAmount = amount * cap.providerBps / 10000`, `hubAmount = amount * cap.hubBps / 10000`, `reserveAmount = amount - providerAmount - hubAmount` (the residual absorbs rounding dust to preserve the invariant `providerAmount + hubAmount + reserveAmount == amount`).
5. Transfer `hubAmount` to `HUB_TREASURY` and `reserveAmount` to `NETWORK_RESERVE` directly. A revert on either of these MUST revert the entire call.
6. Attempt the Provider transfer via an external self-call wrapped in `try/catch` (see §8.6). On success the Provider receives a direct USDC transfer; on failure the share routes to `providerEscrow[provider]`.
7. Emit `PaymentSplit(capabilityId, payer, amount, providerAmount, hubAmount, reserveAmount)`.

`splitFor` does NOT accept a caller-supplied amount; the only source of truth is the on-chain ledger written by `recordSettlement`. This is the structural defense against the original draft's `SC-A1` Critical (permissionless drain via crafted amount).

### 8.6 Pull-pattern `withdraw` for griefed Providers

To prevent a single griefing Provider from blocking settlement for everyone (SC-A3 High), `splitFor` MUST attempt the Provider transfer via `try/catch`:

```solidity
try this._pushProvider(cap.provider, providerAmount) {
    // direct transfer succeeded
} catch {
    providerEscrow[cap.provider] += providerAmount;
    emit ProviderEscrowed(cap.provider, providerAmount, "push_failed");
}
```

The `_pushProvider` helper MUST be `external` (so it can be `try/catch`-wrapped) and MUST require `msg.sender == address(this)` to prevent direct invocation.

The Splitter MUST expose:

```solidity
function withdraw() external;
```

`withdraw()` MUST drain `providerEscrow[msg.sender]` to `msg.sender`, zero the slot before the transfer (CEI), revert `NoEscrowedFunds` if the slot is zero, and emit `ProviderWithdrew(provider, amount)`. The Provider may call this from any address it controls — recovery is self-service and requires no Hub action.

### 8.7 RELAYER rotation

```solidity
function setRelayer(address newRelayer) external;
```

`setRelayer` MUST revert if `msg.sender != RELAYER_ADMIN` (`UnauthorizedRelayerAdmin`). On success it MUST update `relayer = newRelayer` and emit `RelayerRotated(oldRelayer, newRelayer)`.

This function exists for KMS key rotation hygiene only. The contract does NOT gate any authorization function on `msg.sender == relayer`; the RELAYER's only on-chain footprint is being the typical `tx.origin` of `register()` and `recordSettlement()` submissions (gas payer).

### 8.8 Wire surface

The 402 challenge surfaces the Splitter integration to the agent via two fields on the `exact` `accepts[]` entry (§2.2):

- `pay_to` MUST be the Splitter contract address (a single, well-known on-chain address per Hub deployment).
- `extra.splitter_capability_id` MUST be the registered `bytes32` ID for this capability.

Agents MAY independently verify the registration on-chain by reading `Splitter.capabilities(capabilityId)` before signing the EIP-3009 authorization. SDKs SHOULD ship a helper for this check.

### 8.9 Provider opt-in

A Provider that opts in to x402 MUST:

1. Register a `usdc_payout_address` (Base mainnet EVM address) via `POST /v1/providers/me/payout-address`. Address change MUST require DNS reverification + 7-day cooldown + email notification (Panel 2 TM-S3). Once the contract has registered a capability with a given `provider` address, the Splitter binding cannot be changed without Provider `deactivate()` + fresh signed `register()` (§8.3).
2. Declare `payment_methods: ["stripe", "x402"]` (or `["x402"]`) on each capability action that accepts x402.
3. **Sign an EIP-712 `Register` payload** at `POST /v1/manifests/{id}/promote` time (§8.3). The Hub MUST collect this signature in the same request that promotes the manifest; the Hub then submits the on-chain `register()` transaction via its KMS-backed RELAYER (the Hub pays gas, ~$0.03–0.06 per call).

Providers MUST NOT publish the `usdc_payout_address` in any catalog field, manifest field, or other client-facing surface (Panel 2 TM-I6). The address lives only in Hub-internal state and on the Splitter contract.

### 8.10 RELAYER key management

The Hub's `relayer` key MUST be held in **AWS KMS** (or an equivalent FIPS 140-2 Level 3 HSM). The plaintext key MUST NOT appear in:

- Hub binary or source code,
- environment variables (Fly.io, Vercel, Docker),
- log output (including stack traces and panic reports),
- process memory beyond the duration of a single signature operation.

Reference implementation: the [`alloy-signer-aws`](https://docs.rs/alloy-signer-aws) crate. Signing latency MUST be budgeted at +80–120 ms per `register()` call; this is acceptable because registration fires on the lazy-on-promote path (`POST /v1/manifests/{id}/promote`), not on every invoke.

KMS rotation procedure: provision a new KMS key, derive its EVM address, call `setRelayer(newAddress)` from the `RELAYER_ADMIN` multisig, then disable the old KMS key. The old `RELAYER` address has no on-chain authority post-rotation; in-flight transactions it submitted continue to settle normally.

### 8.11 Invariants (formal-verification ready)

The Splitter MUST maintain the following invariants:

- **I-1** (split conservation): for every `splitFor` call, `providerAmount + hubAmount + reserveAmount == amount` where `amount` is `accountedBalance[capabilityId]` at function entry.
- **I-2** (ledger source-of-truth): `accountedBalance[capabilityId]` is incremented ONLY by `recordSettlement()`, which is gated to `AUTHORIZED_SETTLER`.
- **I-3** (nonce monotonicity): `usedNonces[n]` is set true exactly once per nonce and is never reset to false. EIP-712 `register()` calls with a re-used nonce MUST revert `NonceUsed`.
- **I-4** (registration authority): `capabilities[id].provider` is set ONLY by `register()` with a valid Provider EIP-712 signature recovered to that exact address. The RELAYER cannot set or change the provider field.
- **I-5** (no over-distribution): for every `splitFor` call, total USDC out of the contract ≤ `accountedBalance[id]` at function entry; the rounding-residual assignment to `reserveAmount` ensures equality.
- **I-6** (RELAYER rotation auditability): every change to `relayer` emits `RelayerRotated(oldRelayer, newRelayer)`; only `RELAYER_ADMIN` can trigger the change.

All six invariants SHOULD be expressed as Foundry invariant tests in the `jecp-contracts` repo, and SHOULD be in scope for the Spearbit / Cure53 / Trail of Bits audit (ADR-0003).

### 8.12 Splitter immutability and upgrade governance

The Splitter contract is **immutable except for the `relayer` address**. There is no proxy pattern, no upgrade hatch, and no admin pause. If a bug or new feature is required, the Hub deploys a v2 Splitter at a new address; capabilities migrate via fresh Provider-signed `register()` calls on v2; v1 stays operational for in-flight settlements until 30 days after migration is announced. This is the explicit trade-off for not introducing proxy attack surface.

## 9. Backward Compatibility

### 9.1 Old SDKs (no x402 awareness)

Old SDKs (≤ v0.7.x; pre-x402) do not send `X-Payment` and do not parse the `payment` field on 402 responses. v1.1.0 wire-format changes are designed to leave them unaffected:

- On a `["stripe"]`-only capability: behavior is unchanged. Wallet path runs. 402 responses still parse — old SDKs see `error.code = PAYMENT_REQUIRED` and `next_action.type = "topup"`. The new `payment` sibling field is silently ignored (additive OPTIONAL field; JSON parsers tolerate unknown keys).
- On a `["stripe", "x402"]` capability with low wallet: 402 returns. Old SDK reads `next_action.type = "topup"` and surfaces "top up your wallet". User tops up. Retry succeeds. The `payment` field is invisible to the old SDK; **no regression**.
- On an `["x402"]`-only capability: 402 returns with `next_action.type = "x402_settle"` (NOT `"topup"`). Old SDK does not recognize `"x402_settle"` and SHOULD surface a generic error like "unknown next_action type — see `error.message`". This is a **soft failure**; the user can read the message. Acceptable graceful degradation.

### 9.2 Migration recommendation for Providers

Until the SDK ecosystem reaches v0.8.0+ saturation (estimated 6 months post-v1.1.0 GA), Providers SHOULD declare `payment_methods: ["stripe", "x402"]` rather than `["x402"]` alone. This gives older agents a fallback while still allowing newer agents to settle directly on-chain.

**One-time on-chain registration cost.** A Provider that opts in to x402 MUST sign an EIP-712 `Register` payload at `POST /v1/manifests/{id}/promote` time (§8.3 / §8.9). The Hub submits the on-chain `register()` transaction via its KMS-backed RELAYER and pays gas of approximately $0.03–$0.06 per capability on Base mainnet (recovered after roughly 25 paid invokes at the typical $0.20 floor). The signing happens once per `(capabilityId, splits)` tuple; subsequent invokes consume no Provider signature. A capability that is never promoted incurs zero on-chain footprint and zero gas cost — the registration is strictly lazy.

A Provider that does NOT opt in to x402 (`payment_methods: ["stripe"]` or omitted) signs no EIP-712 payload and pays no on-chain gas. The Splitter integration is invisible to Stripe-only Providers.

### 9.3 Hub upgrade path

A Hub upgrading from v1.0 to v1.1:

- MUST run the database migrations for `x402_settlements`, `x402_refund_log`, and the `payment_methods` column on the capability table.
- MUST publish `/.well-known/agent-guide.json` with `payment_methods_supported` once the x402 facilitator is configured. Until then, MUST NOT advertise `"x402"` in any 402 response.
- MAY omit x402 support entirely and remain v1.1.0-conformant — the new error codes (X402_*) simply never fire. v1.1.0 conformance does NOT require x402 support; it requires honoring `payment_methods` declarations correctly when present.

### 9.4 Versioning rationale

This integration is shipped in jecp-spec v1.1.0 (minor bump). All changes are additive:

- New OPTIONAL field `pricing.payment_methods` on capability manifest.
- New OPTIONAL sibling field `payment` on the existing 402 error envelope.
- New OPTIONAL request header `X-Payment`.
- New OPTIONAL response header `X-Payment-Response`.
- 5 new error codes (`X402_*`) — additive per 03-errors.md §7.
- 1 new value (`"x402"`) on the open enum `billing.method`.
- 1 new value (`"x402_settle"`) on the open enum `next_action.type`.

No REQUIRED fields added. No types changed. No fields removed. No HTTP status remappings. No behavior change for capabilities with `payment_methods: ["stripe"]` (or omitted). The wire-version string `"jecp": "1.0"` is unchanged through the v1.x line.

## 10. Conformance Requirements

Conformant Hubs at v1.1.0 that advertise `"x402"` in any `payment_methods` declaration MUST pass the 22 conformance assertions in `conformance/v1.1/X402_*.yaml`:

- `X402_VERIFY_BEFORE_SETTLE` — `/verify` is called before `/settle`.
- `X402_AMOUNT_MISMATCH_REJECTED` — verified amount < expected → 422.
- `X402_NONCE_REUSE_REJECTED` — replay of same `auth_nonce` for different `(agent_id, request_id)` → 409.
- `X402_TX_HASH_REUSE_REJECTED` — same settlement `tx_hash` submitted twice → 409.
- `X402_FACILITATOR_TIMEOUT_GRACEFUL` — facilitator timeout → 504 + `Retry-After`.
- `X402_CERT_PIN_ENFORCED` — facilitator TLS cert change → 502 + `cert_pin_mismatch`.
- `X402_RESPONSE_SIG_VERIFIED` — facilitator response signature mismatch → 502 + `signature_pin_mismatch`.
- `X402_SUNSET_HEADER_PRESENT` — sunset capability with x402 → 410 + `Sunset` header (intersection with 01-protocol §4.6).
- `X402_PAYMENT_METHODS_FIELD_OPTIONAL` — manifest without `payment_methods` is accepted; defaults to `["stripe"]`.
- `X402_OLD_SDK_GRACEFUL_DEGRADE` — old-SDK-shaped request without `X-Payment` continues to use wallet on `["stripe", "x402"]` capabilities.
- `X402_SPLITTER_ADDRESS_IN_PAYTO` — `pay_to` in 402 response equals the published Splitter contract address.
- `X402_RECONCILER_CHAIN_CONFIRM` — reconciler transitions `facilitator_attested` → `chain_confirmed` after on-chain receipt verification.
- `X402_RECONCILER_MISMATCH_FLAGGED` — reconciler detects on-chain divergence and flags settlement.
- `X402_RECONCILER_ORPHAN_DETECTED` — reconciler marks settlement `orphaned` after 10-minute receipt-not-found window.
- `X402_REFUND_RATE_LIMIT_ENFORCED` — 11th refund / 24h / agent triggers investigation hold.
- `X402_KILL_SWITCH_HALTS_NEW` — `feature_flags.x402_enabled = false` halts new x402 invokes within 60s.
- `X402_KILL_SWITCH_PRESERVES_WALLET` — kill switch flip does NOT regress wallet-path latency or correctness.
- `X402_PAYMENT_RESPONSE_HEADER` — settled 200 carries `X-Payment-Response`.
- `X402_AGENT_GUIDE_DISCLOSES_X402` — `/.well-known/agent-guide.json` includes `payment_methods_supported = [..., "x402"]` when x402 is enabled.
- `X402_CACHE_CONTROL_NO_STORE` — every `/v1/invoke` response carries `Cache-Control: no-store` (v1.1.0-rc2; see §11.1).
- `X402_CORS_EXPOSE_HEADERS` — every `/v1/invoke` response (and the CORS preflight) advertises `X-Payment-Response, X-Request-Id, Retry-After, WWW-Authenticate` in `Access-Control-Expose-Headers` (v1.1.0-rc2; see §11.2).
- `X402_WWW_AUTHENTICATE_HEADER` — every 402 response carries `WWW-Authenticate` with the correct scheme value for the capability's accepted payment methods (v1.1.0-rc2; see §11.3).

Conformant Hubs that do NOT advertise `"x402"` (i.e., x402 is not configured) are exempt from the 19 x402-feature assertions but MUST still pass the existing v1.0 suite. The three header assertions (`X402_CACHE_CONTROL_NO_STORE`, `X402_CORS_EXPOSE_HEADERS`, `X402_WWW_AUTHENTICATE_HEADER`) bind to `/v1/invoke` shape and apply universally; non-x402 Hubs MAY skip the X-Payment-bearing setup steps and assert only on the 402 and 200-wallet branches.

## 11. Response headers (normative)

This section consolidates the three normative HTTP response headers introduced across §2.1, §3.3, §4.4, and §5. They are restated here in one place so implementers can verify their handler emits all three on every relevant response without cross-referencing four sections. Three additional conformance assertions in `conformance/v1.1/X402_*.yaml` cover this surface; see §10.

### 11.1 `Cache-Control: no-store` — MUST on every `/v1/invoke` response

Every response from `POST /v1/invoke` MUST carry `Cache-Control: no-store`. This includes:

- 200 OK responses on the wallet path (no x402 was settled).
- 200 OK responses on the x402 path (where `X-Payment-Response` is also emitted).
- 402 Payment Required challenges.
- 422 Unprocessable Entity errors (`X402_NOT_ACCEPTED`, `X402_PAYMENT_INVALID`).
- 409 Conflict errors (`X402_SETTLEMENT_REUSED`, `DUPLICATE_REQUEST`).
- 502 Bad Gateway (`X402_FACILITATOR_UNREACHABLE`).
- 504 Gateway Timeout (`X402_SETTLEMENT_TIMEOUT`).
- Streaming (text/event-stream) responses on the same endpoint.

Rationale: a paid call delivered from CDN cache replays revenue to the agent and skips settlement. The Hub's per-request idempotency cache prevents this within the Hub process, but does not bind intermediaries; `Cache-Control: no-store` does. Both §2.1 (already MUST on 402) and §5.2 (already MUST on 200) are restated here as a single Hub-wide rule covering every status.

### 11.2 `Access-Control-Expose-Headers` — MUST on every `/v1/invoke` response

Every response from `POST /v1/invoke` MUST carry:

```
Access-Control-Expose-Headers: X-Payment-Response, X-Request-Id, Retry-After, WWW-Authenticate
```

These are the four x402-relevant non-default response headers a browser-based agent reads via the Fetch API. Without explicit exposure, the browser strips them from JS access (CORS specification §10) — the agent cannot decode the receipt (`X-Payment-Response`), correlate its request (`X-Request-Id`), back off on facilitator delays (`Retry-After`), or surface the challenge to the user (`WWW-Authenticate`).

The CORS preflight (OPTIONS) response MUST list the same four headers in `Access-Control-Expose-Headers`. Hubs SHOULD also include `X-Payment` in `Access-Control-Allow-Headers` so browser-based agents may send the request header on preflighted requests.

The header value MAY be emitted as a single comma-separated string (as shown) or as repeated header values; both forms are RFC 7230-equivalent.

### 11.3 `WWW-Authenticate` — MUST on every 402 Payment Required response

Every 402 response from `POST /v1/invoke` MUST carry a `WWW-Authenticate` header per RFC 7235. The value depends on which payment methods the capability accepts (after applying the runtime kill switch from §6.3):

- When x402 is the ONLY accepted scheme (capability declares `payment_methods: ["x402"]` AND `feature_flags.x402_enabled = true`):

  ```
  WWW-Authenticate: x402, scheme="exact", network="base"
  ```

  The `network` parameter MUST match the network the `exact` entry advertises in `payment.accepts[]` (typically `"base"`; `"base-sepolia"` in test).

- When both Stripe wallet and x402 are accepted (`payment_methods: ["stripe", "x402"]` or any superset):

  ```
  WWW-Authenticate: x402, Bearer
  ```

  No realm parameter is required here — `Bearer` is the JECP wallet path (Stripe-funded API-key auth from §2 / 02-authentication.md), and emitting a realm on the wallet half can collide with proxy auth realms.

- When only Stripe is accepted (`payment_methods: ["stripe"]` or omitted; legacy / kill-switch state), Hubs SHOULD emit:

  ```
  WWW-Authenticate: Bearer
  ```

  This is a SHOULD (not MUST) for backward compatibility with v1.0 Hubs that did not emit `WWW-Authenticate` on the legacy wallet 402.

Rationale: non-JSON-aware HTTP clients (curl users, RFC 7235-aware proxies, generic HTTP libraries) MUST be able to recognize the response as an authentication challenge without parsing the JECP error envelope. The `x402` scheme name is registered ad-hoc per x402.org v1; the JECP working group will pursue IANA registration in a future version.

### 11.4 Worked example

A 402 response on a capability that accepts both methods:

```http
HTTP/1.1 402 Payment Required
Content-Type: application/json
Cache-Control: no-store
Retry-After: 30
WWW-Authenticate: x402, Bearer
Access-Control-Expose-Headers: X-Payment-Response, X-Request-Id, Retry-After, WWW-Authenticate

{
  "jecp": "1.0",
  "id": "req_abc123",
  "status": "failed",
  "error": { /* PAYMENT_REQUIRED */ },
  "payment": { /* accepts[]: stripe-wallet, exact (x402) */ }
}
```

A 200 OK on the x402-settled path:

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: no-store
X-Payment-Response: eyJzdWNjZXNzIjp0cnVlLCJ0cmFuc2FjdGlvbiI6IjB4Li4uIn0=
Access-Control-Expose-Headers: X-Payment-Response, X-Request-Id, Retry-After, WWW-Authenticate

{ "jecp": "1.0", "id": "req_abc123", "status": "completed", "result": { ... }, "billing": { "method": "x402", ... } }
```

## 12. References

- ADR-0003 — x402 Integration (the design rationale + admiral-locked decisions)
- ADR-0004 — Idempotency × x402 (extension of ADR-0001 to cover x402 settlements)
- 01-protocol.md §3 — request envelope (sibling `payment` field on error responses)
- 03-errors.md §3.4 — `PAYMENT_REQUIRED` (reused, not replaced)
- 03-errors.md §3.8 — new `X402_*` error codes + 19-subcause registry
- 04-manifest.md §5 — `Action.pricing.payment_methods`
- 05-discovery.md §4 — `/.well-known/agent-guide.json` `payment_methods_supported`
- 02-authentication.md §9.7.1 — composite SSRF defense (applies to facilitator URL at boot)
- [x402 spec v1](https://x402.org) — Coinbase HTTP 402 + USDC-on-Base micropayment
- [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) — `transferWithAuthorization`
- [EIP-2](https://eips.ethereum.org/EIPS/eip-2) — ECDSA signature malleability (low-`s` requirement)
- [RFC 4648 §4](https://datatracker.ietf.org/doc/html/rfc4648#section-4) — Standard base64 alphabet
- [RFC 7235](https://datatracker.ietf.org/doc/html/rfc7235) — `WWW-Authenticate` header semantics
- [USDC on Base](https://basescan.org/token/0x833589fcd6edb6e08f4c7c32d4f71b54bda02913) — canonical Circle-issued contract

## 13. Authors

JECP Working Group. Contact: hello@jecp.dev.
