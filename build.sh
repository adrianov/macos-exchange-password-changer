#!/bin/sh
set -eu
cd "$(dirname "$0")"
root=$(pwd)
app="$root/build/Exchange Password.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
swiftc -parse-as-library -O -framework AppKit -framework SwiftUI \
  -o "$app/Contents/MacOS/ExchangePassword" \
  Sources/*.swift
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "$app"
