![Hand Mouse: move your index finger to move the pointer](assets/hand-mouse.png)

# Hand Mouse

**Control your Mac's mouse with your hand.** Move your **index fingertip** to move the pointer. Click by bending **index + middle fingers together**, then lifting them, like tapping a trackpad in the air. Clicks default **on**; the camera starts paused. Runs locally with your camera and Apple's hand tracking — no accounts, cloud, or model downloads.

## First launch

The dark startup panel walks you through **Permissions → Camera → Pointer**. Each step reflects the current permission and camera state. The starting-pose guide and **Start / Pause camera** stay visible while you scroll; **Gesture settings** keeps extra controls out of the way until you need them.

1. **Permissions:** **Enable Accessibility** → turn on **Hand Mouse** (add `~/Applications/Hand Mouse.app` with **+** if needed).
2. **Start camera** → allow camera access.
3. **Raise index + middle fingers**, with your **palm toward the camera**. Hold still briefly until **Pointer ready**, then move your index fingertip to aim inside the dashed guide.
4. Enable **Allow clicks** when ready. Bend both fingers down together, then lift to click. **Practice safely** lets you try taps without sending system input.

The starting pose comes **before** the click gesture. Raise index + middle to start, then bend and lift both together to click. No pose calibration is required.

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

1. Click **Start camera**. Raise **index + middle fingers**, palm toward the camera, and hold steady briefly until **Pointer ready**.
2. Move your index fingertip within the dashed box to aim. Its edges reach the screen edges; your palm can extend outside the box.
3. Raise both fingers, **bend index + middle down together**, then **lift them together** to click, like tapping a trackpad in the air. Complete the tap within roughly half a second.

The pointer freezes during the tap. **Lift to click** appears beside the system cursor, including over other apps. A completed tap clicks once; holding still never clicks. Keep both fingers and their knuckles visible. Missing tracking, a long hold, or **Esc** cancels the pending tap. Raise both fingers again before retrying.

**Two-finger tap replaces Pinch and Point forward clicking.** Existing Allow clicks choices remain saved. Two-finger scrolling and one-hand pinch dragging are unavailable in this mode; their saved preferences are retained but do not activate. The same fingers must not scroll and click together.

- **Practice safely:** rehearse taps on targets without sending mouse events to other apps. Finishing practice leaves clicks off.
- **Allow clicks:** turn off to aim without clicking.
- **Rest/reposition:** lower your hand, then raise index + middle centrally and hold briefly. The pointer resumes where you left it.
- **Pause:** Esc, Pause camera, or the menu-bar hand icon. **⌃⌥⌘H** pauses/resumes from another app (configurable in Permissions).
- **Two-hand drag (experimental):** enable the option, acquire one hand first, then form an L with thumb + index on both hands. Move the original hand to drag; open either hand to release. Clicks pause while the second hand acts as a modifier.

Tap recognition uses camera images, not measured depth or physical contact. Good lighting and a visible palm help. Physical testing across hands and cameras is still needed; start in practice. Right-click and an explicit double-click gesture are not included. See [tap behavior and validation](docs/TWO_FINGER_TAP.md).

## Troubleshooting

- **Camera blocked:** click **Camera Settings**, enable Hand Mouse, then restart if macOS requests it.
- **Camera interrupted or disconnected:** reconnect it or close the other camera app, then click **Start camera** to retry. Hand Mouse rebuilds its capture session instead of silently restarting mouse control.
- **Hand detected, but mouse won't move:** enable Accessibility for the installed app.
- **Waiting to resume:** raise index + middle, palm **toward the camera**. Hold still for about a second until **Pointer ready**; then aim. A finger already pointing into the lens may hide its length. Use the same hand; if the pointer is on another display, move it onto the selected display first.
- **Shortcut unavailable:** another app may own that combination. Choose the other shortcut or **Off** in **Permissions**. Hand Mouse must be running, and the Mac must be awake and in your active session.
- **Updating from v1.3.0 or earlier:** a one-time Accessibility repair is needed when moving to the persistent signing identity. Use **Show in Finder** to locate the new app, remove the old Hand Mouse entry in Accessibility, then add and enable that exact copy. Future source updates reuse its signer. [Why this changed](docs/SIGNING.md).
- **Permission is on but the pointer still won't move:** confirm that Accessibility lists the exact running app. If its entry is stale, replace it; toggling the old entry may not help. See the [targeted repair](docs/DEVELOPMENT.md#repair-a-stale-local-permission). On macOS 27 the pane is called **Device Control and Data Access**.
- **Tracking is intermittent:** improve lighting, keep your palm and fingertips visible. Start pointer control with one hand; show both hands for dragging.
- **Escape doesn't pause outside the app:** global Escape needs Accessibility permission; use the window or menu-bar pause button.
- **Unexpected clicks:** turn **Allow clicks** off. See [safety notes](docs/SAFETY.md).

## Privacy

Hand Mouse processes camera frames on your Mac. It does not record or upload video, hand landmarks, or keystrokes; it requests no microphone access and includes no telemetry. Camera permission enables tracking. Accessibility permission enables mouse control and the Escape pause key. The resume shortcut registers a specific key combination with macOS; it does not collect a keyboard input stream.

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
