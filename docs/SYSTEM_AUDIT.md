# v1.3 system audit

Historical audit. Version 1.4 replaces the automatic Dwell mode discussed below;
see [forward-click design and validation](FORWARD_CLICK.md) for the current interaction.

Reviewed September 7, 2026. Scope includes the existing application, PR #1's pointer and click modes, and PR #2's camera/countdown interface. The fixes and enhancements are included together in PR #2.

## Findings and fixes

| Area | Problem found | Result |
| --- | --- | --- |
| Dwell rearming | A full reset after stalled delivery could discard the post-click movement requirement, allowing another click at the same spot. | Tracking interruptions cancel incomplete progress while retaining the completed-click lock and cooldown. |
| Invalid observations | Nonmonotonic timestamps and nonfinite points could reset completed-click state. Extreme display bounds could produce nonfinite pointer coordinates. | Invalid observations cancel arming without bypassing rearm rules; invalid display bounds produce no pointer or click output. |
| Dwell aiming | At 60 fps the pointer could freeze before settling onto a new target. | Increased the settling interval from 80 to 100 ms; production-path tests cover re-aiming at 15, 30, and 60 fps. |
| Tracking cadence | Floating-point rounding at the 120 ms grace boundary could cancel an otherwise regular dwell. | A one-nanosecond comparison tolerance preserves the nominal boundary while longer gaps still cancel. |
| Input pipeline | Some older tests assembled their own gesture/filter loop, which could miss mistakes in the app's actual ordering. | `InteractionEngine` is the production path and the integration-test target. It gates freshness, permissions, settings, detector order, and pointer output. |
| Camera recovery | Capture interruptions and runtime failures had no explicit recovery path; repeated Vision errors looked like missing hands. A paused session could retain a disconnected camera. | Relevant capture notifications and five consecutive processing failures stop and invalidate the session. Pausing releases the configured camera, and Start performs fresh discovery. Removed-output callbacks are rejected; normal no-hand frames are not errors. |
| System changes | Display changes or a sleeping/inactive session could leave a countdown aimed at obsolete coordinates. | Pause on display configuration changes, sleep, display sleep, and user-session deactivation; verify the selected display before producing events. |
| Cursor feedback | An overlay could fall back to the wrong display, gain inappropriate window behavior, or leave a moving click confirmation. | Explicitly non-key/non-main, click-through panel; support other apps' full-screen contexts; hide on missing display; confirmation remains at the sent click location. |
| Interface | Dwell timing was fixed, mode settings could not be prepared with clicks off, and the target display was unnamed. | Saved 0.65/1/1.5-second hold presets, settings available during practice, and a visible target-display label. |
| Accessibility | A disclosure button's title was not rendered by its native bezel. Progress and state feedback needed clearer semantics. | Separate visible label, expanded/collapsed accessibility state, labeled percentage, and discrete state/click announcements. |
| Installation | Copying over an existing bundle could retain removed files or partially replace a working app. | Fresh staging, signature verification, replacement with rollback, and refusal to overwrite a running destination. |
| Development launch | The launcher could run an old build after source changes. | Rebuild before launch; if the exact build is running, ask the developer to quit before rebuilding. |

## Verification

- `bash scripts/test.sh`: **187 core checks and 51 production interaction-engine checks** pass. Covers pinch confirmation, cooldown, dwell progress/cancel/rearm, loss of tracking, malformed input, frame delivery, pointer response, display mapping, and overlay geometry.
- `bash Tests/install.sh`: isolated fresh install, stale-file removal, failed-verification rollback, build-failure preservation, cleanup, and running-destination refusal pass. It never installs into the user's Applications folder.
- Universal `arm64` + `x86_64` build targets macOS 13; both architecture slices and the app signature are verified.
- A failed build preserves the prior app; a successful rebuild removes an injected obsolete resource. Builds and installs for this audit use temporary directories.
- Shell syntax, plist validation, and whitespace checks pass. CI runs the logic and installer tests, native builds, and signature checks on Apple Silicon and Intel, with universal packaging on Apple Silicon.
- Independent GPT-5.6 Sol high reviews covered gesture state, production input ordering, interface/accessibility, camera lifecycle, and installation. An additional 50,000-frame synthetic dwell exercise found no stationary-repeat violation; this is a supplementary probe, not a substitute for the committed regressions.

## Hands-on checks still required

The Mac was locked during the final visual check. Build and synthetic-test results do not establish live hand-tracking quality, spoken VoiceOver behavior, or delivery to another application.

Before release, use the Test click target to verify Pinch and each dwell duration, move-to-cancel/rearm, recovery from a hidden hand, and clicks off during a countdown. Check camera disconnect/retry, Accessibility revocation, sleep/resume, and display connection changes. Confirm ring placement and click-through behavior on a second display and inside full-screen applications; review the compact window with permissions expanded and VoiceOver enabled. Physical Intel and older supported macOS testing remain outstanding.

The existing installed app is unchanged. This audit does not merge either pull request. Binary archives remain ad-hoc signed and not notarized; the source installer is the supported installation route.
