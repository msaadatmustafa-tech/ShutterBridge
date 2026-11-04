# ShutterBridge 1.5.0

A local-first SayCheese alternative: control your iPhone camera from Windows Bluetooth or an Android/laptop browser, with optional live Wi-Fi preview and local recording up to 4K60.

## Downloads

- **ShutterBridge-Windows-v1.5.exe** — Windows controller, unsigned. No Python required for this binary.
- **ShutterBridge-iPhone-v1.5-unsigned.ipa** — iPhone companion v1.5/build 8. Must be personally signed/installed using Sideloadly on Windows or your own signing tools; not directly installable or App Store signed.
- **ShutterBridge-v1.5.0-source.zip** — current source, setup guides, license and verification notes.
- **SHA256SUMS.txt** — download checksums.

## Setup

Follow README and the Windows + iPhone installation guide. Keep iPhone foreground/unlocked. Native Windows commands use Bluetooth and the phone's six-digit session PIN. Optional Android/laptop browser controls use a trusted local Wi-Fi and the explicit iPhone remote-controls toggle.

## Verified

19 Windows tests passed. Real physical iPhone tests covered 4K/1080p/720p at 30/60 FPS on front and back cameras (12 combinations), with saved-file metadata and Photos success; owner confirmed Gallery saves. Real Windows EXE BLE authentication, quality apply and Start/Stop passed. The iPhone-hosted browser UI was tested end-to-end from Windows Chrome. iOS cloud build and Sideloadly installation succeeded.

## Limits

Modes are camera/device dependent. Preview is a reduced-resolution silent framing feed, not a 4K stream. No app-imposed duration cutoff; storage, heat, battery and iOS interruptions still apply. Extended capture and broad-device testing remain outstanding. No Apple passwords or signing credentials are included.

Built by @msaadatmustafa-tech. If it helps your shoots, give ShutterBridge a star!
