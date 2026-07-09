#!/usr/bin/env bash
# Run the Go Cloud Functions test suite (macOS-safe).
# CGO_ENABLED=0 bypasses "dyld: missing LC_UUID" on macOS; harmless on Linux.
# Extra args are passed to `go test` (e.g. -run TestCreate -v ./test/triggers/...).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT/functions/loans"
exec env CGO_ENABLED=0 go test "${@:-./...}"
