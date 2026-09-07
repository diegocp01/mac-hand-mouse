![Hand Mouse: move your index finger to move the pointer](assets/hand-mouse.png)

# Hand Mouse

**Control your Mac's mouse with your hand.** Move your **index fingertip** to move the pointer. Choose **Pinch**, or teach the experimental **Point forward** gesture. Clicks start **off**. Runs locally with your camera and Apple's hand tracking — no accounts, cloud, or model downloads.

## First launch

The dark startup panel walks you through **Allow control → Start camera → Point & practice**. Each step reflects the current permission and camera state. **Start / Pause camera** stays visible while you scroll; **Gesture settings** keeps extra controls out of the way until you need them.

1. **Permissions & setup:** **Enable Accessibility** → turn on **Hand Mouse** (add `~/Applications/Hand Mouse.app` with **+** if needed).
2. **Start camera** → allow camera access.
3. Show **one hand**, palm visible; **index fingertip** moves the pointer inside the dashed guide.
4. Leave **Allow clicks** off while you practice. Expand **Gesture settings** to choose **Pinch**, or complete **Set up forward click** and its practice targets. Enable **Allow clicks** when ready.

Keep a trackpad or mouse nearby. **Esc** (or **Pause camera** / menu-bar hand) pauses capture.

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
| Move the pointer | Move your **index fingertip** inside the dashed box. Soft edges — no hard wall at the crop. |
| Practice without clicking | Leave **Allow clicks** unchecked (default). Aim freely; no mouse click is sent. |
| Practice without moving the system pointer | Uncheck **Move pointer with index finger**. |
| Turn on clicks | Check **Allow clicks**. Forward clicking requires setup and practice first; its clicks reset to off when the app relaunches. |
| Left-click — Pinch | Select **Pinch**. Touch **thumb + index** together briefly, then separate before the next click. |
| Left-click — Point forward (experimental) | Set up your two poses, aim, then point toward the camera as if touching the screen. Hold the forward pose until the ring fills. Pull back to cancel or rearm. |
| Adjust forward hold time | Choose **0.65**, **1**, or **1.5 seconds** (saved). A confirmed forward gesture starts this timer; ordinary stillness does not. |
| Easier pinches | Under **Pinch feel**, choose **Easy** (Pinch mode only; saved). |
| Practice a click target | Aim at **Test click** and fire a click; the count rises when the button receives it. |
| Pause | **Esc**, **Pause camera**, or the menu-bar hand icon. |

**Tips:** one hand, palm visible, even lighting. Closing the window pauses capture. For multiple monitors, put the app window on the screen you want before starting; the header names the display being controlled. Sleep, switching away from your Mac session, or a display configuration change pauses the camera. Start it again when ready.

### Set up Point forward

1. Expand **Gesture settings**, then select **Point forward** → **Set up forward click**. System pointer movement and clicks pause during setup.
2. Hold your usual pointing pose and press **Capture movement pose**. Keep it steady briefly. You can use **⌘⇧P** with your other hand to activate the capture button.
3. Point your index toward the camera as if touching the screen, with a small forward reach. Keep the finger and palm visible, then press **Capture forward pose** and hold it steady.
4. In the practice canvas, move the dot onto each green target, point forward, and hold. Pull back before trying the next target. These are simulated clicks, with no input sent to other apps.
5. Hit both targets, press **Finish practice**, then turn on **Allow clicks** when ready.

This mode uses **2D pose changes**, not measured depth. It may confuse a hand rotation or change in seating distance with the taught gesture, and pointing directly at the lens can hide your finger joints. If the two poses cannot be distinguished reliably in practice, choose **Pinch**. Calibration stays in memory for this app session; repeat it after relaunching, changing cameras, or changing your hand/camera position. [How it works and testing limits](docs/FORWARD_CLICK.md).

Upgrading from **Dwell** selects **Point forward** with clicks off and setup required. Automatic hold-still clicking has been removed.

### See the click coming

After the forward gesture is confirmed, a ring fills **around the system pointer**, with a **Click in 0.6 s…** caption even while you work in another app. The target stays fixed during the forward gesture. Pull back or move your hand sideways to cancel. After one click, return to your movement pose before pointing forward again. Moving the pointer or holding the movement pose starts no countdown.

The countdown uses tracked frames, so it clears if your hand disappears, tracking stalls, the camera pauses, permissions change, or clicks are turned off. With **Allow clicks** off, you can point freely without a countdown or a frozen pointer. The floating ring passes mouse clicks through to the target.

Camera status stays separate from click instructions: **Starting camera**, **Hand tracked**, **Looking for hand**, and **Paused**. You can resize the window and scroll to settings; the pause control stays visible at the top. **Esc** also pauses.

**Hand colors:** green = tracking · blue = click gesture recognized · white flash + **Clicked ✓** = click events posted. Text, a progress bar, and checkmarks explain the same states without relying on color; the target application may still reject a click.

## What it does *not* do (yet)

Dragging, scrolling, right-click, double-click, and tap-to-click are **not** included. Keep your physical mouse/trackpad available.

## Troubleshooting

- **Camera blocked:** click **Camera Settings**, enable Hand Mouse, then restart if macOS requests it.
- **Camera interrupted or disconnected:** reconnect it or close the other camera app, then click **Start camera** to retry. Hand Mouse rebuilds its capture session instead of silently restarting mouse control.
- **Hand detected, but mouse won't move:** enable Accessibility for the installed app.
- **Updating from v1.3.0 or earlier:** a one-time Accessibility repair is needed when moving to the persistent signing identity. Use **Show in Finder** to locate the new app, remove the old Hand Mouse entry in Accessibility, then add and enable that exact copy. Future source updates reuse its signer. [Why this changed](docs/SIGNING.md).
- **Permission is on but the pointer still won't move:** confirm that Accessibility lists the exact running app. If its entry is stale, replace it; toggling the old entry may not help. See the [targeted repair](docs/DEVELOPMENT.md#repair-a-stale-local-permission). On macOS 27 the pane is called **Device Control and Data Access**.
- **Tracking is intermittent:** improve lighting, keep your palm and fingertips visible, and show only one hand.
- **Escape doesn't pause outside the app:** global Escape needs Accessibility permission; use the window or menu-bar pause button.
- **Unexpected clicks:** turn **Allow clicks** off (default). See [safety notes](docs/SAFETY.md).

## Privacy

Hand Mouse processes camera frames on your Mac. It does not record or upload video, hand landmarks, or keystrokes; it requests no microphone access and includes no telemetry. Camera permission enables tracking. Accessibility permission enables mouse control and the Escape pause key.

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
