#!/usr/bin/env bash
# Verifies the ADR registry shape:
#   1. At least one ADR file exists at jecp-spec/adr/0NNN-*.md
#   2. ADR-0001 (Idempotency-Provenance Interaction) exists by exact name
#   3. Every ADR has the 4 required sections (Status / Context / Decision / Consequences)
#   4. Every ADR with status "Accepted" has a date in the Status line
#
# Used by .github/workflows/adr-lint.yml on every PR + push to main.
# Also runnable as a pre-commit hook.

set -euo pipefail

cd "$(dirname "$0")/.."

ROOT="adr"

if [ ! -d "$ROOT" ]; then
  echo "✗ FAIL: $ROOT/ does not exist"
  exit 1
fi

# Rule 1: at least one ADR
count=$(find "$ROOT" -maxdepth 1 -name '0*-*.md' | wc -l | tr -d ' ')
if [ "$count" -lt 1 ]; then
  echo "✗ FAIL: $ROOT/ must contain >=1 ADR (0NNN-*.md). Found 0."
  exit 1
fi
echo "✓ ADR count: $count"

# Rule 2: ADR-0001 by exact name
TARGET="$ROOT/0001-idempotency-provenance-interaction.md"
if [ ! -f "$TARGET" ]; then
  echo "✗ FAIL: ADR-0001 missing — expected $TARGET"
  echo "  This ADR is the v1.0.2 commitment artifact (idempotency↔provenance)."
  exit 1
fi
echo "✓ ADR-0001 present"

# Rule 3: required sections in every ADR
required_sections=("## Status" "## Context" "## Decision" "## Consequences")
fail=0
while IFS= read -r f; do
  for h in "${required_sections[@]}"; do
    if ! grep -qF "$h" "$f"; then
      echo "✗ FAIL: $f missing section '$h'"
      fail=$((fail+1))
    fi
  done
done < <(find "$ROOT" -maxdepth 1 -name '0*-*.md')

if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "✓ All ADRs have the 4 required sections"

# Rule 4: Accepted ADRs have a date
while IFS= read -r f; do
  status_line=$(grep -m1 -E '^(Accepted|Superseded|Deprecated)' "$f" || true)
  if [ -z "$status_line" ]; then
    # Fall back to looking for the section's content (next non-empty line after ## Status)
    status_line=$(awk '/^## Status/{flag=1; next} flag && NF{print; exit}' "$f")
  fi
  if echo "$status_line" | grep -q "Accepted" && ! echo "$status_line" | grep -qE '\(20[0-9]{2}-[0-9]{2}-[0-9]{2}\)'; then
    echo "✗ FAIL: $f has Status: Accepted but no date in YYYY-MM-DD form"
    fail=$((fail+1))
  fi
done < <(find "$ROOT" -maxdepth 1 -name '0*-*.md')

if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "✓ All Accepted ADRs carry a date"

echo
echo "═══ ADR registry healthy ═══"
