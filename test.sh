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
scroll_sources=("$project_dir/Tests/M6BarTests/ScrollPhysicsTests.swift")
if [[ -f "$project_dir/Sources/M6Bar/ScrollPhysics.swift" ]]; then
    scroll_sources+=("$project_dir/Sources/M6Bar/ScrollPhysics.swift")
fi
xcrun swiftc -swift-version 6 -parse-as-library \
    "${scroll_sources[@]}" \
    -o "$build_dir/ScrollPhysicsTests"
"$build_dir/ScrollPhysicsTests"
event_sources=("$project_dir/Tests/M6BarTests/ScrollEventTests.swift" "$project_dir/Sources/M6Bar/ScrollPhysics.swift")
if [[ -f "$project_dir/Sources/M6Bar/ScrollEventCodec.swift" ]]; then
    event_sources+=("$project_dir/Sources/M6Bar/ScrollEventCodec.swift")
fi
xcrun swiftc -swift-version 6 -parse-as-library "${event_sources[@]}" -o "$build_dir/ScrollEventTests"
"$build_dir/ScrollEventTests"
xcrun swiftc -swift-version 6 -parse-as-library \
    "$project_dir/Sources/M6Bar/ScrollPhysics.swift" \
    "$project_dir/Sources/M6Bar/ScrollEventCodec.swift" \
    "$project_dir/Sources/M6Bar/ScrollEventEngine.swift" \
    "$project_dir/Tests/M6BarTests/ScrollEngineTests.swift" \
    -o "$build_dir/ScrollEngineTests"
"$build_dir/ScrollEngineTests"
