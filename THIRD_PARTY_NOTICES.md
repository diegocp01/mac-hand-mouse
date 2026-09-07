# Third-party components

Hand Mouse contains no vendored third-party libraries or model weights. It uses Apple system frameworks supplied with macOS: AppKit, AVFoundation, Vision, CoreGraphics, Foundation, and ApplicationServices. Apple's software and system resources remain subject to Apple's terms; this repository's MIT license covers its original code and documentation.

Hand tracking uses [VNDetectHumanHandPoseRequest](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest). No model download or external inference service is configured by this app.

GitHub Actions uses [actions/checkout](https://github.com/actions/checkout) and [actions/upload-artifact](https://github.com/actions/upload-artifact). Their source is not bundled with the app.
