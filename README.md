![Hand Mouse: move your index finger to move the pointer](assets/hand-mouse.png)

# Hand Mouse

**Control your Mac's mouse with your hand.** Move your **index fingertip** to move the pointer. Choose **Pinch** or the experimental **Point forward** gesture — no pose setup required. Clicks default **on**; the camera starts paused. Runs locally with your camera and Apple's hand tracking — no accounts, cloud, or model downloads.

## First launch

The dark startup panel walks you through **Permissions → Camera → Pointer**. Each step reflects the current permission and camera state. The starting-pose guide and **Start / Pause camera** stay visible while you scroll; **Gesture settings** keeps extra controls out of the way until you need them.

1. **Permissions:** **Enable Accessibility** → turn on **Hand Mouse** (add `~/Applications/Hand Mouse.app` with **+** if needed).
2. **Start camera** → allow camera access.
3. **Point your index finger UP**, with your **palm toward the camera** and **thumb apart**. Hold still for about a second until the app says **Pointer ready**. Then move your index fingertip to aim inside the dashed guide.
4. Expand **Gesture settings** to choose **Pinch** or **Point forward**, then enable **Allow clicks** when ready. Forward clicking adapts automatically as you aim; **Practice safely** lets you try either mode without sending system input.

The starting pose comes **before** the click gesture. In Point forward mode, first raise your index to start pointer control; aim at the target, then point toward the camera to click. If the app says **Waiting to resume**, repeat the starting pose. No capture button or calibration wizard is required.

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

| Action | How |
| --- | --- |
| Move the pointer | Show a steady, open hand briefly, then move your **index fingertip** inside the dashed box. Its edges map to the screen edges; your palm may extend outside it. |
| Rest and reposition your hand | Lower your hand, then return with thumb + index separated (or ordinary extended pointing in Forward mode). After a brief steady hold, movement resumes from the current cursor without jumping. |
| Aim with clicks off | Uncheck **Allow clicks**. Aim freely; no mouse click is sent. |
| Preview only | Uncheck **Move pointer**. |
| Practice safely | Try simulated Pinch or Point forward targets and a scroll counter. No system pointer, click, or scroll input is sent. |
| Turn on clicks | Check **Allow clicks**. Enabled on new installs; an existing saved choice is preserved. No pose capture or practice targets are required. |
| Drag / select with one hand (opt-in, experimental) | Choose **Pinch**, enable **Pinch to drag** and **Allow clicks**. Pinch + release to click; hold + move your hand to drag or select text; release to finish. |
| Drag / select with two hands (opt-in, experimental) | Enable **Allow two-hand L dragging** in **Gesture settings**. Aim with one hand first. Make an **L with thumb + index on both hands**, other fingers folded. Hold briefly, then move your **original pointer hand** to drag. Open either hand to release. Requires **Allow clicks**. |
| Left-click — Pinch | Select **Pinch**. Touch **thumb + index** together briefly, then separate before the next click. |
| Left-click — Point forward (experimental) | Aim with your index extended, then point toward the camera as if touching the screen. Hold the forward pose until the ring fills. Pull back to cancel or rearm. |
| Adjust forward hold time | Choose **0.65**, **1**, or **1.5 seconds** (saved). A confirmed forward gesture starts this timer; ordinary stillness does not. |
| Easier pinches | Under **Pinch feel**, choose **Easy** (Pinch mode only; saved). |
| Practice a click target | Aim at **Test click** and fire a click; the count rises when the button receives it. |
| Pause | **Esc**, **Pause camera**, or the menu-bar hand icon. |
| Pause / resume from another app | **⌃⌥⌘H** by default. Choose **⌃⌥⌘M** or **Off** in **Permissions** if needed. |
| Scroll (opt-in) | In **Gesture settings**, enable **Allow two-finger scrolling**. Hold index + middle extended with ring + little folded, then move up/down. Lower the middle finger to return to pointing. |

**Tips:** start with one hand, palm visible, even lighting. Add the other hand only as the drag modifier; it never becomes a second pointer. Closing the window pauses capture. For multiple monitors, put the app window on the screen you want before starting; the header names the display being controlled. Sleep, switching away from your Mac session, or a display configuration change pauses the camera. Start it again when ready.

### Reaching corners comfortably

The dashed box marks **fingertip travel**, not a boundary for your whole hand. The
smaller central region reaches all screen edges while leaving room for your palm
in the camera view. Keep the whole hand visible to the camera; the palm can extend
outside the dashed box. After you lower and return your hand, the cursor stays
where you left it and the guide adjusts to the new pointing position. Reverse
direction to leave an edge without moving through an invisible dead zone.

Start with your hand near the camera's center for comfortable travel in every
direction. If tracking is lost, lower the hand and return centrally with index up,
palm toward the camera, and thumb apart; wait briefly for **Pointer ready**.

### One-hand pinch dragging (experimental)

In **Gesture settings**, choose **Pinch** and enable **Pinch to drag**. It starts off and requires **Allow clicks**. Aim with your index finger, then pinch thumb + index. Release for a click; keep pinching and move your whole hand to drag or select text. Open the pinch to finish. The pointer stays still during finger closure and follows the palm during dragging.

Choose one drag method at a time; enabling either disables the other. Switching to **Point forward** turns pinch dragging off. In **Practice safely**, enable **Try pinch dragging** to rehearse without controlling other apps. Finishing practice turns clicks, scrolling, and both drag methods off.

