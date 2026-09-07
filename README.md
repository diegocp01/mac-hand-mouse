![Hand Mouse: move your index finger to move the pointer](assets/hand-mouse.png)

# Hand Mouse

**Control your Mac's mouse with your hand.** Move your **index fingertip** to move the pointer. Choose **Pinch**, or teach the experimental **Point forward** gesture. Clicks start **off**. Runs locally with your camera and Apple's hand tracking — no accounts, cloud, or model downloads.

## First launch

Camera status and **Start / Pause camera** stay at the top. Pointer and click controls sit below the preview; expand **Permissions & setup** when needed.

1. **Permissions & setup:** **Enable Accessibility** → turn on **Hand Mouse** (add `~/Applications/Hand Mouse.app` with **+** if needed).
2. **Start camera** → allow camera access.
3. Show **one hand**, palm visible, with thumb + index separated. Keep it steady briefly to take control. Your index then moves the pointer from its current position.
4. Leave **Allow clicks** off while you practice. Choose **Pinch**, or complete **Set up forward click** and its practice targets. Enable **Allow clicks** when ready.

Keep a trackpad or mouse nearby. **Esc** pauses capture. **Control + Option + Command + H** pauses or resumes from another app; change or disable this shortcut in **Permissions & setup**.

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

## Use

| Action | How |
| --- | --- |
| Move the pointer | Show a steady, open hand briefly, then move your **index fingertip** inside the dashed box. |
| Rest and reposition your hand | Lower your hand, then return with thumb + index separated (or your taught movement pose). After a brief steady hold, movement resumes from the current cursor without jumping. |
| Practice without clicking | Leave **Allow clicks** unchecked (default). Aim freely; no mouse click is sent. |
| Practice clicks and scrolling safely | Choose **Practice safely** (or **⌘⇧T** in the app). Practice uses a simulated pointer, targets, and scroll counter. |
| Preview with all system input off | Uncheck **Move the system pointer with my index finger**. |
| Turn on clicks | Check **Allow clicks**. Forward clicking requires setup and practice first; its clicks reset to off when the app relaunches. |
| Left-click — Pinch | Select **Pinch**. Touch **thumb + index** together briefly, then separate before the next click. |
| Left-click — Point forward (experimental) | Set up your two poses, aim, then point toward the camera as if touching the screen. Hold the forward pose until the ring fills. Pull back to cancel or rearm. |
| Adjust forward hold time | Choose **0.65**, **1**, or **1.5 seconds** (saved). A confirmed forward gesture starts this timer; ordinary stillness does not. |
| Easier pinches | Under **Pinch feel**, choose **Easy** (Pinch mode only; saved). |
| Practice a click target | Aim at **Test click** and fire a click; the count rises when the button receives it. |
| Pause | **Esc**, **Pause camera**, or the menu-bar hand icon. |
| Pause / resume from another app | **⌃⌥⌘H** by default. Choose **⌃⌥⌘M** or **Off** in **Permissions & setup** if needed. |
| Scroll (opt-in) | Enable **Allow two-finger scrolling**. Hold index + middle extended with ring + little folded, then move up/down. Lower the middle finger to return to pointing. |

**Tips:** one hand, palm visible, even lighting. Closing the window pauses capture. For multiple monitors, put the app window on the screen you want before starting; the header names the display being controlled. Sleep, switching away from your Mac session, or a display configuration change pauses the camera. Start it again when ready.

The app keeps the controlling hand's left/right side for the current session. Pause and restart to choose another hand. Returning with a closed pinch, uncertain tracking, or a different hand cannot immediately move or click. If you use the physical mouse, the next activation starts from its new position. Keep the pointer on the chosen display; Hand Mouse will not pull it back from another display.

### Practice without controlling other apps

Choose **Pinch** → **Practice safely** to go straight to a simulated target. For **Point forward**, teach the two poses first. Open your hand and keep it steady briefly, move the dot onto green, then click with the selected gesture. Enable **Try two-finger scrolling in practice** to change the scroll counter. Finishing or canceling practice leaves real clicks and scrolling **off**. Camera access is required; Accessibility is not needed for practice.

### Two-finger scrolling

Scrolling is **off by default**, with a separate control from **Allow clicks**. After normal pointing is active, show just index + middle extended, with ring + little folded. Hold the pose briefly; a **Scrolling ↑↓** caption appears at the pointer. Move up to scroll toward the top of the page, or down toward the bottom. The pointer stays fixed and clicks are suppressed. Stopping your fingers stops scrolling; there is no inertia. Lower the middle finger and return to a steady movement pose to resume pointing.

