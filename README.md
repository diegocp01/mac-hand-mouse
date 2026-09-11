![Hand Mouse — your hand, your cursor](docs/images/hand-mouse-hero.jpeg)

# Hand Mouse

*Illustration above. Current left-click gesture: raise index + middle and hold for one second.*

**Control your Mac's mouse with your hand.** Show your hand and move to aim. From an open hand, raise **index + middle** with the other fingers curled and hold for **one second** to left-click; a ring fills while the pointer holds its target. Bring **all five fingertips together** to right-click. Clicks default **on**; the camera starts paused. Runs locally with your camera and Apple's hand tracking — no accounts, cloud, or model downloads.

## First launch

The startup window follows your Mac's light or dark appearance and keeps **Start / Pause** and **Practice** visible. Five animated tutorials show Move, Click, Right click, Scroll, and Select text. **Settings** holds feature controls; **Permissions** contains setup help.

1. **Permissions:** **Enable Accessibility** → turn on **Hand Mouse** (add `~/Applications/Hand Mouse.app` with **+** if needed).
2. Click **Start** → allow camera access.
3. **Show your hand and move to aim.** The pointer follows your index fingertip immediately; no special pose is required.
4. Try **Practice**: aim at **Send**, raise index + middle with the other fingers curled, and hold while the ring fills for one second. Open your hand to prepare another click. Practice also has scrolling and text-selection tasks. It sends no system input; afterward, enable the controls you want in **Settings** to use them in other apps.

An open hand prepares clicking. Raise index + middle with the other fingers curled, then hold for one second. Open your hand before the next click. No pose calibration is required.

Keep a trackpad or mouse nearby. **Esc** pauses capture. **Control + Option + Command + H** pauses or resumes from another app; change or disable this shortcut in **Permissions**.

## Setup with Codex

You need **macOS 13+**, a camera, and Apple's free **Xcode Command Line Tools**. Apple Silicon and Intel builds are supported; live testing so far is on Apple Silicon.

**Copy this prompt into Codex on your Mac:**

```text
Install Hand Mouse on this Mac from https://github.com/diegocp01/mac-hand-mouse.git.
Check that Apple's Xcode Command Line Tools are installed; if they are missing,
help me install them first. Clone the repository into a suitable local folder,
review its installation script, then run bash "Install Hand Mouse.command"
from the repository to build and install the app in ~/Applications.
If Hand Mouse is already running, help me quit it before installing.
Open the installed app and guide me through enabling Accessibility and
camera access. Show me where to launch it next time.
```

Codex can handle cloning, building, and installing. You may need to finish Apple's tools installer and approve macOS permissions yourself. The installer keeps a local signing identity so normal source updates can retain that approval. No ZIP download needed.

## Developer setup

If the Command Line Tools are missing, run `xcode-select --install` in Terminal and finish installation first. Then clone and install:

```sh
git clone https://github.com/diegocp01/mac-hand-mouse.git
cd mac-hand-mouse
bash "Install Hand Mouse.command"
```

The installer builds from source, installs **Hand Mouse** in `~/Applications`, and opens it. **Next time, open Hand Mouse from your home folder's Applications folder or search for it in Spotlight.** For editing, tests, and running a development build, see [development notes](docs/DEVELOPMENT.md).

After installing from a Git clone, use **Hand Mouse → Check for Updates…** in
the top-left menu. The app checks the official GitHub `main` branch. When an
update is available, **Update and Restart** pauses the camera, fast-forwards the
clean source checkout, rebuilds with the same local signing identity, and reopens
the installed app. This preserves normal Accessibility approval across updates.

The updater stops without changing the app if the checkout has uncommitted files,
is on another branch, has diverged from GitHub, or uses a different remote. Commit
developer work before updating. A packaged ZIP does not contain a source checkout;
clone the repository and run the installer once to enable source updates.
See [source-update behavior and safeguards](docs/UPDATES.md) for details.

## Use

1. Click **Start**. Show your hand and move to aim.
2. Move your index fingertip within the dashed box to aim. Its edges reach the screen edges; your palm can extend outside the box.
3. From an open hand, raise **index + middle** with the other fingers curled. The pointer holds its target and a ring fills for **one second**, then sends one left-click. Open your hand before the next click. Index-only aiming can also prepare a click.