Keep your palm and fingertips visible. Uncertain tracking releases an existing press; open your pinch to reacquire before continuing. A release can complete the click or drop already in progress in the target app. Physical camera testing is still needed; see [one-hand design and checks](docs/ONE_HAND_DRAG.md).

### Two-hand dragging and text selection (experimental)

This feature starts **off**. In **Gesture settings**, enable **Allow two-hand L dragging** and **Allow clicks**. Try **Practice safely** first; enable the practice dragging checkbox there. Finishing practice turns dragging, clicks, and scrolling off.

1. Start with **one hand** and wait for **Pointer ready**. Aim at the beginning of the text or the item to drag.
2. Bring your other hand into view. The original hand keeps the pointer; the second hand is a **drag modifier**. With two-hand dragging enabled, single-hand clicking and scrolling are suspended while the second hand is visible.
3. On **both hands**, extend thumb and index into an **L**, with middle, ring, and little fingers folded. Keep palms visible. Hold for about **a quarter second**. A ring beside the cursor shows confirmation progress, then **Dragging** appears.
4. Move the **original pointer hand** to extend the selection or drag the item. The second hand holds the gesture and never moves the pointer.
5. **Open either hand** to release. You can also lower a hand or press **Esc**. After release or lost tracking, open either hand briefly (at least 0.12 seconds with reliable tracking), then form the pair again. An uncertain pose releases the button but does not rearm it.

This works with either Pinch or Point forward selected and uses **Allow clicks** to enable button input. **Practice safely** shows a simulated selection trail without sending system input. If both hands appear before the pointer is acquired, lower one to establish the owner first. Pause/restart to switch the owner.

Tracking loss, stale frames, camera pause, settings changes, and leaving practice release or cancel a drag. Losing the original hand never transfers control to the remaining hand. Ownership uses left/right handedness, not biometric identity. L recognition needs physical testing across users and cameras; see [two-hand design and checks](docs/TWO_HAND_DRAG.md).

### If pointing does not start a click

Pointer tracking and click recognition are separate. Keep the index straight and
turn it slightly sideways so the camera can see its fingertip and joints; pointing
directly into the lens can hide them. Keep your palm and knuckles visible, aim
again, then point forward at a slight angle. The app now tells you whether the
index, palm, or finger shape is unclear. No timer runs while the pose is unclear.
Choose **Pinch** in **Gesture settings** if forward pointing is uncomfortable.

### Point forward — no pose setup

Expand **Gesture settings**, select **Point forward**, start the camera, and enable **Allow clicks**. Move your index to aim, then point it toward the camera as if touching the screen. The app automatically accounts for your hand's size and visible finger length while you aim. There are no capture buttons, saved poses, or required practice clicks, and the reference can adapt while the pointer moves. Starting or returning after tracking loss still requires a brief steady pointing pose before taking over the current cursor.

**Practice safely** opens a canvas for the selected click mode and pauses all system input. Use **Try two-finger scrolling in practice** to test the scroll counter. **Finish practice** is always available, even with zero hits; it leaves real clicks and scrolling off. **⌘⇧T** toggles practice while Hand Mouse is focused. The same camera tracking and cursor recovery run in practice, without requiring Accessibility.

Forward clicking still uses **2D pose changes**, not measured depth. Hand rotation can resemble a forward point, and pointing directly into the lens can hide joints. Keep your palm and index visible; use Pinch if recognition is inconsistent. [Detection and testing limits](docs/FORWARD_CLICK.md).

Upgrading from the old **Dwell** mode selects **Point forward** with clicks off once. Automatic hold-still clicking remains removed.

### See the click coming

After the forward gesture is confirmed, a ring fills **around the system pointer**, with a **Click in 0.6 s…** caption even while you work in another app. The target stays fixed during the forward gesture. Pull back or move your hand sideways to cancel. After one click, return to your movement pose before pointing forward again. Moving the pointer or holding the movement pose starts no countdown.

The countdown uses tracked frames, so it clears if your hand disappears, tracking stalls, the camera pauses, permissions change, or clicks are turned off. With clicks and scrolling off, pointing has no gesture-induced freeze or countdown after activation. The floating ring passes mouse clicks through to the target.

Camera status stays separate from click instructions: **Starting camera**, **Hand tracked**, **Looking for hand**, and **Paused**. You can resize the window and scroll to settings; the pause control stays visible at the top. **Esc** also pauses.

**Hand colors:** green = tracking · blue = click gesture recognized · white flash + **Clicked ✓** = click events posted. Text, a progress bar, and checkmarks explain the same states without relying on color; the target application may still reject a click.

## What it does *not* do (yet)

Right-click, double-click, and tap-to-click are **not** included. Dragging and text selection are available with the optional one-hand pinch or two-hand L gestures above. Keep your physical mouse/trackpad available.

## Troubleshooting

- **Camera blocked:** click **Camera Settings**, enable Hand Mouse, then restart if macOS requests it.
- **Camera interrupted or disconnected:** reconnect it or close the other camera app, then click **Start camera** to retry. Hand Mouse rebuilds its capture session instead of silently restarting mouse control.
- **Hand detected, but mouse won't move:** enable Accessibility for the installed app.
- **Waiting to resume:** point your index **up**, palm **toward the camera**, and thumb **apart**. Hold still for about a second until **Pointer ready**; then aim. A finger already pointing into the lens may hide its length. Use the same hand; if the pointer is on another display, move it onto the selected display first.
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
