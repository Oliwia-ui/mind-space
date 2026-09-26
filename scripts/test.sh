#!/usr/bin/env bash
set -euo pipefail

PLUGIN="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$PLUGIN" ]]; then
  swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN"
else
  swift test
fi
