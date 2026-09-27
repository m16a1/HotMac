#!/bin/bash
# Run the HotMac logic tests. No framework or package manager: the harness in
# Tests/main.swift is compiled together with the sources and asserts directly.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$(mktemp -d)/hotmac-tests"

swiftc -O -DDEBUG \
    -o "$BIN" \
    "$DIR/Tests/main.swift" \
    "$DIR/Sources/SMC.swift" \
    "$DIR/Sources/Sensors.swift" \
    "$DIR/Sources/TemperatureModel.swift" \
    -framework SwiftUI -framework AppKit -framework IOKit

"$BIN"
status=$?
rm -rf "$(dirname "$BIN")"
exit $status
