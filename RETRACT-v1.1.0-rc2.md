# Retraction Notice — `jecp-spec@v1.1.0-rc2`

**Date**: 2026-05-16
**Status**: RETRACTED. Superseded by `jecp-spec@v1.1.0-rc3`.
**Reason**: Architectural reassessment of `AUTHORIZED_SETTLER` role definition. No wire-format incompatibility; SDK / CLI / Provider integration unchanged.

---

## 1. What was retracted

`jecp-spec@v1.1.0-rc2`, tagged 2026-05-13, including the cert-pin restoration patch and the three audit-A HIGH header fixes (§11.1 `Cache-Control: no-store`, §11.2 `Access-Control-Expose-Headers`, §11.3 `WWW-Authenticate`). The rc2 spec text is intact and remains historically referenced; only the **release tag and its associated GitHub Release** are retracted, marked SUPERSEDED, and replaced by rc3.

The rc2 retraction is **not** an emergency security advisory. No production deployments of v1.1.0-rc2 exist (Splitter not yet mainnet-deployed; the rc2 mainnet deploy gate was blocked by the same OQ-1 that surfaced the AUTHORIZED_SETTLER defect). The retraction is governance hygiene: external review on 2026-05-16 identified that rc2's normative definition of `AUTHORIZED_SETTLER` (the x402.org facilitator's address) was non-implementable against x402.org as deployed and inverted x402's published trust model. ADR-0003 Am-7 (2026-05-16) records the correction; rc3 is the canonical text.

---

## 2. Retract command sequence (operator runs)

Executed by the `jecpdev` maintainer with push rights to `github.com/jecpdev/jecp-spec`. Commands assume working tree at `/Users/tufecompany/Desktop/開発・プロジェクト/jecp-spec`.

```bash
# Step 1 — confirm current state
git -C /Users/tufecompany/Desktop/開発・プロジェクト/jecp-spec fetch --tags --prune
git -C /Users/tufecompany/Desktop/開発・プロジェクト/jecp-spec tag -l 'jecp-spec/v1.1.0-rc*'
# expected: jecp-spec/v1.1.0-rc1, jecp-spec/v1.1.0-rc2

# Step 2 — delete local rc2 tag
git -C /Users/tufecompany/Desktop/開発・プロジェクト/jecp-spec tag -d jecp-spec/v1.1.0-rc2

# Step 3 — delete remote rc2 tag
git -C /Users/tufecompany/Desktop/開発・プロジェクト/jecp-spec push --delete origin jecp-spec/v1.1.0-rc2

# Step 4 — verify deletion
git -C /Users/tufecompany/Desktop/開発・プロジェクト/jecp-spec ls-remote --tags origin | grep -F 'v1.1.0-rc2' || echo "rc2 tag removed cleanly"

# Step 5 — proceed to rc3 tag after spec edits land
git -C /Users/tufecompany/Desktop/開発・プロジェクト/jecp-spec tag -a jecp-spec/v1.1.0-rc3 -m "v1.1.0-rc3 — supersedes rc2; AUTHORIZED_SETTLER redefinition via Am-7"
git -C /Users/tufecompany/Desktop/開発・プロジェクト/jecp-spec push origin jecp-spec/v1.1.0-rc3
```

**Safety note**: deleting a Git tag is reversible only if the tagged commit remains reachable from another ref (e.g., `main`). The rc2 commit MUST remain reachable; do NOT also delete branches that contain it. The retraction targets the tag pointer only.

---

## 3. GitHub Releases marking

After Step 3 above, the GitHub Release UI requires manual editing (the tag delete does not auto-update the Release page). Operator steps:

1. Navigate to `https://github.com/jecpdev/jecp-spec/releases/tag/jecp-spec/v1.1.0-rc2`. The page now shows "This tag has been deleted" but the Release entity persists.
2. Click "Edit release".
3. Prepend the title with **`[SUPERSEDED] `**: `[SUPERSEDED] jecp-spec v1.1.0-rc2 — header MUSTs + cert-pin patch`.
4. Replace the release-notes body with the public notice below, in full.
5. Check "Set as a pre-release" (should already be checked); leave "Set as the latest release" unchecked.
6. Save.

### Public release-notes body (replace rc2 body verbatim)

> **This release tag has been retracted on 2026-05-16 and is superseded by `jecp-spec@v1.1.0-rc3`.**
>
> External review on 2026-05-16 identified that v1.1.0-rc2's normative definition of `AUTHORIZED_SETTLER` (the x402.org facilitator's address) was non-implementable against x402.org as deployed and inverted x402's published trust model. The rc3 release applies amendment Am-7 to ADR-0003, redefining `AUTHORIZED_SETTLER` as a Hub-controlled keeper EOA driven by the Hub keeper-driver. Wire format is unchanged across rc2 → rc3; SDK `@jecpdev/sdk@0.8.x`, CLI `@jecpdev/cli@0.7.x`, and Provider EIP-712 registration are unaffected. The three audit-A header MUSTs and the cert-pin patch from rc2 are preserved verbatim in rc3.
>
> No production deployments existed at rc2 (Splitter contract was not yet on Base mainnet). Implementers who built against rc2 should update to rc3; no code-level migration is required for SDK / CLI consumers. Splitter contract implementers MUST adopt the rc3 constructor argument layout per `spec/v1.1.0-rc3-errata.md` §E.1.
>
> See `jecp-spec/v1.1.0-rc3` release notes for full details and the ADR-0003 Am-7 record.

---

## 4. npm package coordination

The `@jecpdev/sdk` and `@jecpdev/cli` npm packages are **wire-compatible** with rc3 and DO NOT require deprecation. No `npm deprecate` action is taken. Explicit guidance to consumers (posted in `CHANGELOG.md` of each repo):

> `@jecpdev/sdk@0.8.x` and `@jecpdev/cli@0.7.x` are fully conformant with `jecp-spec@v1.1.0-rc3`. The rc2 → rc3 spec change is server-side (Hub + Splitter contract) only; SDK consumers require no upgrade.

If, in a future rc4 or v1.1.0 GA, a wire-affecting change does occur, deprecation will use the standard form:

```bash
npm deprecate "@jecpdev/sdk@<version>" "use @jecpdev/sdk@<next-version> for jecp-spec@v1.1.0 GA conformance"
```

This is NOT executed for the rc2 → rc3 transition.

---

## 5. Downstream notification

The following parties MUST be notified within 24 h of the retract being pushed:

| Party | Channel | Message owner |
|---|---|---|
| `jecp-contracts` maintainer | GitHub Issue on `jecpdev/jecp-contracts` titled "Splitter v1 constructor — adopt rc3 `AUTHORIZED_SETTLER` semantics (Am-7)" | admiral |
| `jecpdev/website` (LP) maintainer | Copy patch sweep per `JobDoneBot/docs/jecp/release-prep/RC3-COPY-PATCH-TRACKER.md` Patch 4-5 | brand-guardian |
| Audit firm RFP recipients (Spearbit / Cure53 / Trail of Bits) | Email from `security@jecp.dev` with subject "RFP scope update — Splitter v1 rc3 constructor change (Am-7)"; bundle the 3-scope split per BS-4 | admiral + protocol-designer |
| `acromoney777@gmail.com` (admiral inbox) | This document URL + ADR-0003 Am-7 URL | self |

Notification text is published in `docs/jecp/release-prep/rc2-retract-notifications.md` (separate file) and is out of scope of this retraction document.
