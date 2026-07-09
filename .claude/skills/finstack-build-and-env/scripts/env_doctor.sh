#!/usr/bin/env bash
# finstack env doctor — read-only diagnostics for the local build environment.
# Checks toolchain presence/versions and the known local-build traps documented
# in .claude/skills/finstack-build-and-env/SKILL.md. Makes NO changes.
#
# Usage: .claude/skills/finstack-build-and-env/scripts/env_doctor.sh
# Exit code: 0 = no FAILs (WARNs allowed), 1 = at least one FAIL.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

FAILS=0
WARNS=0

pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; WARNS=$((WARNS + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }

echo "== finstack env doctor =="
echo "repo root: $REPO_ROOT"
echo

# --- Trap: path with spaces (breaks Flutter 3.44 SPM auto-integration) ---
case "$REPO_ROOT" in
  *" "*) fail "repo path contains a space — Flutter 3.44 SPM will break (move the repo to a space-free path)" ;;
  *)     pass "repo path has no spaces" ;;
esac

# --- Required tools ---
for tool in fvm go java gcloud gh; do
  if command -v "$tool" >/dev/null 2>&1; then
    pass "$tool found ($(command -v "$tool"))"
  else
    fail "$tool not found on PATH"
  fi
done

# Optional tools (needed only for specific tasks)
for tool in firebase pod xcodebuild sdkmanager; do
  if command -v "$tool" >/dev/null 2>&1; then
    pass "$tool found (optional)"
  else
    warn "$tool not found (optional — needed for index/rules deploys, iOS, Android SDK mgmt)"
  fi
done

echo

# --- Flutter pin (apps/loans/.fvmrc) vs fvm global default ---
FVMRC="$REPO_ROOT/apps/loans/.fvmrc"
if [ -f "$FVMRC" ]; then
  PINNED=$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FVMRC")
  pass "apps/loans/.fvmrc pins Flutter $PINNED"
  if [ -L "$HOME/fvm/default" ]; then
    GLOBAL_VER=$(basename "$(readlink "$HOME/fvm/default")")
    if [ "$GLOBAL_VER" = "$PINNED" ]; then
      pass "fvm global default = $GLOBAL_VER (matches pin — packages/*.sh will use the right SDK)"
    else
      fail "fvm global default = $GLOBAL_VER but pin is $PINNED — packages/*.sh scripts run outside apps/loans and use the GLOBAL default. Fix: fvm global $PINNED"
    fi
  else
    warn "no fvm global default (~/fvm/default missing) — set one: fvm global $PINNED (packages/*.sh depends on it)"
  fi
else
  fail "missing $FVMRC"
fi

# --- Go version ---
if command -v go >/dev/null 2>&1; then
  GOVER=$(go version | awk '{print $3}')
  case "$GOVER" in
    go1.22*) pass "Go $GOVER (functions/loans targets go 1.22.x)" ;;
    *)       warn "Go $GOVER — functions/loans/go.mod targets go 1.22.12; newer usually works, but CI pins 1.22" ;;
  esac
fi

# --- Java version (need 17 for AGP 8.11 / sms-gateway) ---
if command -v java >/dev/null 2>&1; then
  JAVA_MAJOR=$(java -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9]*\).*/\1/p')
  if [ "${JAVA_MAJOR:-0}" -ge 17 ] 2>/dev/null; then
    pass "Java $JAVA_MAJOR (>= 17)"
  else
    fail "Java ${JAVA_MAJOR:-unknown} — Android builds (AGP 8.11.1) and sms-gateway need JDK 17"
  fi
fi

echo

# --- Trap: gradle jvmargs must stay 4096M ---
GP="$REPO_ROOT/apps/loans/android/gradle.properties"
if grep -q 'org.gradle.jvmargs=-Xmx4096M' "$GP" 2>/dev/null; then
  pass "apps/loans gradle jvmargs = 4096M"
else
  fail "apps/loans/android/gradle.properties jvmargs is not -Xmx4096M — 2048M OOMs at this toolchain"
fi

# --- Trap: triggers module typo is load-bearing info ---
TRIG_MOD=$(head -1 "$REPO_ROOT/functions/loans/triggers/go.mod" 2>/dev/null)
if [ "$TRIG_MOD" = "module com.looans.app/triggers" ]; then
  pass "triggers/go.mod still has the known two-o typo (harmless while root replace directives exist)"
elif [ "$TRIG_MOD" = "module com.loooans.app/triggers" ]; then
  warn "triggers/go.mod typo has been FIXED since this skill was authored — update SKILL.md"
else
  warn "triggers/go.mod first line unexpected: '$TRIG_MOD'"
fi

if grep -q 'replace com.loooans.app/triggers => ./triggers' "$REPO_ROOT/functions/loans/go.mod" 2>/dev/null; then
  pass "root go.mod replace directives present"
else
  fail "root functions/loans/go.mod is missing 'replace com.loooans.app/triggers => ./triggers' — builds will break"
fi

# --- ADC for local Go Admin SDK runs ---
if [ -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
  pass "ADC file present (~/.config/gcloud/application_default_credentials.json) — note: ADC account can differ from 'gcloud auth list'"
else
  warn "no ADC file — local Go Admin SDK runs need: gcloud auth application-default login"
fi

echo

# --- sms-gateway local config (only if you work on it) ---
SG="$REPO_ROOT/apps/sms-gateway"
if [ -f "$SG/app/google-services.json" ]; then
  pass "sms-gateway: app/google-services.json present"
else
  warn "sms-gateway: app/google-services.json missing (download from Firebase console; required to build sms-gateway)"
fi
if [ -f "$SG/local.properties" ] && grep -q '^gateway.email=..*' "$SG/local.properties" && grep -q '^gateway.password=..*' "$SG/local.properties"; then
  pass "sms-gateway: local.properties has non-empty gateway.email / gateway.password"
else
  warn "sms-gateway: gateway.email / gateway.password missing or empty in local.properties (app builds but cannot sign in)"
fi

echo
echo "== summary: $FAILS fail(s), $WARNS warn(s) =="
if [ "$FAILS" -gt 0 ]; then
  exit 1
fi
exit 0
