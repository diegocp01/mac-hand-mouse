#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/FrameMailbox.swift Sources/FeedbackGeometry.swift Tests/main.swift -o build/gesture-tests
build/gesture-tests
