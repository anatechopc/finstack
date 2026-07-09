#!/usr/bin/env bash
# Runs the D2 race proof in both modes against a local RTDB emulator.
# Prereq: firebase emulators:start --only database --project demo-race
# (see references/aggregation-triggers.md for a copy-paste emulator setup).
set -uo pipefail
cd "$(dirname "$0")"

export FIREBASE_DATABASE_EMULATOR_HOST="${FIREBASE_DATABASE_EMULATOR_HOST:-localhost:9000}"
export CGO_ENABLED=0   # macOS dyld LC_UUID workaround; harmless elsewhere

N="${1:-50}"

echo "=== racy mode (mirrors applyToNodeValue) — expect lost updates, exit 1 ==="
go run . -n "$N"
racy=$?

echo
echo "=== transaction mode (Ref.Transaction) — expect exactly $N, exit 0 ==="
go run . -n "$N" -txn
txn=$?

echo
if [ "$racy" -ne 0 ] && [ "$txn" -eq 0 ]; then
  echo "RESULT: race demonstrated AND transaction fix proven."
  exit 0
fi
echo "RESULT: unexpected (racy exit $racy, txn exit $txn) — rerun or raise N; see main.go header."
exit 1
