#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="${M6BAR_BUILD_DIR:-"$project_dir/work"}"
mkdir -p "$build_dir"
xcrun swiftc -swift-version 6 -parse-as-library \
    "$project_dir/Sources/M6Bar/Telemetry.swift" \
    "$project_dir/Tests/M6BarTests/TelemetryTests.swift" \
    -o "$build_dir/TelemetryTests"
"$build_dir/TelemetryTests"
