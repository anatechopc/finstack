#!/usr/bin/env bash
# Run the Flutter app test suite with the repo's canonical flags
# (coverage + randomized ordering). Extra args are passed through,
# e.g.:  test-flutter.sh test/features/chat/chat_bloc_test.dart
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT/apps/loans"
exec fvm flutter test --coverage --test-randomize-ordering-seed random "$@"
