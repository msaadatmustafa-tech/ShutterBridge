# ShutterBridge — complete installation and user guide

**Windows laptop + iPhone. Optional Android browser remote. No Mac of your own required.**

[Overview](../README.md) · [Downloads](https://github.com/msaadatmustafa-tech/ShutterBridge/releases/latest) · [Roman Urdu](../WINDOWS_IPHONE_SETUP_ROMAN_URDU.md) · [Verified results](../VERIFICATION_AND_INSTALL.md)

## Choose your setup

| Goal | What you need |
|---|---|
| Windows recording remote | Windows EXE + signed iPhone companion + BLE connection and app PIN |
| Live camera on Windows | Above setup + trusted shared Wi-Fi + Enable Wi-Fi preview |
| Android remote | Installed iPhone companion + shared Wi-Fi + opt-in remote controls; open its QR link in Chrome |
| Laptop browser remote | Open the same iPhone-hosted link with Wi-Fi remote controls enabled |
| Custom builds | Source ZIP, Python for Windows and GitHub Actions or Xcode for iPhone |

The companion app records the video. This does not control Apple's built-in Camera app. After installation, camera control is wireless; keep the companion open and iPhone unlocked.

## Before you start

- Windows laptop with Bluetooth LE; Windows 11 is the tested environment.
- iPhone running iOS 16+ with enough free space and battery. Modes depend on the active camera/device.
- USB **data** cable for initial installation, plus your own Apple ID for local signing.
- Internet for downloads, installation/signing and cloud builds. Camera control operates locally.
- Trusted same Wi-Fi for preview/browser controls. BLE-only commands do not need Wi-Fi.
- Chrome on Android if desired. No Android APK is needed.

## Download the correct files

From [v1.5.0 Releases](https://github.com/msaadatmustafa-tech/ShutterBridge/releases/tag/v1.5.0), choose:

| File | Purpose |
|---|---|
| `ShutterBridge-Windows-v1.5.exe` | Desktop controller; no Python required |
| `ShutterBridge-iPhone-v1.5-unsigned.ipa` | iPhone companion; personal signing required |
| `ShutterBridge-v1.5.0-source.zip` | Fixed release source snapshot |
| `SHA256SUMS.txt` | Checksums for those three versioned files |

For the newest source **and documentation updates**, use [main.zip](https://github.com/msaadatmustafa-tech/ShutterBridge/archive/refs/heads/main.zip). Extract source before running its batch files. The source ZIP is not the iPhone installer.

### Verify downloads

In PowerShell, from the download folder:

```powershell
Get-FileHash -Algorithm SHA256 .\ShutterBridge-Windows-v1.5.exe
Get-FileHash -Algorithm SHA256 .\ShutterBridge-iPhone-v1.5-unsigned.ipa
```

Compare each hash with its filename in `SHA256SUMS.txt`. The changing `main.zip` is not covered by the fixed release manifest.

## Install the iPhone app from Windows

1. Install [official Sideloadly](https://sideloadly.io/), following its current Windows driver/dependency requirements. Use its [FAQ](https://sideloadly.io/faq) for device detection and signing help.
2. Connect iPhone over USB, unlock it and accept **Trust This Computer** if prompted.
3. In Sideloadly select iPhone, then choose or drag in `ShutterBridge-iPhone-v1.5-unsigned.ipa`.
4. Sign/install using **your own Apple ID locally**. Complete authentication only in your local installer. Never put passwords, codes, certificates or provisioning profiles in GitHub or public issues.
5. If prompted, trust the developer profile in iPhone Settings. If Developer Mode is required, use **Settings → Privacy & Security → Developer Mode**, restart and confirm. Menus may vary by iOS version.
6. Open **iPhone BLE Camera**. ShutterBridge is the public project name; the v1.5 companion uses this home-screen name and the Camera Studio interface.
7. Grant permissions below. Keep the app foreground and phone unlocked while using the camera.

The IPA is **unsigned** and cannot be installed merely by opening it on iPhone. It is not an App Store release. A free Apple account normally needs signature renewal after seven days; see the official FAQ. This installation expiry is separate from recording duration. Back up clips before re-signing/updating; use the same Apple ID and bundle ID to update the existing app.

### Permissions

| Permission | Used for | If denied |
|---|---|---|
| Camera | Video capture | Recording cannot start |
| Bluetooth | Nearby Windows BLE commands | BLE discovery/control will not work |
| Microphone | Sound in recordings | Movies can be silent; check before a shoot |
| Add Photos | Gallery/Photos saving | Files originals remain; allow permission and retry import |
| Local Network | Optional preview/browser remote | Wi-Fi preview/remote cannot connect |

Review denied permissions in iPhone Settings, return to the app and retry. Permissions and remote-control choices stay visible; no hidden/background capture mode is supplied.

## Connect Windows over Bluetooth

1. Open the Windows EXE. Its title is **Camera Studio — iPhone Remote**.
2. Enable Bluetooth on both devices; keep the iPhone app foreground/unlocked and nearby.
3. Click **Scan for iPhone**, choose `iPhoneCam`, and enter the current six-digit PIN shown by the app.
4. Click **Connect** and wait for accepted authorization / **READY**.
5. While stopped, choose a supported quality, press **Apply quality**, and read the confirmed dimensions/FPS.
6. Press **Start**, then **Stop & Save**. Wait for finalization and the save result.

Connect through the app scanner/PIN. Ordinary Windows Bluetooth pairing alone does not establish this app connection. After session changes or revoked authorization, reconnect with the current phone PIN.

## Add Windows live preview

1. Stop recording before enabling preview for the first time.
2. Put laptop and iPhone on the same trusted Wi-Fi.
3. On iPhone tap **Enable Wi-Fi preview** and grant Local Network. If the prompt paused preview, enable it again.
4. Copy the complete phone link, including the access key.
5. Windows → **LIVE PREVIEW** → paste link → **Connect preview**.
6. Keep BLE connected for native Windows recording buttons; they do not send commands through the preview link.

The preview is silent, up to **640px / 5 FPS**, and is intended for framing. Check confirmed quality and saved-file metadata to verify the original movie. Preview resolution is independent of recording resolution.

## Connect Android or a laptop browser

1. Use the same trusted Wi-Fi and keep the iPhone companion open/unlocked.
2. Enable Wi-Fi preview and **Allow Wi-Fi remote controls** on iPhone.
3. Scan its QR code with Camera / Google Lens and open Chrome, or transfer the complete link privately.
4. Use the browser's Start / Stop & Save, quality + Apply, camera and zoom controls.
5. Stop/save before changing camera/quality. Select a mode, press **Apply quality**, then read the confirmed format.

No Android APK or camera-control login is required. A laptop browser can use the same page. These browser commands use Wi-Fi; native desktop commands use BLE.

## Controls and recording quality

| Control | Expected behavior |
|---|---|
| Start / Record | Wait for confirmed recording state and elapsed timer; “starting” alone is not proof |
| Stop & Save | Finalizes the movie and attempts Photos saving while retaining a local original |
| Quality + Apply | Applies a supported mode while stopped; the pending selection is separate from confirmation |
| Back / Front | Switches while stopped; available modes refresh for the new camera |
| 1× / 2× | Zoom request, clamped to the camera's range; zoom can change during recording |
| iPhone full-screen view | Viewfinder, timer, recording controls and settings menu |
| Allow Wi-Fi remote controls | Explicit browser-control opt-in, separate from preview |
| Save existing clips to Photos | Retries eligible local clips after Add Photos access becomes available |
| Refresh iPhone status | Re-reads actual state in the Windows controller |

| Mode | Dimensions | Requested FPS |
|---|---|---|
| 4K30 / 4K60 | 3840 × 2160 | 30 / 60 |
| 1080P30 / 1080P60 | 1920 × 1080 | 30 / 60 |
| 720P30 / 720P60 | 1280 × 720 | 30 / 60 |

Options are device/camera dependent. Confirmed format comes from the active camera; saved-file metadata comes from the completed movie. Nominal-60 test clips measured approximately 59.95–60 FPS. Make a short test clip before a real session.

No app-imposed duration cutoff exists. Storage, heat, battery and iOS interruptions still limit capture. Foreground operation is required.

## Find and export recordings

1. Stop/save and wait for completion.
2. Check **Photos → Recents** when Add Photos access is allowed. The owner confirmed Gallery saves during testing.
3. A `.mov` original remains in Documents / **Files → On My iPhone → iPhone BLE Camera**, where available.
4. If Photos fails, keep the Files original, allow Add Photos and use **Save existing clips to Photos**.
5. Copy/share from Files, or use iPhone app File Sharing in Apple Devices on Windows / Finder on Mac where supported.
6. Inspect a test clip's resolution/FPS, playback and sound before a shoot.

Videos do not automatically save on the laptop or travel over Bluetooth. Back up originals before deleting the app; uninstalling can remove its local Documents.

## Reconnect, update and finish

- Lock/background stops capture and pauses the listener. Return to foreground to resume the same preview key/port; clients retry. Re-authenticate BLE when authorization is revoked.
- App restart or changed Wi-Fi/IP may require a new QR/link. Always use the current displayed address.
- Explicit **Turn Wi-Fi preview off** revokes the link. Disable Wi-Fi remote controls when you only want preview.
- Back up clips before updating. Use the same signing Apple ID and bundle ID; update both client versions together.
- Stop and allow saving to finish before closing, locking or disconnecting a recording session.

## Troubleshooting

| Problem | Check |
|---|---|
| ZIP does not open an app | Download the separate EXE and IPA; source is for code |
| IPA will not install directly | It needs personal signing via the documented Windows route |
| Sideloadly cannot see iPhone | Data cable, unlock + Trust, selected device and official Windows driver requirements |
| App unavailable after several days | Renew its personal signature; use the original account and back up data |
| No camera found over BLE | Both Bluetooth radios, app foreground/permission, proximity; rescan |
| PIN rejected | Current six-digit app PIN; reconnect after a new session |
| Windows preview works but buttons do not | Connect/authenticate BLE; native buttons use Bluetooth |
| Android page times out | Current complete link, same Wi-Fi, preview on, phone foreground, Local Network allowed; guest isolation/VPN can block traffic |
| Browser preview works but controls do not | Enable Allow Wi-Fi remote controls on iPhone |
| 4K choice does not seem applied | Stop/save, select a supported mode, Apply and read confirmed dimensions/FPS |
| Preview looks low quality | Expected framing feed; inspect saved-file metadata instead |
| Camera/quality controls disabled | Stop and wait for starting/saving to finish |
| Gallery video missing | Wait for save, check Add Photos, keep Files original and retry import |
| No sound | Review Microphone permission and test playback |
| Recording stops | Lock/background, calls/camera conflicts, storage, battery and temperature |
| Movie will not play on Windows | Check finalization and player codec support; retain the original |
| Cloud build fails | Inspect the failed step and build-log artifact; report sanitized errors |

## Frequently asked questions

**Do I need a Mac?** No Mac ownership is needed. GitHub macOS runners can compile the IPA, and Windows can sign/install it using Sideloadly.

**Do I need USB every time I record?** No. USB is for initial setup and installation/transfer when needed; validly installed apps use wireless BLE/Wi-Fi camera controls.

**Can I use only Android?** After installing the iPhone companion, Android can control it over shared trusted Wi-Fi. The documented initial no-Mac installation route uses Windows.

**Does it record while locked or closed?** No. Keep the companion foreground and iPhone unlocked.

**Is 4K60 guaranteed on every iPhone?** No. Modes depend on the camera/device. Physical tests covered one iPhone.

**Is preview 4K?** No. The reduced-resolution framing feed is separate from full-quality local recording.

**Is the IPA signed or on the App Store?** No. Use your own local signing account; no shared Apple account or certificate is provided.

**Where is the complete test evidence?** See [verified results and outstanding hardware checks](../VERIFICATION_AND_INSTALL.md). Gallery presence was owner-confirmed; playback/audio, extended capture and wider device behavior need further testing.

## Build from source

- **Windows:** extract source, install Python 3.11+ with Tkinter, run `Windows/START_WINDOWS.bat`. `Windows/BUILD_EXE.bat` creates `Windows/dist/iPhoneCameraRemote.exe`.
- **iPhone:** fork the repository, enable Actions, run **Build iPhone IPA (no Mac required)**, download/extract the IPA artifact and sign locally. On Mac, open the Xcode project with your own signing team.
- **Maintainers:** **Build and publish ShutterBridge v1.5** builds/tests Windows and compiles iOS, then creates v1.5.0 assets/checksums. It fails rather than replacing an existing release; update version/tag, names and notes for a later release. No personal token or Apple signing credentials are required by these workflows.

[Development commands](../README.md#build-and-contribute) · [Protocol](../PROTOCOL.md) · [Contributing](../CONTRIBUTING.md) · [Security](../SECURITY.md)
