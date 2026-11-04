# Wi-Fi preview and Android remote — ShutterBridge v1.5

1. Install/update the companion app using the unsigned IPA from Releases and your own local signing account. Back up recordings first; keep the same bundle ID and signing account when updating.
2. Put iPhone, Windows and Android on the same trusted Wi-Fi. Keep iPhone open/unlocked.
3. On iPhone tap **Enable Wi-Fi preview**, grant Local Network, and enable again if the permission prompt paused it.
4. Windows app: paste the complete link in **LIVE PREVIEW → Connect preview**. Connect Bluetooth with the displayed PIN for native desktop buttons.
5. Android: turn on **Allow Wi-Fi remote controls**, scan the iPhone QR code with Camera / Google Lens and open Chrome. The same page works on a laptop.
6. While stopped, select quality → **Apply quality** → check confirmed dimensions/FPS. Start → Stop & Save → wait for the save result. Check the verified saved-file metadata.

## Preview versus recording quality

The framing feed is silent, up to 640px and up to 5 FPS. It does not represent the resolution/FPS of the saved movie. Recordings use the actual iPhone camera format and are saved locally in Photos (when allowed) and Files.

## Reconnection

Backgrounding/locking stops recording and pauses the listener. Returning to foreground resumes the session with the same key/port; clients retry. Explicit **Turn Wi-Fi preview off** revokes the link. Restarting the app or changing Wi-Fi/IP can require a new link. Use the QR code to avoid leaving the camera app to share the link.

## If the page times out

Keep the camera app foreground, confirm preview is enabled and Local Network allowed, and use its current complete link. All devices must share a network that allows client-to-client traffic. Guest Wi-Fi, client isolation and VPNs can block this. No router port forwarding is needed.

## Privacy

The link grants preview access to anyone who has it on the local network; mutations additionally need the visible Wi-Fi remote toggle. HTTP is unencrypted. Never paste a live link in public issues, screenshots or the repository. Use trusted Wi-Fi and turn preview off when finished.

For actual test results and limitations see [Verification](VERIFICATION_AND_INSTALL.md).
