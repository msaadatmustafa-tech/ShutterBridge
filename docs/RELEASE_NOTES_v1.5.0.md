## Your iPhone camera. Remotely controlled.

A local-first SayCheese alternative: control your iPhone camera from Windows Bluetooth or an Android/laptop browser, with optional live Wi-Fi preview and local recording up to 4K60.

### Choose your download

| Package | Direct download | How to use it |
|---|---|---|
| **Windows desktop app** | [Download EXE](https://github.com/msaadatmustafa-tech/ShutterBridge/releases/download/v1.5.0/ShutterBridge-Windows-v1.5.exe) | Run on Windows with BLE; no Python required |
| **iPhone v1.5 / build 8** | [Download unsigned IPA](https://github.com/msaadatmustafa-tech/ShutterBridge/releases/download/v1.5.0/ShutterBridge-iPhone-v1.5-unsigned.ipa) | Personally sign/install using Sideloadly on Windows |
| **Release source snapshot** | [Download v1.5.0 ZIP](https://github.com/msaadatmustafa-tech/ShutterBridge/releases/download/v1.5.0/ShutterBridge-v1.5.0-source.zip) | Fixed source used for this release |
| **Latest source + A-to-Z guides** | [Download current main ZIP](https://github.com/msaadatmustafa-tech/ShutterBridge/archive/refs/heads/main.zip) | Includes documentation updates after the release |
| **Checksums** | [SHA256SUMS.txt](https://github.com/msaadatmustafa-tech/ShutterBridge/releases/download/v1.5.0/SHA256SUMS.txt) | Verify the three versioned files |

> **The iPhone IPA is unsigned.** Opening it directly on iPhone will not install it. You need your own Apple ID, a USB data cable for initial setup and a local signing tool such as [Sideloadly](https://sideloadly.io/). No Apple password, certificate or provisioning profile is bundled. The Windows EXE is also unsigned. Android uses the browser remote and needs no APK.

### Start here

1. [Install the iPhone companion from Windows](https://github.com/msaadatmustafa-tech/ShutterBridge/blob/main/docs/GETTING_STARTED.md#install-the-iphone-app-from-windows).
2. [Connect Windows through BLE + the app PIN](https://github.com/msaadatmustafa-tech/ShutterBridge/blob/main/docs/GETTING_STARTED.md#connect-windows-over-bluetooth).
3. [Enable live preview](https://github.com/msaadatmustafa-tech/ShutterBridge/blob/main/docs/GETTING_STARTED.md#add-windows-live-preview) or [connect the Android browser](https://github.com/msaadatmustafa-tech/ShutterBridge/blob/main/docs/GETTING_STARTED.md#connect-android-or-a-laptop-browser).
4. Select quality → Apply → check confirmed format → Start → Stop & Save.
5. [Find recordings in Photos/Files and export them](https://github.com/msaadatmustafa-tech/ShutterBridge/blob/main/docs/GETTING_STARTED.md#find-and-export-recordings).

**[Complete English setup + troubleshooting](https://github.com/msaadatmustafa-tech/ShutterBridge/blob/main/docs/GETTING_STARTED.md)** · **[Roman Urdu guide](https://github.com/msaadatmustafa-tech/ShutterBridge/blob/main/WINDOWS_IPHONE_SETUP_ROMAN_URDU.md)** · **[Project overview](https://github.com/msaadatmustafa-tech/ShutterBridge)**

### Included in v1.5

- Camera Studio desktop/iPhone interface and full-screen iPhone recording view.
- Start/Stop & Save, front/back switching, zoom and supported 4K/1080p/720p at 30/60 FPS.
- Confirmed camera format and saved movie dimensions/FPS, separate from pending quality selections.
- Local Photos saving with Files originals; optional Wi-Fi preview, QR connection and browser controls.
- Foreground-only operation with visible permission and remote-control choices.

### Verified results

19 Windows tests passed. Real physical iPhone tests covered 4K/1080p/720p at 30/60 FPS on front and back cameras (12 combinations), with saved-file metadata and Photos success; owner confirmed Gallery saves. Real Windows EXE BLE authentication, quality apply and Start/Stop passed. The iPhone-hosted browser UI was tested end-to-end from Windows Chrome. iOS cloud build and Sideloadly installation succeeded.

[Release build](https://github.com/msaadatmustafa-tech/ShutterBridge/actions/runs/41820089945) · [Detailed evidence and outstanding hardware checks](https://github.com/msaadatmustafa-tech/ShutterBridge/blob/main/VERIFICATION_AND_INSTALL.md). Public downloads were fetched and their SHA-256 checksums verified; IPA version/build and archive integrity were checked.

### Before your first shoot

Modes are camera/device dependent. Preview is a reduced-resolution silent framing feed, not a 4K stream. No app-imposed duration cutoff; storage, heat, battery and iOS interruptions still apply. Extended capture and broad-device testing remain outstanding. No Apple passwords or signing credentials are included.

Keep iPhone foreground/unlocked. Signing can expire and need refresh. Playback/audio inspection and wider device testing remain outstanding. Use trusted local Wi-Fi and keep access links/PINs private.

**[MIT license](https://github.com/msaadatmustafa-tech/ShutterBridge/blob/main/LICENSE).** Built by [@msaadatmustafa-tech](https://github.com/msaadatmustafa-tech). If ShutterBridge helps your shoots, give the repository a star.
