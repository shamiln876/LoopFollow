#!/bin/bash
# Runs both apps' exact model/receiver sources in separate modules. No treatment transport.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
trio_root="${1:?Pass the matching Trio checkout as the first argument}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/smart-meal-integration.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
cmp "$repo_root/LoopFollow/Remote/TRC/SmartMealProtocol.swift" "$trio_root/Trio/Sources/Models/SmartMealProtocol.swift"
mkdir -p "$test_root/Sources/LoopFollow" "$test_root/Sources/Trio" "$test_root/Tests/IntegrationTests"
for name in RiceMealPlan MealReviewSettings MealReviewSnapshot MealReviewCalculation MealReviewFullCalculation SmartMealProtocol SmartMealDelivery PushMessage TRCCommandType; do
    cp "$repo_root/LoopFollow/Remote/TRC/$name.swift" "$test_root/Sources/LoopFollow/"
done
cp "$trio_root/Trio/Sources/Models/SmartMealProtocol.swift" "$test_root/Sources/Trio/"
cp "$trio_root/Trio/Sources/Models/CommandPayload.swift" "$test_root/Sources/Trio/"
cp "$trio_root/Trio/Sources/Services/RemoteControl/SmartMealReceiver.swift" "$test_root/Sources/Trio/"
# The actual enum/decode implementation is in CommandPayload.swift; only its containing
# service name is stubbed. No app resolver, transport or pump can be initialized here.
printf 'final class TrioRemoteControl {}\n' > "$test_root/Sources/Trio/ServiceContainerStub.swift"
cp "$repo_root/Scripts/SmartMealIntegrationTests.swift" "$test_root/Tests/IntegrationTests/"
cat > "$test_root/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SmartMealIntegrationTests", platforms: [.macOS(.v13)], targets: [.target(name: "LoopFollow"), .target(name: "Trio"), .testTarget(name: "IntegrationTests", dependencies: ["LoopFollow", "Trio"])], swiftLanguageModes: [.v5])
PACKAGE
swift test --package-path "$test_root" --jobs 2