Keep both fingers and their knuckles visible during the countdown. Lower the middle finger before it finishes to cancel. Keeping both fingers raised after a click does not repeat it. Excessive hand movement, missing tracking, a competing gesture, or **Esc** cancels the pending click.

**Point and hold replaces two-finger tap.** Your saved click choice is preserved. Bringing thumb + index + middle fingertips together scrolls; bringing all five fingertips together right-clicks. One-hand pinch dragging is unavailable in this mode.

- **Practice:** click **Send**, scroll to **Quarterly review**, or select a sentence without sending mouse events to other apps. Right clicks are counted separately. Finishing practice leaves clicks, scrolling, and selection off for that session without changing saved preferences.
- **Steady aim:** on by default in Settings. Slow, careful hand movements make smaller pointer adjustments; faster movements keep normal travel. After smoothing settles, the pointer stays at your fine adjustment. This responds to your movement, without detecting buttons or other targets. Turn it off to use the previous pointer behavior.
- **Right click:** bring all five fingertips together and hold briefly. Keep every fingertip visible so the camera can confirm the gesture. It sends one right-click; open your hand before doing it again, including after a canceled attempt.
- **Precision:** enable **Precision** for roughly 35% of normal hand-to-pointer travel. Lower and raise your hand to reposition when needed. The setting is saved.
- **Scroll:** enable **Scroll**, bring thumb + index + middle fingertips together and hold steady for about a quarter second, then move your hand up/down. Keep the ring and little fingertips separate from the pinch. The cursor stays put and clicks are suppressed. Release the pinch to stop immediately and resume aiming without a jump. Thumb + index alone does not scroll. Scrolling also works with Click off.
- **Click:** enabled by default. Turn it off to aim without clicking; your manual choice is saved. Practice leaves clicks off for the current session without changing that preference, so the next launch restores your saved choice or the default on.
- **Rest/reposition:** lower your hand, then show the same hand again. The pointer resumes where you left it.
- **Pause:** Esc, **Pause**, or the menu-bar hand icon. **⌃⌥⌘H** pauses/resumes from another app (configurable in Permissions).
- **Select text:** enable it, acquire one hand first, then form an L with thumb + index on both hands. Move the original hand to drag or select; open either hand to release. Clicks pause while the second hand acts as a modifier.

Gesture recognition uses camera images, not measured depth or physical contact. Good lighting and a visible palm help. Physical testing across hands and cameras is still needed, including five-finger visibility and Steady aim tuning; synthetic tests do not establish small-target accuracy. Start in practice. An explicit double-click gesture is not included. See [point-and-hold behavior and validation](docs/POINT_AND_HOLD.md).

## Test two-finger recognition with your camera

Diagnostics are **disabled in normal builds**. To enable them locally, change `FeatureFlags.diagnostics` from `false` to `true` in `Sources/FeatureFlags.swift`, quit the app, and rebuild with `bash "Launch Hand Mouse.command"`. Keep this local change out of commits and restore `false` before sharing a build. There is no user-facing setting or saved preference that enables diagnostics.

Choose **Practice → Click**, then **Show camera diagnostics** below the practice target. The panel uses the same camera and click detector as normal control, but Practice sends no system input. It shows the mirrored camera/skeleton, each finger's shape and minimum joint confidence, geometry ratios, hold progress, last cancellation reason, frame age/gap, and index movement. Confidence values are tracking scores, not probabilities. Hover over a finger row for the unchanged recognition cutoffs.

To collect a calibration baseline:

1. Choose an **Intent**: Free test, Aim only, One left click, or Cancel a hold. Labels describe what you intend, not what the app predicts.
2. Click **Record session**. This resets Click Practice and begins an in-memory numeric recording; it does not change gesture thresholds.
3. Perform one attempt, reopening your hand before clicking. Choose **Next attempt** before repeating. Changing Intent also begins a new attempt. Use this button rather than Practice's **Retry**, which resets the interaction and stops the recording.
4. Include successful clicks, missed clicks, ordinary non-click movements, and early cancellations. Repeat at comfortable distances and angles, changing one condition at a time.
5. Choose **Stop recording**, then **Export JSON…**. Review and share the file only if you want to. Nothing uploads automatically.

