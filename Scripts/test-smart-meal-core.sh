#!/bin/bash
# Runs the exact app calculation/draft sources without app startup or treatment transport.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/smart-meal-core.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/Sources/LoopFollow" "$test_root/Tests/LoopFollowTests"
for name in RiceMealPlan MealReviewSettings MealReviewSnapshot MealReviewCalculation MealReviewFullCalculation; do
    cp "$repo_root/LoopFollow/Remote/TRC/$name.swift" "$test_root/Sources/LoopFollow/"
done
for name in RiceMealPlanTests MealReviewCalculationTests MealReviewSnapshotTests MealReviewFullCalculationTests; do
    cp "$repo_root/Tests/$name.swift" "$test_root/Tests/LoopFollowTests/"
done
cat > "$test_root/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SmartMealCoreTests", platforms: [.macOS(.v13)], targets: [.target(name: "LoopFollow"), .testTarget(name: "LoopFollowTests", dependencies: ["LoopFollow"])], swiftLanguageModes: [.v5])
PACKAGE
swift test --package-path "$test_root"
