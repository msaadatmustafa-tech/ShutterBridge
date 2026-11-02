# Windows and iPhone verification / installation

Project was edited directly in the extracted Downloads/iPhone-BLE-Camera-Remote-Windows-iPhone-No-Mac/iPhone-BLE-Camera-Remote folder.

## Verified on Windows, 2026-11-03
- Python 3.11.9, Bleak 3.0.2; dependency check passed.
- Six mocked controller tests passed: fragmented/coalesced status, auth rejection, stale disconnect, authorized and unauthorized writes, oversized input.
- Tk GUI startup and close passed.
- PyInstaller 6.22.3 EXE build passed; EXE process stayed alive after four seconds. Packager reports optional non-Windows backend imports; actual BLE connection remains untested.
- Initial BLE scan failed with radio POWERED_OFF. After Bluetooth was enabled, a real 5-second scan passed and found 3 BLE devices, zero camera services. No iPhone connection or recording has been verified.
- Private repository published: https://github.com/msaadatmustafa-tech/iPhone-BLE-Camera-Remote
- Corrected iOS build b38d8a6 passed on GitHub Actions (Xcode 16.4, iOS 18.5 SDK, arm64): https://github.com/msaadatmustafa-tech/iPhone-BLE-Camera-Remote/actions/runs/41510583811
- Downloaded IPA CRC and arm64 executable verified. Camera, microphone, Bluetooth descriptions and Files/USB sharing verified in packaged Info.plist. SHA256: 25b6193ea269f155e7a3dbaf20e7ec6d88bbd830c1853e1ce25a7d0fa8058c2a.
- Compiler log confirms BUILD SUCCEEDED. GitHub warns that v4 actions use deprecated Node 20 and are forced to Node 24; build succeeds. No iPhone runtime tests completed.
- Sideloadly installer downloaded from official sideloadly.io. It is not Authenticode signed; installation was not completed. Apple ID, trust/permission prompts and initial USB connection remain user steps.
- User has Bluetooth enabled but no USB cable available. Initial Sideloadly installation and physical camera verification are blocked until a cable is available.

## Publish and build (approval required)
Git is initialized locally. A local Git repository has no private/public setting; GitHub visibility is set on publication.
In GitHub Desktop: File > Add local repository, choose this project, review changes and commit. Publish repository with Keep this code private enabled. Never add signing files, Apple passwords, tokens or .env files. Publish only after owner approval. In GitHub Actions select Build iPhone IPA (no Mac required) > Run workflow. Inspect the xcode-build-log artifact on failure. Successful runs provide iPhoneBLECamera-unsigned-IPA: download and unzip the artifact to obtain the IPA. An unsigned IPA cannot launch until signed locally.

## Install from Windows
1. Download Sideloadly only from https://sideloadly.io/ and follow its current Windows dependency/driver instructions. Connect the unlocked iPhone over USB and accept Trust This Computer.
2. Open Sideloadly, select the iPhone and drag in the unsigned IPA. Enter Apple ID and any authentication prompts locally in Sideloadly only. Do not send passwords here or put credentials in Git, workflow secrets, logs, or files in this repository.
3. Start installation. If required, trust your developer profile in Settings > General > VPN & Device Management. Enable Developer Mode under Settings > Privacy & Security if prompted, restart, and confirm.
4. Launch iPhone BLE Camera. Allow Camera and Bluetooth. Microphone permission is optional; denying it gives silent video. Keep app foreground and phone unlocked.
5. Enable laptop Bluetooth. Launch Windows/dist/iPhoneCameraRemote.exe (or START_WINDOWS.bat), scan, select iPhoneCam, enter the phone PIN and connect. Wait for OK:AUTH.
Free Apple ID signatures generally last seven days; refresh using the same Apple ID and bundle ID. Back up recordings via Files or USB before updating, reinstalling or deleting the app. See https://sideloadly.io/faq .

## Hardware acceptance checks still required
- Wrong PIN rejects controls; correct PIN allows them. Power cycle Bluetooth, disconnect/reconnect and verify fresh authorization; second laptop cannot take ownership.
- For each camera, inspect supported modes on the phone. Test every offered 4K/1080p/720p 30/60 mode; unsupported modes must return an error. Inspect saved clip dimensions and frame rates on Windows.
- Start, wait for REC:1, stop, wait for OK:SAVED; open local .mov and verify picture/audio. Test camera switches and zoom, rapid repeated commands and unsupported formats.
- Record for an extended period and check duration, disk space and temperature. No app timer limits duration; iOS, storage, power, thermal state and filesystem limits remain.
- Lock phone, switch apps, interrupt with a call, revoke permissions and test low storage. App must reject remote starts outside foreground, finalize recordings and show errors; return foreground then reconnect.
- Copy recordings through Files / Apple Devices file sharing. Video must remain local; BLE transmits commands/status only.

The PIN is not encrypted Bluetooth pairing. Use in trusted surroundings. Both apps use protocol v2 and must be updated together.
