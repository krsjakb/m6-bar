#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
artifact_dir="$(dirname -- "$project_dir")"
build_dir="${M6BAR_BUILD_DIR:-"$project_dir/work"}"
app_dir="$artifact_dir/M6 Bar.app"
mkdir -p "$build_dir" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
arch_name="$(uname -m)"
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -target "$arch_name-apple-macosx14.0" \
    "$project_dir"/Sources/M6Bar/*.swift \
    -o "$app_dir/Contents/MacOS/M6Bar" \
    -framework AppKit -framework SwiftUI -framework Charts -framework IOKit -framework ServiceManagement
xcrun swift "$project_dir/Tools/Icon.swift" "$build_dir"
iconutil -c icns "$build_dir/M6Bar.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - --identifier hu.balint.m6bar "$app_dir"
printf 'Elkészült: %s\n' "$app_dir"
