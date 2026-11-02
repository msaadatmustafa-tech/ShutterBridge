# Current verification

Private GitHub publication completed. Windows: six mocked controller tests, dependency check, GUI smoke test, EXE build and real BLE scan passed. Corrected Xcode 16.4 / iOS 18.5 arm64 build b38d8a6 passed; downloaded IPA and Files/USB sharing keys verified. Initial iPhone installation and recording remain untested because no USB cable is available. See VERIFICATION_AND_INSTALL.md for current results; older prototype notes below describe the original package.

# iPhone 4K BLE Camera Remote (local project)

**What this does:** A Windows laptop sends Bluetooth Low Energy (BLE) commands to a small iPhone recording app. The iPhone captures the video locally, with its own camera and microphone. It supports 4K, 1080p and 720p formats and 30/60 FPS **only when that specific iPhone camera supports each mode**.

**What this does NOT do:** It does **not** stream 4K footage over Bluetooth, provide live laptop preview, or control Apple's built-in Camera app without installing an iPhone companion app. It is source code with an **automated cloud-build recipe**, **not** a prebuilt signed iPhone IPA or a prebuilt Windows EXE. This project has not been hardware-tested.

## Requirements

- Windows 11 laptop with Bluetooth LE (on modern Windows 10 builds it may also work, but Windows 11 is the supported/tested target for Bleak)
- Python 3 installed, including Tkinter, from python.org
- iPhone running iOS 16+ (the companion app must be installed and kept in foreground)
- For **Windows-only** users: GitHub account (cloud macOS Xcode build) + [Sideloadly](https://sideloadly.io/) on Windows + an Apple ID for personal-device signing. See **`WINDOWS_IPHONE_SETUP_ROMAN_URDU.md`**. A Mac is optional.
- iPhone camera/microphone and Bluetooth permissions, enabled Bluetooth on both devices

## 1. Install iPhone app (Windows-only OR Mac)

**Windows + iPhone users:** Follow `WINDOWS_IPHONE_SETUP_ROMAN_URDU.md` first. The included `.github/workflows/build-ios-ipa.yml` uses a GitHub-hosted Mac to compile an **unsigned** `.ipa`, which Windows Sideloadly can sign and install with your own Apple ID. No Mac of your own is required, but a GitHub account, initial internet connection and a USB cable are necessary. This route has **not yet been live-tested**.

**Mac/Xcode option:**

1. Copy the `iPhone/` folder to a Mac.
2. Open `iPhone/iPhoneBLECamera.xcodeproj` in Xcode.
3. Select the `iPhoneBLECamera` target. Under **Signing & Capabilities**, set your own unique bundle ID and select your personal/team signing account. Let Xcode sign automatically.
4. Connect iPhone, trust Mac. Enable **Developer Mode** on the iPhone when Xcode requests it (iPhone Settings > Privacy & Security > Developer Mode).
5. Select the physical iPhone device and press **Run** in Xcode. Simulator won't work for physical camera/BLE.
6. Open the installed **iPhone BLE Camera** app and grant **Camera, Microphone, Bluetooth** permissions. Leave the app open and unlocked. A 6-digit PIN appears.

**Important:** Xcode does not run on Windows. If you have no Mac, use the included GitHub Actions cloud-build workflow and the Sideloadly Windows installer. Free Apple ID signing normally expires after 7 days and requires refresh.

## 2. Start Windows controller

1. Extract this ZIP on your Windows laptop.
2. Double-click `Windows/START_WINDOWS.bat`.
3. On first run it installs `bleak` inside a folder-local `.venv` virtual environment. It won't modify the rest of your Python installation.
4. Switch on Bluetooth on laptop, keep iPhone app open, click **Scan for iPhone**.
5. Select discovered `iPhoneCam`, type the **6-digit PIN visible on your iPhone**, click **Connect**.
6. When status says **READY**, choose a recording quality, click **Apply Quality** and **START RECORDING**.
7. Click **STOP RECORDING** to finish a clip and save it on iPhone.

To create an optional Windows EXE yourself, double-click `Windows/BUILD_EXE.bat` (runs PyInstaller on Windows), then look for `Windows/dist/iPhoneCameraRemote.exe`. This is not necessary for normal use.

## 3. What is supported

| Feature | Support | Notes |
| --- | --- | --- |
| Bluetooth remote start/stop | Yes, through companion app | iPhone must be foreground + unlocked |
| 4K 3840×2160 at 30 FPS | Conditional | Only if camera format supports it |
| 4K 3840×2160 at 60 FPS | Conditional | Only if camera format supports it |
| 1080p at 30/60 FPS | Conditional | Camera hardware dependent |
| 720p at 30/60 FPS | Conditional | Camera hardware dependent |
| Front/back camera | Yes | If supported; cannot switch during recording |
| 1×/2× zoom | Yes | Capped by the active iPhone camera's supported zoom |
| Microphone audio | Yes, when permission granted | No sound if permission denied |
| Unlimited app time limit | Yes | No hardcoded clip-duration cutoff |
| Literally unlimited capture | No | Phone storage, battery, heating, system interrupts still apply |
| Live laptop preview over Bluetooth | No | Bluetooth bandwidth is unsuitable for 4K preview |
| Save directly to laptop over Bluetooth | No | Recordings remain on iPhone; USB / Files for transfer |
| Screen locked / app background recording | No | Keep iPhone app active in foreground |
| Change resolution while recording | No | Stop recording first |

## 4. Find and transfer recorded files

Video files are written as `.mov` files in the iPhone app's `Documents` folder (example `Camera_2026-11-02_19-25-13-123.mov`).

On your iPhone open **Files > On My iPhone > iPhone BLE Camera** (when app's Documents folder appears in Files). Alternatively connect by USB and use iPhone app **File Sharing** in Finder (Mac) or Apple Devices (Windows) to copy the documents to your laptop. No cloud upload takes place.

## Troubleshooting

- **Scan returns zero iPhones:** Check the iPhone app reads *Discoverable as iPhoneCam* and is in foreground, Bluetooth is on both sides, and the computer supports BLE. Move devices closer; rescan. Windows can sometimes cache stale BLE results. This app advertises a custom service, not standard Bluetooth file transfer.
- **Connected, but PIN rejected:** Restart the app, use the new 6-digit code. After 5 wrong codes there is a 2-minute cooldown.
- **4K60 says unsupported:** That specific front/back iPhone camera mode doesn't advertise 4K at 60 FPS. Try `4K30` or `1080P30`.
- **Missing videos:** Stop recording and allow the save to complete. Check app Documents. Long recordings require lots of available storage.
- **Video stops unexpectedly:** iOS may interrupt capture for calls, camera conflicts, high temperatures or storage. Keep the display awake, charge safely and avoid overheating.
- **Build error / App can't install:** Verify Apple's code signing, bundle ID, selected team, and iOS Developer Mode. No signed `.ipa` is bundled.

## Privacy and security

- Commands stay local over BLE. No login, backend, upload, analytics or internet dependency for the camera control itself (first-time Windows installation downloads the Python dependency).
- Camera and microphone require consent on iPhone. A six-digit session PIN gates remote commands and changes when the app is restarted. This is basic access control, **not** strong cryptographic authentication; use in a trusted, nearby environment.
- The app never secretly starts the camera in the background. Keep the iPhone app visibly open while recording.

## Project contents

```
iPhone-BLE-Camera-Remote/
├─ Windows/
│  ├─ camera_remote.py           # Tkinter graphical controller + Bleak BLE client
│  ├─ START_WINDOWS.bat           # First-run dependency installation + launch
│  ├─ BUILD_EXE.bat               # Optional build a Windows .exe on Windows
│  └─ requirements.txt
├─ .github/workflows/
│  └─ build-ios-ipa.yml          # GitHub Actions macOS cloud build (unsigned .ipa)
├─ scripts/
│  └─ build-unsigned-ipa.sh      # Cloud build and IPA packaging
├─ WINDOWS_IPHONE_SETUP_ROMAN_URDU.md
├─ iPhone/
│  ├─ iPhoneBLECamera.xcodeproj/  # Native Xcode project + shared scheme
│  └─ iPhoneBLECamera/
│     ├─ RemoteCamApp.swift       # iPhone UI + live local camera preview
│     ├─ CameraService.swift      # AVFoundation camera recording
│     └─ BluetoothService.swift   # BLE peripheral server + PIN verification
└─ README.md
```

## Testing / readiness

- Python syntax compilation completed successfully.
- Swift syntax parsing completed successfully with a local Swift parser.
- **Not verified:** GitHub Actions iOS Xcode build, Windows GUI/Bluetooth radio connection, IPA sideloading, or physical iPhone video recording (hardware/macOS Xcode unavailable in this workspace). The source is a functional prototype that may need device-specific fixes; it is **not** a certified, tested production product.

## Sources

- Apple: https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager
- Apple: https://developer.apple.com/documentation/avfoundation/avcapturesession/preset/hd4k3840x2160
- Apple: https://developer.apple.com/documentation/avfoundation/avcapturefileoutput/maxrecordedduration
- Apple: https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device/
- Bleak: https://bleak.readthedocs.io/en/latest/
