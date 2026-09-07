# Hand Mouse v1.2 functional audit

This audit addresses difficult pinch clicks, misleading hand colors, and the local permission failure observed after packaging. It is a functional review, not a claim of a complete security audit.

| Finding | Improvement | Evidence |
| --- | --- | --- |
| Orange landmarks indicated fingertip proximity even when the click detector was unarmed. | Landmarks and status now follow the gesture state; only an emitted click produces the white flash and Click! message. Added a Test click target. | Source review and state-machine tests; final gesture feel requires live use. |
| A single missing hand frame disarmed clicking, including brief fingertip occlusion during a pinch. | Preserve readiness for up to 120 ms while discarding interrupted confirmation evidence. Long gaps still require reopening. | Brief and long gap, held-pinch, and reacquisition tests. |
| Small fluctuations around the close threshold repeatedly canceled confirmation. | Use a separate confirmation tolerance and require two fresh observations. Added saved Precise/Balanced/Easy sensitivity settings. | Jitter, noise, frame-rate, preset, and duplicate-prevention tests. |
| A near-pinch could freeze the cursor even when no click was armed. | Freeze from the confirmed gesture state, holding the pre-pinch aim through click and release. | Integrated detector/pointer test. |
| Pinches during cooldown could turn into unexpected delayed clicks. | Consume those gestures and require reopening instead of queuing a click. | Cooldown regression test. |
| Missing thumb or pinky landmarks disabled index-finger movement. Palm width also shrank when the hand turned. | Separate pointer tracking from pinch measurements; use wrist-to-middle distance as a fallback scale. | Geometry, scale, and aspect tests; physical hand rotation still needs live evaluation. |
| Overlay assumed 4:3 even when capture delivered widescreen video. | Fit landmarks and the movement guide to the actual frame aspect ratio. | 4:3 and 16:9 geometry tests. |
| Main-thread callbacks could accumulate or arrive after pause/restart. | Keep only the newest pending result and reject callbacks from an earlier camera session. | Bounded-delivery tests and source inspection of session generation checks. |
| Camera denial/startup errors left the button in a misleading running state. | Return to paused state with an actionable error message. | Error-path source review and successful compilation. |
| Temporary app copies shared an identifier, and macOS retained an older signature requirement. | Build installer/package intermediates in temporary directories with cleanup, add Show this app in Finder, and document a reset limited to Hand Mouse. | Prior live System Settings and TCC-log diagnosis; installer/archive validation. |

Automated tests use synthetic landmark distances and timestamps. They do not establish real camera accuracy or successful OS mouse injection. The practice target is available for that final live check. No tracking images, user screenshots, or permission database contents are included in this repository.
