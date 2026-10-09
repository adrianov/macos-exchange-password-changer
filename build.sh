#!/bin/sh
set -eu
cd "$(dirname "$0")"
root=$(pwd)
app="$root/build/Exchange Password.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -parse-as-library -O -target "$arch-apple-macosx14.0" \
    -framework AppKit -framework SwiftUI \
    -o "build/ExchangePassword-$arch" Sources/*.swift
done
lipo -create build/ExchangePassword-arm64 build/ExchangePassword-x86_64 \
  -output "$app/Contents/MacOS/ExchangePassword"
rm build/ExchangePassword-arm64 build/ExchangePassword-x86_64
cp Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
echo "$app"
