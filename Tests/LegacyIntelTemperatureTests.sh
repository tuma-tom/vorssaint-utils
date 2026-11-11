#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
legacy_test_dir="$(mktemp -d)"
trap 'rm -rf "$legacy_test_dir"' EXIT
cat > "$legacy_test_dir/main.swift" <<'SWIFT'
import Foundation
let intel = TemperatureSensorSelector.platform(brandString: "Intel(R) Core(TM) i7-8750H CPU @ 2.20GHz")
for key in ["TC0P", "TC0D", "TCAD", "TC1C", "TC2c"] {
    precondition(TemperatureSensorSelector.isCPUTemperatureKey(key, platform: intel), "Missing Intel CPU sensor: \(key)")
}
for key in ["TCGC", "TG0D", "TB0T", "Tp01", "TCXX"] {
    precondition(!TemperatureSensorSelector.isCPUTemperatureKey(key, platform: intel), "Not an Intel CPU sensor: \(key)")
}
for key in ["TCGC", "TG0D", "TGDD", "TG0H", "TG0P"] {
    precondition(TemperatureSensorSelector.isGPUTemperatureKey(key, platform: intel), "Missing Intel GPU sensor: \(key)")
}
precondition(!TemperatureSensorSelector.isGPUTemperatureKey("TC0P", platform: intel))
precondition(!TemperatureSensorSelector.hasCPUCoreSet(platform: intel), "Unverified Intel sensors must not enable automatic fan curves")
precondition(TemperatureSensorSelector.displayedCPUTemperature(readings: [("TC0D", 76), ("TC0P", 52), ("TCAD", 0)], platform: intel) == 76)
precondition(!TemperatureSensorSelector.isCPUTemperatureKey("TC0D", platform: .appleM1Family))
precondition(TemperatureSensorSelector.isGPUTemperatureKey("Tg05", platform: .appleM1Family))
precondition(!TemperatureSensorSelector.isGPUTemperatureKey("TGDD", platform: .appleM1Family))
print("LEGACY INTEL TEMPERATURE TESTS OK")
SWIFT
swiftc Sources/Vorssaint/Services/Metrics/TemperatureSensorSelector.swift "$legacy_test_dir/main.swift" -o "$legacy_test_dir/tests"
"$legacy_test_dir/tests"
