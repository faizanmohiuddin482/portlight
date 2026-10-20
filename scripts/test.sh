#!/usr/bin/env bash
# Runs the test suite. With only the Command Line Tools installed, Swift Testing
# isn't on the default search path, so point the compiler and linker at it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" ]]; then
  F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  exec swift test \
    -Xswiftc -F"$F" -Xlinker -F"$F" \
    -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
fi
exec swift test "$@"
