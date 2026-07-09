#!/usr/bin/env bash
# scan-security-regressions.sh — read-only guardrail for finstack security invariants.
#
# Checks (see references/security-invariants.md):
#   3. No real jwt.ParseUnverified( call sites (finstack#71/#74).
#   4. No committed credential material — key files or JWT/PEM literals (finstack#60,
#      and Finding 3: the expired OIDC JWT in job/subscription_job.go).
#   5. Every gated HTTP handler still calls ValidateRequestV2 (informational list).
#
# Exit 0 = clean; exit 1 = at least one regression found. Read-only; no writes.
#
# Usage: bash scripts/scan-security-regressions.sh [functions-dir]
#   Defaults to the finstack functions/loans tree relative to this script.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# repo root is five levels up: .claude/skills/finstack-security-hardening/scripts
default_fn_dir="$(cd "$script_dir/../../../.." 2>/dev/null && pwd)/functions/loans"
FN_DIR="${1:-$default_fn_dir}"

if [[ ! -d "$FN_DIR" ]]; then
  echo "ERROR: functions dir not found: $FN_DIR" >&2
  echo "Pass the path explicitly: bash scan-security-regressions.sh /path/to/functions/loans" >&2
  exit 2
fi

echo "Scanning: $FN_DIR"
fail=0

echo
echo "== [3] jwt.ParseUnverified( call sites (must be none) =="
if grep -rn 'ParseUnverified(' "$FN_DIR" --include='*.go' | grep -v '//'; then
  echo "  REGRESSION: a ParseUnverified call site exists — see invariant #3." >&2
  fail=1
else
  echo "  OK (a comment mention in triggers/user_created.go is expected and benign)."
fi

echo
echo "== [4] committed key files / credential literals (must be none) =="
if grep -rn 'WithCredentialsFile\|WithCredentialsJSON\|BEGIN PRIVATE KEY\|private_key' \
    "$FN_DIR" --include='*.go'; then
  echo "  REGRESSION: credential material referenced in Go source — see invariant #4." >&2
  fail=1
else
  echo "  OK: no key-file references."
fi

echo
echo "== [4/Finding 3] JWT literals in source (must be none) =="
# A JWT is three base64url segments separated by dots, starting with eyJ.
if grep -rEn 'eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}' "$FN_DIR" --include='*.go'; then
  echo "  REGRESSION: a JWT literal is committed (Finding 3 = job/subscription_job.go:18)." >&2
  echo "  Delete the offending comment/line. See SKILL.md 'Finding 3'." >&2
  fail=1
else
  echo "  OK: no JWT literals."
fi

echo
echo "== [5] gated HTTP handlers calling ValidateRequestV2 (informational) =="
grep -rn 'ValidateRequestV2' "$FN_DIR/api" "$FN_DIR/utils" --include='*.go' 2>/dev/null \
  | grep -v 'validate_request_v2.go' \
  || echo "  (none found — investigate if new HTTP handlers were added)"
echo "  Reminder: setPassword + sendPasswordSetupLink are intentionally public;"
echo "  every other HTTP function must validate. See invariant #5."

echo
if [[ "$fail" -ne 0 ]]; then
  echo "RESULT: regression(s) found." >&2
  exit 1
fi
echo "RESULT: clean."
exit 0