Recordings stop after three minutes or 9,000 events, and on pause, leaving Click Practice, camera changes, or interaction/settings resets. A stopped recording remains available for export even after **Esc**; unexported recordings disappear when the app quits. Starting another recording or discarding one requires confirmation when it contains samples. Exported files are not removed. The default export filename is ignored by Git; keep all real-hand recordings out of commits.

For development, with the diagnostics flag enabled and after `bash scripts/test.sh`, replay an explicitly exported session with:

```sh
build/practice-diagnostics-tests --replay "/path/to/hand-mouse-diagnostics.json"
```

Replay feeds the recorded selected-hand landmarks through the production finger classifier and the practice interaction engine, including recorded tracking interruptions. It reports decision differences, click counts, and missed/false clicks against your attempt labels. It does not start a camera, post mouse events, rerun Apple's Vision model, or automatically tune the detector. Fresh live-camera trials are still needed to validate any later threshold changes.

## Troubleshooting

- **Camera blocked:** click **Camera Settings**, enable Hand Mouse, then restart if macOS requests it.
- **Camera interrupted or disconnected:** reconnect it or close the other camera app, then click **Start** to retry. Hand Mouse rebuilds its capture session instead of silently restarting mouse control.
- **Hand detected, but mouse won't move:** enable Accessibility for the installed app.
- **Waiting to resume:** show the same hand with the index fingertip visible. If the pointer is on another display, move it onto the selected display first.
- **Two fingers do not click:** check that **Click** is enabled in **Settings**. Open your hand briefly first, then raise index + middle with ring and little fingers curled and hold still for one second. Keep both raised fingers visible; open your hand before retrying a canceled hold.
- **Right click is not recognized:** keep all five fingertips visible as they meet. A hidden fingertip cannot confirm this gesture. Open the hand before retrying.
- **Shortcut unavailable:** another app may own that combination. Choose the other shortcut or **Off** in **Permissions**. Hand Mouse must be running, and the Mac must be awake and in your active session.
- **Updating from v1.3.0 or earlier:** a one-time Accessibility repair is needed when moving to the persistent signing identity. Use **Show in Finder** to locate the new app, remove the old Hand Mouse entry in Accessibility, then add and enable that exact copy. Future source updates reuse its signer. [Why this changed](docs/SIGNING.md).
- **Permission is on but the pointer still won't move:** confirm that Accessibility lists the exact running app. If its entry is stale, replace it; toggling the old entry may not help. See the [targeted repair](docs/DEVELOPMENT.md#repair-a-stale-local-permission). On macOS 27 the pane is called **Device Control and Data Access**.
- **Tracking is intermittent:** improve lighting, keep your palm and fingertips visible. Start pointer control with one hand; show both hands for dragging.
- **Escape doesn't pause outside the app:** global Escape needs Accessibility permission; use the window or menu-bar pause button.
- **Unexpected clicks:** turn **Click** off. See [safety notes](docs/SAFETY.md).

## Privacy

Hand Mouse processes camera frames on your Mac. It never records or uploads video or audio, requests no microphone access, and includes no telemetry. By default it does not record hand landmarks. In locally enabled diagnostics builds, **Record session** in Click Practice explicitly opts into a bounded, in-memory record of selected-hand landmarks, confidence, relative timing, gesture decisions, attempt labels, and numeric display dimensions/aim settings. Only **Export JSON…** writes that recording to a location you choose; it excludes camera identifiers, screen content, device names, and machine uptime. No diagnostic data uploads automatically. Camera permission enables tracking. Accessibility permission enables mouse control and the Escape pause key. The resume shortcut registers a specific key combination with macOS; it does not collect a keyboard input stream.

## Build, test, and package

```sh
bash scripts/test.sh
bash Tests/install.sh
bash Tests/signing.sh
bash scripts/build.sh
bash scripts/package.sh
```

Packaging creates a universal Mac ZIP and checksum in `dist/`. These archives are locally signed and **not notarized**; downloaded binaries may be blocked by macOS. The source installer above is the supported setup path. See the [v1.3 system audit](docs/SYSTEM_AUDIT.md), [safety notes](docs/SAFETY.md), and [development notes](docs/DEVELOPMENT.md) for tuning, tests, and release details, and [CONTRIBUTING.md](CONTRIBUTING.md) for contributions.

## License

[MIT](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for Apple system frameworks and build tooling.