Try the scroll counter in practice first. Camera occlusion or unclear finger shapes can interrupt scrolling; this gesture still needs broader hands-on testing. It uses standard pixel scroll events, whose effect can vary between applications.

### Set up Point forward

1. Select **Point forward** → **Set up forward click**. System pointer movement and clicks pause during setup.
2. Hold your usual pointing pose and press **Capture movement pose**. Keep it steady briefly. You can use **⌘⇧P** with your other hand to activate the capture button.
3. Point your index toward the camera as if touching the screen, with a small forward reach. Keep the finger and palm visible, then press **Capture forward pose** and hold it steady.
4. In the practice canvas, move the dot onto each green target, point forward, and hold. Pull back before trying the next target. These are simulated clicks, with no input sent to other apps.
5. Hit both targets, press **Finish practice**, then turn on **Allow clicks** when ready.

This mode uses **2D pose changes**, not measured depth. It may confuse a hand rotation or change in seating distance with the taught gesture, and pointing directly at the lens can hide your finger joints. If the two poses cannot be distinguished reliably in practice, choose **Pinch**. Calibration stays in memory for this app session; repeat it after relaunching, changing cameras, or changing your hand/camera position. [How it works and testing limits](docs/FORWARD_CLICK.md).

Upgrading from **Dwell** selects **Point forward** with clicks off and setup required. Automatic hold-still clicking has been removed.

### See the click coming

After the forward gesture is confirmed, a ring fills **around the system pointer**, with a **Click in 0.6 s…** caption even while you work in another app. The target stays fixed during the forward gesture. Pull back or move your hand sideways to cancel. After one click, return to your movement pose before pointing forward again. Moving the pointer or holding the movement pose starts no countdown.

The countdown uses tracked frames, so it clears if your hand disappears, tracking stalls, the camera pauses, permissions change, or clicks are turned off. With clicks and scrolling off, pointing has no gesture-induced freeze or countdown after activation. The floating ring passes mouse clicks through to the target.

Camera status stays separate from click instructions: **Starting camera**, **Hand tracked**, **Looking for hand**, and **Paused**. You can resize the window and scroll to settings; the pause control stays visible at the top. **Esc** also pauses.

**Hand colors:** green = tracking · blue = click gesture recognized · white flash + **Clicked ✓** = click events posted. Text, a progress bar, and checkmarks explain the same states without relying on color; the target application may still reject a click.

## What it does *not* do (yet)

Dragging, right-click, double-click, and tap-to-click are **not** included. Keep your physical mouse/trackpad available.

## Troubleshooting

- **Camera blocked:** click **Camera Settings**, enable Hand Mouse, then restart if macOS requests it.
- **Camera interrupted or disconnected:** reconnect it or close the other camera app, then click **Start camera** to retry. Hand Mouse rebuilds its capture session instead of silently restarting mouse control.
- **Hand detected, but mouse won't move:** enable Accessibility for the installed app.
- **Waiting to resume:** open thumb + index (or return to your calibrated movement pose), use the same hand, and keep it steady briefly. If the pointer is on another display, move it onto the selected display first.
- **Shortcut unavailable:** another app may own that combination. Choose the other shortcut or **Off** in **Permissions & setup**. Hand Mouse must be running, and the Mac must be awake and in your active session.
- **Updating from v1.3.0 or earlier:** a one-time Accessibility repair is needed when moving to the persistent signing identity. Use **Show in Finder** to locate the new app, remove the old Hand Mouse entry in Accessibility, then add and enable that exact copy. Future source updates reuse its signer. [Why this changed](docs/SIGNING.md).
- **Permission is on but the pointer still won't move:** confirm that Accessibility lists the exact running app. If its entry is stale, replace it; toggling the old entry may not help. See the [targeted repair](docs/DEVELOPMENT.md#repair-a-stale-local-permission). On macOS 27 the pane is called **Device Control and Data Access**.
- **Tracking is intermittent:** improve lighting, keep your palm and fingertips visible, and show only one hand.
- **Escape doesn't pause outside the app:** global Escape needs Accessibility permission; use the window or menu-bar pause button.
- **Unexpected clicks:** turn **Allow clicks** off (default). See [safety notes](docs/SAFETY.md).

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
