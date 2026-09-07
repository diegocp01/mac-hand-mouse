# Contributing

Keep changes focused and describe the user-visible behavior they improve. Run `bash scripts/test.sh` and `bash scripts/build.sh` before opening a pull request. For installer or packaging changes, also run `bash Tests/install.sh` and `bash scripts/package.sh`. Quit the destination app before building, or use a separate `HAND_MOUSE_BUILD_DIR`.

Preserve separate-fingers-to-rearm behavior, paired mouse-down/up events, tracking-loss disarming, and the pause controls. Add behavior-focused tests for gesture changes. Report the macOS version, Mac architecture, camera, and lighting when sharing manual test results. Do not claim physical tracking was tested when only synthetic tests ran.

Avoid identifiable camera images, unrelated screen content, and private paths in reports. Build output and archives are ignored by Git. Contributions are provided under the repository's MIT license. See [development notes](docs/DEVELOPMENT.md) for code structure and packaging.
