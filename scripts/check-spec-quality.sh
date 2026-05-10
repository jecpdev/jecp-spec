#!/usr/bin/env bash
# Spec quality linter — JECP v1.1 c2.
#
# Replaces a heavyweight Spectral toolchain with a focused bash + python3
# checker for the small surface area of jecp-spec/. Validates:
#
#   1. Every spec/error-catalog/*.md carries the required header fields
#      (Public URL, Spec source, HTTP status) so each error has a stable
#      reference contract.
#   2. Every conformance/v1.0/*.yaml is parseable + has required keys
#      (id, level, spec_section) and a sane `level`.
#   3. README version badge matches the latest semver tag (informational).
#
# Used by .github/workflows/spec-lint.yml on every PR + push to main.
# Per locked-design v1.1 §4 D16=A: BLOCK on errors only; warnings annotate.

set -euo pipefail

cd "$(dirname "$0")/.."

EXIT=0
WARN_COUNT=0
ERR_COUNT=0

red()   { printf "\033[31m%s\033[0m" "$*"; }
green() { printf "\033[32m%s\033[0m" "$*"; }
yel()   { printf "\033[33m%s\033[0m" "$*"; }

err()  { echo "$(red ERROR): $*"; ERR_COUNT=$((ERR_COUNT+1)); EXIT=1; }
warn() { echo "$(yel WARN): $*"; WARN_COUNT=$((WARN_COUNT+1)); }
ok()   { echo "$(green OK): $*"; }

# ---------------------------------------------------------------
# Rule 1: every error-catalog/*.md has required fields
# ---------------------------------------------------------------
echo "── checking spec/error-catalog/ ──"
catalog_count=$(find spec/error-catalog -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$catalog_count" -lt 1 ]; then
  warn "spec/error-catalog/ is empty (acceptable until v1.1 errata pages land)"
else
  ok "found $catalog_count error catalog file(s)"
  for f in spec/error-catalog/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    if ! grep -q '^> Public URL: https://jecp.dev/errors/' "$f"; then
      err "$name missing '> Public URL: https://jecp.dev/errors/...' line"
    fi
    if ! grep -q '^> Spec source:' "$f"; then
      err "$name missing '> Spec source: ...' line"
    fi
    if ! grep -qE 'HTTP status:[[:space:]]*\`[0-9]{3}' "$f"; then
      err "$name missing 'HTTP status: \`NNN ...\`' line"
    fi
  done
fi

# ---------------------------------------------------------------
# Rule 2: conformance/v1.0/*.yaml parseable + required keys
# ---------------------------------------------------------------
echo "── checking conformance/v1.0/ ──"
if ! python3 -c "import yaml" 2>/dev/null; then
  err "python3 yaml module missing (pip install pyyaml)"
else
  python3 - <<'PY' || EXIT=1
import sys, yaml as Y, glob, os, re

err = 0
ALLOWED_LEVELS = {'MUST', 'SHOULD', 'MAY'}
ID_RE = re.compile(r'^JECP-[A-Z]+-(MUST|SHOULD|MAY)-[A-Z0-9-]+$')

files = sorted(glob.glob('conformance/v1.0/*.yaml'))
print(f"  found {len(files)} conformance YAML(s)")
for f in files:
    name = os.path.basename(f)
    try:
        d = Y.safe_load(open(f, 'r', encoding='utf-8'))
    except Exception as e:
        print(f"  ERROR: {name} parse failure: {e}")
        err += 1
        continue
    if not isinstance(d, dict):
        print(f"  ERROR: {name} top-level is not a mapping")
        err += 1
        continue
    for k in ('id', 'level', 'spec_section'):
        if k not in d:
            print(f"  ERROR: {name} missing required key '{k}'")
            err += 1
    if d.get('level') and d['level'] not in ALLOWED_LEVELS:
        print(f"  ERROR: {name} level={d['level']!r} not in {ALLOWED_LEVELS}")
        err += 1
    aid = d.get('id', '')
    if aid and not ID_RE.match(str(aid)):
        print(f"  ERROR: {name} id={aid!r} does not match JECP-<AREA>-<LEVEL>-<NUMBER> grammar")
        err += 1
    fname_aid = name[:-len('.yaml')]
    if aid and aid != fname_aid:
        print(f"  ERROR: {name} id={aid!r} does not match filename")
        err += 1

sys.exit(1 if err else 0)
PY
  if [ $? -eq 0 ]; then ok "conformance YAMLs all valid"; fi
fi

# ---------------------------------------------------------------
# Rule 3: README version badge matches latest tag (informational warn)
# ---------------------------------------------------------------
echo "── checking README badge vs latest tag ──"
latest_tag=$(git tag --list 'v[0-9]*' 2>/dev/null | grep -v -- '-rc' | sort -V | tail -1 | sed 's/^v//')
badge_version=$(grep -oE 'version-([0-9]+\.[0-9]+\.[0-9]+)-blue' README.md | head -1 | sed 's/^version-\([^-]*\)-blue/\1/' || true)
if [ -n "$latest_tag" ] && [ -n "$badge_version" ]; then
  if [ "$latest_tag" != "$badge_version" ]; then
    warn "README badge version ($badge_version) differs from latest tag ($latest_tag) — bump on next release"
  else
    ok "README badge $badge_version matches latest tag v$latest_tag"
  fi
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo
echo "═══ Spec quality summary ═══"
echo "  errors:   $ERR_COUNT"
echo "  warnings: $WARN_COUNT"
exit $EXIT
