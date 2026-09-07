![Hand Mouse: move your index finger to move the pointer, then pinch to click](assets/hand-mouse.png)

# Hand Mouse

**Control your Mac's mouse with your hand.** Move your index finger to move the pointer, then pinch your thumb and index finger together to click. Runs locally using your camera and Apple's hand tracking—no accounts, cloud services, or model downloads.

## Install

You need **macOS 13+**, a camera, and Apple's free **Xcode Command Line Tools**. Apple Silicon and Intel builds are supported; live testing so far is on Apple Silicon.

1. Click **Code → Download ZIP** on this GitHub page, then unzip it.
2. If you haven't installed Apple's developer tools, open Terminal, run `xcode-select --install`, and let installation finish. This is a one-time step.
3. Double-click **Install Hand Mouse.command** in the unzipped folder. It builds the app, installs it in your user's **Applications** folder, and opens it.
4. Click **Enable Accessibility**, then turn on **Hand Mouse** in System Settings. If it isn't listed, click **+** and select `~/Applications/Hand Mouse.app`.
5. Click **Start camera** and allow camera access. You're ready.

If the downloaded installer is blocked, you can build from the source you reviewed: open Terminal in the unzipped folder and run `bash "Install Hand Mouse.command"`. Future launches: open **Hand Mouse** from your user's Applications folder. Quit it before reinstalling or updating.

## Use

| Action | Gesture or control |
| --- | --- |
| Move the pointer | Move your **index fingertip** inside the dashed box. |
| Left-click | Touch **thumb + index fingertip** together briefly. Separate them before clicking again. |
| Pause | Press **Esc**, click **Pause camera**, or use the menu-bar hand icon. |
| Practice without moving the mouse | Uncheck **Control mouse pointer**. |

Show one hand, keep your palm visible, and use even lighting. Holding a pinch clicks only once. Closing the window pauses capture. For multiple monitors, put the app window on your chosen screen before starting.

## Troubleshooting

- **Camera blocked:** click **Camera Settings**, enable Hand Mouse, then restart if macOS requests it.
- **Hand detected, but mouse won't move:** enable Accessibility for the installed app.
- **Permission stopped working after an update:** remove the old Accessibility entry, add the current app, and enable it again. Locally signed builds can require this after changes.
- **Tracking is intermittent:** improve lighting, keep your palm and fingertips visible, and show only one hand.
- **Escape doesn't pause outside the app:** global Escape needs Accessibility permission; use the window or menu-bar pause button.

Currently supports pointer movement and single left-clicks. Dragging, scrolling, right-clicking, and double-click gestures are not included. Keep your trackpad or physical mouse available while trying it.

## Privacy

Hand Mouse processes camera frames on your Mac. It does not record or upload video, hand landmarks, or keystrokes; it requests no microphone access and includes no telemetry. Camera permission enables tracking. Accessibility permission enables mouse control and the Escape pause key.

## Build, test, and package

```sh
bash scripts/test.sh
bash scripts/build.sh
bash scripts/package.sh
```

Packaging creates a universal Mac ZIP and checksum in `dist/`. These archives are locally signed and **not notarized**; downloaded binaries may be blocked by macOS. The source installer above is the supported setup path. See [development notes](docs/DEVELOPMENT.md) for tuning, tests, and release details, and [CONTRIBUTING.md](CONTRIBUTING.md) for contributions.

## License

[MIT](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for Apple system frameworks and build tooling.
