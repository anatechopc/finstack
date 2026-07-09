#!/usr/bin/env bash
# verify-contract.sh — read-only drift check for the finstack architecture contract.
# Authored 2026-07-07 (finstack-architecture-contract skill). Safe to run anytime:
# it only greps/reads files, never writes.
#
# Usage: .claude/skills/finstack-architecture-contract/scripts/verify-contract.sh
# Exit code: 0 = no drift detected, 1 = at least one WARN.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
cd "$ROOT" || exit 2

warn=0
say()  { printf '%s\n' "$*"; }
ok()   { printf 'OK    %s\n' "$*"; }
warnf(){ printf 'WARN  %s\n' "$*"; warn=1; }

say "finstack architecture-contract drift check — repo: $ROOT"
say ""

# --- I2: the prefix triple ------------------------------------------------
say "[I2] Collection-prefix sites (eyeball: all three must map development->dev_, staging->stg_, production->'')"
grep -Hn "return 'stg_'\|return 'dev_'\|return ''" \
  packages/core/loooans_helpers/lib/src/data_helpers/database/base_firestore_service.dart 2>/dev/null \
  || warnf "Flutter prefix getter not found where expected (base_firestore_service.dart)"
grep -Hn 'collectionPrefix = "dev_"\|collectionPrefix = "stg_"' \
  functions/loans/utils/environment_utils.go 2>/dev/null \
  || warnf "Go GetCollectionPrefix cases not found (utils/environment_utils.go)"
grep -Hn 'collectionPrefix="dev_"\|collectionPrefix="stg_"' \
  .github/scripts/deploy_functions.sh 2>/dev/null \
  || warnf "deploy script prefix assignment not found (.github/scripts/deploy_functions.sh)"
say ""

# --- I2: hardcoded prefixes creeping in ------------------------------------
say "[I2] Hardcoded 'dev_'/'stg_' outside sanctioned files"
GO_HARD=$(grep -rn '"dev_\|"stg_' functions/loans --include="*.go" 2>/dev/null \
  | grep -v "_test\|environment_utils.go\|job/subscription_job.go" || true)
if [ -n "$GO_HARD" ]; then warnf "hardcoded prefix in Go:"; say "$GO_HARD"; else ok "Go clean (known exception: disabled job/subscription_job.go)"; fi
DART_HARD=$(grep -rn "'dev_'\|'stg_'" apps/loans/lib packages --include="*.dart" 2>/dev/null \
  | grep -v "base_firestore_service.dart\|/test/" || true)
if [ -n "$DART_HARD" ]; then warnf "hardcoded prefix in Dart:"; say "$DART_HARD"; else ok "Dart clean (tests asserting the prefix excluded)"; fi
say ""

# --- Module typo ------------------------------------------------------------
say "[go.mod] triggers module name"
MOD=$(head -1 functions/loans/triggers/go.mod 2>/dev/null || true)
case "$MOD" in
  *com.looans.app*)  say "KNOWN two-o typo still present: '$MOD' (open weak point; held together by root replace)";;
  *com.loooans.app*) ok "triggers/go.mod module name fixed: '$MOD' — update SKILL.md weak-points table";;
  *)                 warnf "unexpected triggers/go.mod first line: '$MOD'";;
esac
say ""

# --- DI counts ---------------------------------------------------------------
say "[DI] provider counts (contract snapshot 2026-07-07: 20 repos / 16 blocs)"
RP=$(grep -cE "^\s+RepositoryProvider[(<]" apps/loans/lib/app/di/repository_providers.dart 2>/dev/null)
BP=$(grep -cE "^\s+BlocProvider[(<]" apps/loans/lib/app/di/bloc_providers.dart 2>/dev/null)
RP=${RP:-0}; BP=${BP:-0}
if [ "$RP" = "20" ] && [ "$BP" = "16" ]; then
  ok "20 repository providers / 16 blocs (matches snapshot)"
