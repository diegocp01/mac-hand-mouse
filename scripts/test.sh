#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Sources/FrameMailbox.swift Sources/FeedbackGeometry.swift Tests/main.swift -o build/gesture-tests
build/gesture-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Tests/InteractionEngineTests.swift -o build/interaction-tests
build/interaction-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Tests/RecoveryScrollTests.swift -o build/recovery-scroll-tests
build/recovery-scroll-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Tests/TwoHandDragTests.swift -o build/two-hand-drag-tests
build/two-hand-drag-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Tests/OneHandDragTests.swift -o build/one-hand-drag-tests
build/one-hand-drag-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/SourceUpdate.swift Tests/SourceUpdateTests.swift -o build/source-update-tests
build/source-update-tests
bash Tests/update.sh
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Tests/TwoFingerTapTests.swift -o build/tap-tests
build/tap-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Tests/TapTimingTests.swift -o build/tap-timing-tests
build/tap-timing-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/TapGuidance.swift Tests/TapGuidanceTests.swift -o build/tap-guidance-tests
build/tap-guidance-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Tests/SteadyAimTests.swift -o build/steady-aim-tests
build/steady-aim-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Tests/IntentClickTests.swift -o build/intent-click-tests
build/intent-click-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Sources/FeatureFlags.swift Sources/PracticeDiagnostics.swift Tests/PracticeDiagnosticsTests.swift -o build/practice-diagnostics-tests
build/practice-diagnostics-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Sources/PracticeTasks.swift Tests/PracticeTaskTests.swift -o build/practice-task-tests
build/practice-task-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/StartupUI.swift Tests/GestureDemoTimelineTests.swift -framework AppKit -o build/gesture-demo-timeline-tests
build/gesture-demo-timeline-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/FeatureFlags.swift Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Sources/PracticeDiagnostics.swift Sources/PracticeDiagnosticsUI.swift Sources/StartupUI.swift Sources/PracticeTasks.swift Sources/FeedbackGeometry.swift Sources/FeedbackUI.swift Sources/LaunchUI.swift Tests/UIRenderSupport.swift Tests/PracticeDiagnosticsUISnapshot.swift -o build/diagnostics-ui-render
build/diagnostics-ui-render
