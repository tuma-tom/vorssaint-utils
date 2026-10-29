#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -std=gnu11 -O2 -fblocks Tests/SoftwareVolumeDriverTests.c -framework CoreAudio -framework CoreFoundation -framework Accelerate -o build/software-volume-driver-tests
./build/software-volume-driver-tests
xcrun swiftc Sources/Vorssaint/Services/QuickTools/MicMuteSupport.swift Sources/Vorssaint/Services/Audio/VirtualOutputSupport.swift Tests/SoftwareVolume/BridgeTests.swift -o build/software-volume-bridge-tests
./build/software-volume-bridge-tests
python3 Tests/SoftwareVolume/UninstallTests.py