else
  warnf "DI counts changed: $RP repository providers / $BP blocs (snapshot: 20/16) — update SKILL.md section 2"
fi
say ""

# --- Singleton residue ---------------------------------------------------------
say "[DI] BLoCs binding .instance WITHOUT a .withDependencies seam"
say "      (snapshot debt = 7: loans, payment, capital, product, payment_center, company, reports)"
KNOWN="loans/bloc/loans_bloc.dart loans/bloc/payment_bloc.dart capital/bloc/capital_bloc.dart products/bloc/product_bloc.dart payment_center/bloc/payment_center_bloc.dart companies/bloc/company_bloc.dart reports/bloc/reports_bloc.dart"
NOSEAM=""
for f in $(grep -rln "AuthenticationService.instance\|SettingsService.instance" apps/loans/lib/features --include="*_bloc.dart" 2>/dev/null); do
  grep -q "withDependencies" "$f" || NOSEAM="$NOSEAM $f"
done
NEW=""
GONE=""
for f in $NOSEAM; do
  case " $KNOWN " in *"${f#apps/loans/lib/features/}"*) ;; *) NEW="$NEW $f";; esac
done
for k in $KNOWN; do
  case " $NOSEAM " in *"$k"*) ;; *) GONE="$GONE $k";; esac
done
if [ -n "$NEW" ]; then warnf "NEW un-seamed .instance BLoC(s) (regression of decision 4):$NEW"; fi
if [ -n "$GONE" ]; then ok "formerly un-seamed bloc(s) now fixed:$GONE — update SKILL.md + evidence.md"; fi
if [ -z "$NEW" ] && [ -z "$GONE" ]; then ok "un-seamed set unchanged (7 known legacy files)"; fi
say ""

# --- Unwired packages -----------------------------------------------------------
say "[pkgs] dormant packages still unwired"
UNW=$(grep -c "karma_transaction_repository\|transaction_repository\|transaction_view_repository" apps/loans/pubspec.yaml 2>/dev/null)
UNW=${UNW:-0}
if [ "$UNW" -eq 0 ] 2>/dev/null; then
  ok "karma_transaction/transaction/transaction_view still not in apps/loans/pubspec.yaml"
else
  warnf "a dormant package is now wired in ($UNW refs in pubspec.yaml) — update SKILL.md section 1"
fi
say ""

# --- Weak-point markers ------------------------------------------------------------
say "[weak] open weak-point markers"
for pat in "TODO(deibeeed)" "%\$w"; do
  HITS=$(grep -c "$pat" functions/loans/triggers/loan_changes.go 2>/dev/null)
  HITS=${HITS:-0}
  say "      loan_changes.go '$pat': $HITS hit(s) (0 => fixed; update SKILL.md table)"
done
PAYTODO=$(grep -rln "TODO(payments)" apps/loans/lib/features 2>/dev/null | wc -l | tr -d ' ')
say "      TODO(payments) files: $PAYTODO (2 at snapshot: payment_center_bloc, payment_submission_bloc)"
PROD_UNDERSCORE=$(grep -c 'pathEnv+"_loan_schedules"' functions/loans/triggers/loan_changes.go 2>/dev/null)
PROD_UNDERSCORE=${PROD_UNDERSCORE:-0}
if [ "$PROD_UNDERSCORE" -gt 0 ] 2>/dev/null; then
  say "KNOWN pathEnv+\"_loan_schedules\" still present ($PROD_UNDERSCORE sites) — open weak point (see campaign skill)"
else
  ok "pathEnv+\"_loan_schedules\" gone — update SKILL.md weak-points table"
fi
say ""

if [ "$warn" -eq 0 ]; then
  say "RESULT: no NEW drift. (Known-open weak points above stay open until their campaign closes them.)"
else
  say "RESULT: drift/warnings above — reconcile code and SKILL.md."
fi
exit "$warn"
