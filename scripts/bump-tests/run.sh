#!/bin/bash
# Compiles the Foundation-only Bump logic with a tiny test main and runs it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/AccountabilityAlarm/AccountabilityAlarm"
OUT="$(mktemp -d)/bump-tests"
swiftc -parse-as-library -o "$OUT" \
  "$APP"/Bump/Logic/*.swift \
  "$APP/Models/ConversationMessage.swift" \
  "$ROOT/scripts/bump-tests/main.swift"
"$OUT"
