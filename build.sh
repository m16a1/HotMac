#!/bin/bash
# Build HotMac.app: compile the Swift sources and assemble a menu bar bundle.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/HotMac.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/Info.plist" "$APP/Contents/Info.plist"

swiftc -O -parse-as-library \
    -o "$APP/Contents/MacOS/HotMac" \
    "$DIR/Sources/"*.swift \
    -framework SwiftUI -framework AppKit -framework Charts -framework IOKit

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "Run:  open \"$APP\""
echo "Stop: pkill -x HotMac"
