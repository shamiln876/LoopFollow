#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/plate-scanner.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/Sources/LoopFollow" "$test_root/Tests/LoopFollowTests"
cp "$repo_root/LoopFollow/Remote/TRC/PlateScan.swift" "$repo_root/LoopFollow/Remote/TRC/CarnivalFood.swift" "$test_root/Sources/LoopFollow/"
cp "$repo_root/Tests/PlateScanTests.swift" "$test_root/Tests/LoopFollowTests/"
cat > "$test_root/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PlateScanTests", platforms: [.macOS(.v13)], targets: [.target(name: "LoopFollow"), .testTarget(name: "LoopFollowTests", dependencies: ["LoopFollow"])], swiftLanguageModes: [.v5])
PACKAGE
PLATE_TEST_CATALOG="$repo_root/LoopFollow/Resources/CarnivalFoodGuide.json" swift test --package-path "$test_root" --scratch-path "$test_root/build" -Xswiftc -module-cache-path -Xswiftc "$test_root/cache"
node --test "$repo_root/server/plate-scanner/worker.test.mjs" "$repo_root/server/plate-scanner/budget.test.mjs"
