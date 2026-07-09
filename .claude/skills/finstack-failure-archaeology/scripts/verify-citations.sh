#!/usr/bin/env bash
# verify-citations.sh — verify the commit-hash citations in
# finstack-failure-archaeology resolve in the local finstack repo.
# Read-only (git cat-file only). Safe to run any time.
#
# Usage: bash verify-citations.sh
#
# What it does:
#   1. Extracts every commit hash cited in SKILL.md + references/saga-evidence.md.
#   2. Checks each resolves to a real commit object in the repo.
#   3. Prints a per-hash + summary report; exits non-zero if any locally
#      resolvable citation is missing.
#
# Known exception: the finstack#83 merge commit (f95eb6e...) is documented as
# "GitHub-only until you git fetch" (SKILL.md §5). If it is missing locally that
# is EXPECTED — the script reports it as a soft NOTE (not a failure) and suggests
# `git fetch origin`.
#
# Volatile PR/issue *states* are intentionally NOT checked here — for those,
# re-run the gh commands in SKILL.md's "Provenance and maintenance" section.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"

# The documented GitHub-only merge commit (SKILL.md §5 / saga-evidence "Chat era").
GITHUB_ONLY_PREFIX="f95eb6e"

if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: $REPO_ROOT is not a git work tree — cannot verify citations." >&2
  exit 2
fi

# Extract candidate commit hashes: 7-40 hex chars wrapped in backticks in the two
# citation files. The strict hex filter excludes English words (v, l, o, p, ...
# are not hex), and file paths in backticks contain '/' or '.', so false
# positives are effectively nil.
HASHES="$(grep -hoE '`[0-9a-f]{7,40}`' \
    "$SKILL_DIR/SKILL.md" \
    "$SKILL_DIR/references/saga-evidence.md" \
  | tr -d '`' | sort -u)"

if [ -z "$HASHES" ]; then
  echo "No commit-hash citations found — nothing to verify (unexpected)." >&2
  exit 2
fi

count="$(printf '%s\n' "$HASHES" | wc -l | tr -d ' ')"
echo "Verifying $count cited commit hashes against $REPO_ROOT ..."
echo

ok=0; missing=0; softmissing=0
fail_list=""
for h in $HASHES; do
  if git -C "$REPO_ROOT" cat-file -e "${h}^{commit}" 2>/dev/null; then
    printf '  OK      %s\n' "$h"
    ok=$((ok + 1))
  elif [ "${h#$GITHUB_ONLY_PREFIX}" != "$h" ]; then
    printf '  NOTE    %s  (GitHub-only merge; run: git -C %s fetch origin)\n' "$h" "$REPO_ROOT"
    softmissing=$((softmissing + 1))
  else
    printf '  MISSING %s\n' "$h"
    missing=$((missing + 1))
    fail_list="$fail_list $h"
  fi
done

echo
echo "Summary: $ok resolved, $missing missing, $softmissing GitHub-only (expected)."
echo "Volatile PR/issue states are NOT checked — see SKILL.md 'Provenance and maintenance'."

if [ "$missing" -gt 0 ]; then
  echo
  echo "FAIL — these cited hashes do not resolve locally:" >&2
  for h in $fail_list; do echo "  $h" >&2; done
  exit 1
fi

echo "PASS — all locally-resolvable citations check out."
exit 0
