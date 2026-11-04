# Contributing to ShutterBridge

Bug reports, device compatibility reports and focused pull requests are welcome.

Before reporting a bug, update both clients, keep iPhone foreground/unlocked and read the README troubleshooting/setup guides. Include Windows/iOS/browser versions, iPhone model, selected camera/mode, expected behavior and exact error. Do not attach live Wi-Fi keys, PINs, Apple IDs, passwords, signing material or private footage.

For code changes, explain the user-visible issue and how you verified it. Run the Windows tests and dependency check documented in README. Build the iOS project when changing Swift/Xcode code. Clearly separate simulated checks from physical hardware tests. Do not claim new device/mode support without measured saved-file dimensions/FPS.

Keep camera/microphone/network permissions visible. Preserve foreground-only recording and local originals. Do not introduce telemetry, cloud upload, hardcoded secrets or background capture.

By contributing, you agree your contributions are provided under this project's MIT license.
