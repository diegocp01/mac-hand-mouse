#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
SWIFTC=(xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache")
# The camera-free engine and everything it depends on.
ENGINE=(Sources/PointerFilter.swift Sources/ClickGestures.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/InteractionEngine.swift)
# AppKit views that render without a camera, Accessibility access, or a window server session.
UI=(Sources/StartupUI.swift Sources/GestureGuide.swift Sources/GestureDemoCanvas.swift Sources/PracticeTasks.swift Sources/FeedbackGeometry.swift Sources/FeedbackUI.swift Sources/LaunchUI.swift)

"${SWIFTC[@]}" "${ENGINE[@]}" Sources/FrameMailbox.swift Sources/FeedbackGeometry.swift Tests/main.swift -o build/gesture-tests
build/gesture-tests
"${SWIFTC[@]}" "${ENGINE[@]}" Tests/InteractionEngineTests.swift -o build/interaction-tests
build/interaction-tests
"${SWIFTC[@]}" "${ENGINE[@]}" Tests/RecoveryScrollTests.swift -o build/recovery-scroll-tests
build/recovery-scroll-tests
"${SWIFTC[@]}" "${ENGINE[@]}" Tests/TwoHandDragTests.swift -o build/two-hand-drag-tests
build/two-hand-drag-tests
"${SWIFTC[@]}" Sources/SourceUpdate.swift Tests/SourceUpdateTests.swift -o build/source-update-tests
build/source-update-tests
bash Tests/update.sh
"${SWIFTC[@]}" "${ENGINE[@]}" Tests/SteadyAimTests.swift -o build/steady-aim-tests
build/steady-aim-tests
"${SWIFTC[@]}" "${ENGINE[@]}" Tests/StillClickTests.swift -o build/still-click-tests
build/still-click-tests
"${SWIFTC[@]}" "${ENGINE[@]}" Tests/ClickGestureTests.swift -o build/click-gesture-tests
build/click-gesture-tests
"${SWIFTC[@]}" "${ENGINE[@]}" Sources/FeatureFlags.swift Sources/PracticeDiagnostics.swift Tests/PracticeDiagnosticsTests.swift -o build/practice-diagnostics-tests
build/practice-diagnostics-tests
"${SWIFTC[@]}" "${ENGINE[@]}" Sources/PracticeTasks.swift Tests/PracticeTaskTests.swift -o build/practice-task-tests
build/practice-task-tests
"${SWIFTC[@]}" Sources/StartupUI.swift Sources/GestureGuide.swift Sources/GestureDemoCanvas.swift Tests/GestureDemoTimelineTests.swift -framework AppKit -o build/gesture-demo-timeline-tests
build/gesture-demo-timeline-tests
"${SWIFTC[@]}" Sources/FeatureFlags.swift "${ENGINE[@]}" Sources/PracticeDiagnostics.swift Sources/PracticeDiagnosticsUI.swift "${UI[@]}" Tests/UIRenderSupport.swift Tests/PracticeDiagnosticsUISnapshot.swift -o build/diagnostics-ui-render
build/diagnostics-ui-render
"${SWIFTC[@]}" "${UI[@]}" Tests/UIRenderSupport.swift Tests/LaunchUISnapshot.swift -o build/launch-ui-render
build/launch-ui-render "$PWD/build/ui-review"
