# JECP — Architecture Decision Records (ADRs)

Architecture decisions for the JECP protocol live here. ADRs sit alongside the spec they document — outsiders building a wire-compatible Hub find the rationale in the same repo as the prose.

ADRs are immutable: once accepted, a decision is not edited. Superseding decisions get their own ADR with a `Supersedes:` line.

## Format

Every ADR uses [`template.md`](./template.md) and has these sections in order:

- **Status** — Accepted / Superseded / Deprecated, with date.
- **Context** — what's the problem.
- **Decision** — what's the rule.
- **Consequences** — what follows.
- **Alternatives Considered** — what we rejected and why.
- **References** — supporting links.

CI guard: PRs that add a new `adr/0NNN-*.md` file MUST also reference it from `CHANGELOG.md` (enforced by `.github/workflows/adr-lint.yml`).

## Index

| Number | Title | Status | Date |
|---|---|---|---|
| [ADR-0001](./0001-idempotency-provenance-interaction.md) | Idempotency–Provenance Interaction | Accepted | 2026-05-10 |

## How to read

If you're a Hub implementer: read every ADR before tagging a release. They encode wire-format guarantees that are not always obvious from the spec text alone.

If you're an SDK author: ADRs explain the *why* of behaviors your SDK must mirror. The spec tells you the *what*.

If you're a security researcher: ADRs document the threat models we considered and the alternatives we rejected. They're a faster path to understanding our defense-in-depth choices than reading the source.
