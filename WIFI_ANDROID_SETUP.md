# Wi-Fi live preview and Android remote (v1.3)

Update the iPhone app using Desktop `iPhone Update v1.3.ipa` in Sideloadly. Keep the same Apple ID and bundle ID, and update over the existing app. Do not delete the app or its recordings. Apple ID/password prompts remain local user steps.

1. Put iPhone, Windows laptop and Android phone on the same Wi-Fi. Keep the iPhone app open and unlocked.
2. Before recording, tap **Enable Wi-Fi preview** on iPhone and allow Local Network access. If the permission prompt stops preview, tap Enable again after allowing it.
3. On Windows, open Desktop **iPhone Camera Remote v1.3.exe**, select **LIVE PREVIEW**, paste the complete link shown by iPhone, and press Connect preview. Preview-tab buttons still use the existing Bluetooth connection; connect and authenticate Bluetooth first to use those buttons.
4. For Android, turn on **Allow Wi-Fi remote controls** on iPhone. Use the iPhone Share link button to transfer the complete link to Android, then open it in Chrome. The browser provides preview, Start/Stop, front/back camera, quality and zoom without installing an Android APK. The same page also works in a laptop browser.
5. Video saves on iPhone; Gallery/Photos saving requires Add Photos permission. Originals remain in app Documents / Files. Stop and wait for confirmation before leaving the app.

The preview is a silent, up-to-640px framing view at up to five frames per second, with Wi-Fi latency. The movie file uses the selected recording quality independently. Enabling preview requires an idle camera; once enabled, it can continue during recording on supported iOS 16+ configurations. Do not judge final recording quality by this preview.

The local HTTP link contains a random access key. Anyone on the local network with that link can see preview; commands additionally require the explicit Wi-Fi-controls toggle. HTTP is unencrypted: use a trusted Wi-Fi, keep the link private and turn preview off after use. Leaving foreground disables the listener, revokes the key and resets Wi-Fi remote permission. No router port forwarding or cloud service is needed. Guest Wi-Fi/client isolation or VPNs may prevent devices communicating.

## Actual verification

- 14 Windows tests passed, including local HTTP JPEG reception, invalid frame rejection, redirect rejection, URL checks, Bluetooth authorization and dashboard status transitions.
- Windows preview integration fetched a simulated JPEG and rendered it in Tk. EXE packaging passed.
- Browser remote was opened against a simulated camera: image loaded, START changed status to REC=1, STOP changed status to REC=0. This was a desktop browser test, not a physical Android test.
- iOS build 27abc17 succeeded: https://github.com/msaadatmustafa-tech/iPhone-BLE-Camera-Remote/actions/runs/41810811844 . Downloaded v1.3 IPA archive integrity and Local Network, Bonjour and Photos usage keys verified.
- Still required on hardware: install v1.3, grant permissions, open preview on Windows and Android, test Bluetooth and Wi-Fi command paths, verify recording with preview at each supported mode, check rotation, latency, sustained heat/battery behavior, app-background revocation, Photos saving and actual clip playback.
