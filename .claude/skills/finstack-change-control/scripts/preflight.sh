#!/usr/bin/env bash
# finstack change-control preflight — READ-ONLY.
# Checks the current branch and pending changes against the change-control
# rules in .claude/skills/finstack-change-control/SKILL.md.
# Exit 1 on hard violations (forbidden branch, key material in diff),
# exit 0 with warnings otherwise.

set -u

fail=0
warn() { printf 'WARN  %s\n' "$1"; }
err()  { printf 'FAIL  %s\n' "$1"; fail=1; }
ok()   { printf 'ok    %s\n' "$1"; }

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Not inside a git repo." >&2; exit 1; }
cd "$root" || exit 1

branch="$(git rev-parse --abbrev-ref HEAD)"
echo "== finstack change-control preflight =="
echo "branch: $branch"

# --- Rule 9: never work directly on deploy branches ---------------------
case "$branch" in
  master)
    err "You are on 'master' — pushing deploys PRODUCTION (loooans-prod). Branch off." ;;
  main)
    err "'main' is a dead vestige of the monorepo genesis — never target it. Use develop." ;;
  develop)
    warn "On 'develop' directly. Pushing deploys the dev environment; prefer a feature branch + PR." ;;
  release/*)
    warn "On a release branch — pushing deploys STAGING. Intentional? (App workflow only matches release/v*.)" ;;
  *)
    ok "feature branch" ;;
esac

# --- Collect pending changes (staged + unstaged + committed-ahead) -------
base=""
for cand in origin/develop develop; do
  if git rev-parse --verify -q "$cand" >/dev/null; then base="$cand"; break; fi
done
changed="$( { git diff --name-only; git diff --cached --name-only;
              [ -n "$base" ] && git diff --name-only "$base"...HEAD; } 2>/dev/null | sort -u)"
if [ -z "$changed" ]; then
  ok "no pending changes detected vs ${base:-HEAD}"
fi

# --- Rule 6: never commit credentials (finstack#60) ----------------------
# Scan staged + unstaged added lines for key material.
secrets="$( { git diff -U0; git diff --cached -U0; } 2>/dev/null \
  | grep -E '^\+' \
  | grep -nE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|"private_key"|AIza[0-9A-Za-z_-]{30}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}' \
  | head -5)"
if [ -n "$secrets" ]; then
  err "Possible key/token material in your diff (finstack#60 incident — Google disables exposed keys):"
  printf '%s\n' "$secrets" | sed 's/^/      /'
else
  ok "no key/token patterns in staged+unstaged diff"
fi

flag() { printf '%s\n' "$changed" | grep -qE "$1"; }

# --- Area-specific gates --------------------------------------------------
if flag '^functions/loans/'; then
  echo "-- Go functions touched:"
  echo "   [ ] go build -v ./... && go test -v ./...   (macOS: CGO_ENABLED=0)"
  echo "   [ ] new/touched handler follows adapter+core with fakes (rule 4)"
  echo "   [ ] new function registered in loooans_cloud_functions.go init()"
  echo "       AND added to .github/scripts/deploy_functions.sh (hand-kept list)"
  echo "   [ ] dates written with .UnixMilli(), never time.Time"
fi

if flag '^apps/loans/|^packages/'; then
  echo "-- Flutter app/packages touched:"
  echo "   [ ] fvm flutter analyze on touched paths"
  echo "   [ ] fvm flutter test --test-randomize-ordering-seed random"
fi

if flag '_entity\.dart$' && ! flag '^functions/loans/'; then
  warn "Entity (doc-shape) change without Go changes — Class B rule: doc-shape ships both sides, BACKEND FIRST (two PRs)."
fi
if flag '^functions/loans/triggers/' && ! flag '^apps/loans/|^packages/'; then
  echo "-- Trigger-only change: fine if shape-compatible. If the doc shape changed,"
  echo "   this must be the (1/2, deploy first) backend PR with a frontend follow-up."
fi

if flag 'loan_calculation_service\.dart|charge_calculator\.dart|triggers/loan_changes\.go|loan_schedule'; then
  warn "Loan-math/reporting surface touched — golden verification gate applies (finstack-loan-engine-and-reporting-campaign)."
fi

if flag 'validate_request|otp_service|\.rules'; then
  warn "Security-sensitive surface touched — check finstack-security-hardening invariants (finstack#71: no tolerant auth paths)."
fi

if flag '\.rules$|\.rules\.json$|firestore\.indexes'; then
  echo "-- Rules/indexes touched: remember real Firestore/Storage rules are console-managed;"
  echo "   console changes need a repo note (.reference file or MEMORY.md entry)."
fi

# --- MEMORY.md duty --------------------------------------------------------
if [ -n "$changed" ] && ! flag 'MEMORY\.md$'; then
  warn "No MEMORY.md in this change set — update the relevant MEMORY.md (root / apps/loans / functions/loans) before ending the session."
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL — fix the FAIL lines before committing/pushing."
  exit 1
fi
echo "RESULT: pass (heed WARN lines)."
