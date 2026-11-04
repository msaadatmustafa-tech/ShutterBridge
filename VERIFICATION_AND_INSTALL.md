# ShutterBridge v1.5 — verification and installation

Verified on 4 November 2026 on one Windows laptop and one physical iPhone. These observations are not certification for all devices.

## Recording matrix

Saved dimensions and nominal frame rates were read from AVAsset metadata on iPhone.
Photos saves reported success for these clips. The owner subsequently confirmed that recordings appear in Gallery; independent playback/audio inspection remains pending.

| Camera | Requested | Saved metadata |
|---|---|---|
| BACK | 4K60 | 3840x2160@60.00fps |
| BACK | 4K30 | 3840x2160@30.00fps |
| BACK | 1080P60 | 1920x1080@59.95fps |
| BACK | 1080P30 | 1920x1080@30.00fps |
| BACK | 720P60 | 1280x720@59.95fps |
| BACK | 720P30 | 1280x720@30.00fps |
| FRONT | 4K60 | 3840x2160@60.00fps |
| FRONT | 4K30 | 3840x2160@30.00fps |
| FRONT | 1080P60 | 1920x1080@60.00fps |
| FRONT | 1080P30 | 1920x1080@30.00fps |
| FRONT | 720P60 | 1280x720@60.00fps |
| FRONT | 720P30 | 1280x720@30.00fps |

## Other observed results

- Windows: 19 automated controller, preview and dashboard tests passed. `pip check` passed. A repeated test run emitted Tk garbage-collection teardown warnings despite passing assertions; shutdown behavior needs broader testing.
- Windows EXE packaged and launched; real BLE discovery/PIN authentication passed. Desktop quality Apply confirmed 4K60; Start and Stop & Save produced about 25 seconds of recording at 3840x2160@59.95fps.
- Real desktop preview frames and elapsed timer observed; camera/quality controls locked during recording.
- Front/back switch and 1x/2x zoom passed on the physical phone.
- Real iPhone-hosted browser UI, tested in Windows Chrome: 4K30 Apply, front/back, 2x/1x, Start and Stop & Save passed. Saved metadata 3840x2160@30.00fps; Photos success received.
- Physical Android connectivity confirmed by owner. Latest responsive browser logic was tested against real iPhone from Windows Chrome, not fully re-tested on physical Android. Simulated tests exercised all six quality choices and selection retention during polling.
- iOS cloud compilation succeeded for commit `eb10224`: [GitHub Actions run](https://github.com/msaadatmustafa-tech/ShutterBridge/actions/runs/41816382729). v1.5/build 8 IPA CRC, version/build and permission declarations verified. Sideloadly showed Done / 100% after installation.

## Remaining hardware checks

- Gallery playback and audio quality inspection.
- Extended recording, storage exhaustion, battery and thermal behavior. No app-imposed duration cutoff exists; device/OS interruptions remain possible.
- Current Android browser touch/rotation/latency across more models.
- Lock/background, calls, permission revocation and Wi-Fi/Bluetooth interruption recovery.
- Broader iPhone model/iOS coverage and simultaneous controller interactions.

## Install / reproduce

Follow [Windows + iPhone installation](WINDOWS_IPHONE_SETUP_ROMAN_URDU.md) and [Wi-Fi / Android setup](WIFI_ANDROID_SETUP.md). From source, run `Windows/START_WINDOWS.bat`; tests: `Windows\.venv\Scripts\python.exe -m unittest discover -s Windows -v`. Build the EXE with `Windows/BUILD_EXE.bat`. Use GitHub Actions for an unsigned IPA, then sign/install locally. Never upload Apple passwords or signing credentials.
