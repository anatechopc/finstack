#!/usr/bin/env bash
# Run `fvm flutter analyze` on apps/loans and report SOURCE issues only,
# filtering the build/ noise (SPM checkouts under build/ios/SourcePackages
# produce thousands of phantom errors from flutterfire example code).
#
# Exit 0 when there are no errors outside build/; exit 1 otherwise.
# Baseline for reference (2026-07-07): 0 errors / 10 warnings / 136 infos.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT/apps/loans"

out="$(fvm flutter analyze 2>&1 || true)"
src="$(printf '%s\n' "$out" | grep '•' | grep -v '• build/' || true)"

errors=$(printf '%s\n' "$src" | grep -c 'error •' || true)
warnings=$(printf '%s\n' "$src" | grep -c 'warning •' || true)
infos=$(printf '%s\n' "$src" | grep -c 'info •' || true)

echo "Source-only analyze results (build/ excluded):"
echo "  errors:   $errors"
echo "  warnings: $warnings"
echo "  infos:    $infos"

if [ "$errors" -gt 0 ]; then
  echo
  echo "Source errors:"
  printf '%s\n' "$src" | grep 'error •'
  exit 1
fi
