import SwiftUI
import AVFoundation
import CoreImage

@main
struct iPhoneBLECameraApp: App {
    @StateObject private var camera = CameraService()
    @StateObject private var bluetooth = BluetoothService()

    var body: some Scene {
        WindowGroup {
            ContentView(camera: camera, bluetooth: bluetooth)
        }
    }
}

struct ContentView: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var bluetooth: BluetoothService
    @Environment(\.scenePhase) private var scenePhase
    @State private var didInitialize = false
    @State private var showFullScreen = false
    @State private var selectedQuality = "1080P30"
    @State private var localFeedback = "Select quality, then Apply while recording is stopped"

    private func perform(_ command: String) {
        camera.execute(command) { response in
            bluetooth.send(response)
            switch response {
            case "ERR:STOP_RECORDING_FIRST": localFeedback = "Stop & Save and wait for saving to finish first."
            case "ERR:UNSUPPORTED_MODE": localFeedback = "This camera does not support that quality."
            case "ERR:MODE_APPLY_FAILED": localFeedback = "The format/FPS could not be applied. Check confirmed quality below."
            case "ERR:CAMERA_NOT_READY": localFeedback = "Camera is not ready. Check Camera permission."
            default: localFeedback = response.hasPrefix("OK:MODE:") ? "Quality applied: " + String(response.dropFirst(8)) : response
            }
        }
    }

    private func wifiQR(_ address: String) -> UIImage? {
        guard !address.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(address.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("CAMERA REMOTE").font(.headline)
                        Spacer()
                        Text(camera.isRecording ? "● RECORDING" : "STANDBY")
                            .font(.headline).foregroundStyle(camera.isRecording ? .red : .green)
                    }
                    CameraPreview(session: camera.session)
                        .frame(height: max(240, geometry.size.height * 0.48))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading) {
                                Text("\(camera.currentMode)  ·  \(camera.cameraSide)")
                                if let start = camera.recordingStartedAt {
                                    Text(start, style: .timer).font(.largeTitle.monospacedDigit().bold())
                                }
                            }
                            .padding(12).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white).padding(12)
                        }
                    Button("Open full-screen camera") { showFullScreen = true }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                    Text(camera.cameraStatus).font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RECORDING QUALITY & CAMERA").font(.headline)
                        HStack {
                            Picker("Video quality", selection: $selectedQuality) {
                                ForEach(camera.availableModes, id: \.self) { mode in Text(mode).tag(mode) }
                            }
                            .pickerStyle(.menu).disabled(camera.isBusy || !camera.isReady)
                            Spacer()
                            Button("Apply quality") { perform("MODE:" + selectedQuality) }
                                .buttonStyle(.borderedProminent)
                                .disabled(camera.isBusy || !camera.isReady || !camera.availableModes.contains(selectedQuality))
                        }
                        HStack {
                            Button("Back") { perform("CAM:BACK") }.disabled(camera.isBusy || !camera.isReady)
                            Button("Front") { perform("CAM:FRONT") }.disabled(camera.isBusy || !camera.isReady)
                            Spacer()
                            Button("1×") { perform("ZOOM:1") }.disabled(!camera.isReady)
                            Button("2×") { perform("ZOOM:2") }.disabled(!camera.isReady)
                        }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                        Text("Confirmed: \(camera.currentMode) · \(camera.cameraSide)").font(.subheadline.bold())
                        Text(camera.actualFormatText).font(.caption.monospaced())
                        Text(localFeedback).font(.caption).foregroundStyle(.secondary)
                        Text("Supported on this camera: \(camera.availableModes.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    HStack(spacing: 12) {
                        Button("START RECORDING") { perform("START") }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.red, in: RoundedRectangle(cornerRadius: 12))
                            .disabled(!camera.isReady || camera.isBusy || camera.isRecording)
                        Button("STOP & SAVE") { perform("STOP") }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                            .disabled(!camera.isBusy && !camera.isRecording)
                    }
                    .buttonStyle(.plain).font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("RECORDINGS", systemImage: "photo.on.rectangle")
                            .font(.headline)
                        Text(camera.photosStatus).font(.subheadline)
                        Text(camera.lastClipDetails).font(.subheadline).textSelection(.enabled)
                        Text("Latest: \(camera.lastFile)").font(.caption).textSelection(.enabled)
                        Button("Save existing Files recordings to Photos") { camera.importExistingRecordings() }
                            .buttonStyle(.bordered).disabled(camera.isRecording)
                        Text("Originals stay in Files → On My iPhone → iPhone BLE Camera. Photos needs Add Photos permission.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 10) {
                        Label("LIVE PREVIEW / ANDROID REMOTE", systemImage: "wifi").font(.headline)
                        Text(camera.wifiStatus).font(.subheadline)
                        Button(camera.wifiEnabled ? "Turn Wi-Fi preview off" : "Enable Wi-Fi preview") { camera.toggleWiFi() }
                            .buttonStyle(.bordered).disabled(camera.isRecording && !camera.wifiEnabled)
                        if camera.wifiEnabled {
                            Toggle("Allow Wi-Fi remote controls", isOn: $camera.wifiRemoteEnabled)
                            Text("Open this link on Android, or paste it in the Windows Live Preview tab.")
                                .font(.caption)
                            Text(camera.wifiAddress).font(.caption.monospaced()).textSelection(.enabled)
                            if let qr = wifiQR(camera.wifiAddress) {
                                Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                                    .frame(width: 180, height: 180).padding(12).background(.white)
                                    .accessibilityLabel("Scan this QR code with Android to open the local remote")
                                Text("Android: scan this QR with Camera / Google Lens. Keep this iPhone app open.")
                                    .font(.caption)
                            }
                            if let url = URL(string: camera.wifiAddress) { ShareLink("Share preview / remote link", item: url) }
                            Text("Keep this app foreground. The link grants preview access; controls need the toggle above. Use a trusted local Wi-Fi. The same link resumes when you return to this app. Turning preview off revokes it.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    DisclosureGroup("Bluetooth connection · PIN \(bluetooth.sessionPIN)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(bluetooth.displayState)
                            Text("Supported: \(camera.availableModes.joined(separator: ", "))")
                            Text("Keep this app open and phone unlocked. Video stays on this iPhone; Bluetooth carries controls only.")
                        }.font(.caption).padding(.top, 8)
                    }
                }
                .padding(16)
            }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(session: camera.session).ignoresSafeArea()
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(camera.isRecording ? "● RECORDING" : "STANDBY")
                                .font(.headline)
                            Text("\(camera.currentMode) · \(camera.cameraSide)").font(.caption)
                        }
                        Spacer()
                        Menu("Settings") {
                            Menu("Video quality") {
                                ForEach(camera.availableModes, id: \.self) { mode in
                                    Button(mode) { selectedQuality = mode; perform("MODE:" + mode) }
                                        .disabled(camera.isBusy)
                                }
                            }
                            Button("Back camera") { perform("CAM:BACK") }.disabled(camera.isBusy)
                            Button("Front camera") { perform("CAM:FRONT") }.disabled(camera.isBusy)
                            Button("1× zoom") { perform("ZOOM:1") }
                            Button("2× zoom") { perform("ZOOM:2") }
                        }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                        Button("Dashboard") { showFullScreen = false }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                    }
                    .padding(14).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                    Spacer()
                    VStack(spacing: 12) {
                        if let start = camera.recordingStartedAt {
                            Text(start, style: .timer).font(.system(size: 42, weight: .bold, design: .monospaced))
                        }
                        Text(camera.isRecording ? "Recording on this iPhone" : camera.cameraStatus)
                            .font(.headline).multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button("START") { perform("START") }
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(.red, in: RoundedRectangle(cornerRadius: 12))
                                .disabled(!camera.isReady || camera.isBusy || camera.isRecording)
                            Button("STOP & SAVE") { perform("STOP") }
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                                .disabled(!camera.isBusy && !camera.isRecording)
                        }
                        .buttonStyle(.plain).font(.headline)
                        if !camera.isRecording {
                            Text(camera.photosStatus).font(.caption).multilineTextAlignment(.center)
                        }
                    }
                    .padding(16).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(16).foregroundStyle(.white)
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: camera.currentMode) { mode in selectedQuality = mode }
        .onChange(of: camera.availableModes) { modes in
            if !modes.contains(selectedQuality) { selectedQuality = modes.contains(camera.currentMode) ? camera.currentMode : (modes.first ?? "1080P30") }
        }
        .onChange(of: camera.isRecording) { recording in
            if recording { showFullScreen = true }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            let active = phase == .active
            UIApplication.shared.isIdleTimerDisabled = active
            camera.setForeground(active)
            bluetooth.setForeground(active)
        }
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            bluetooth.camera = camera
            camera.onCameraEvent = { [weak bluetooth] message in bluetooth?.send(message) }
            UIApplication.shared.isIdleTimerDisabled = true
            camera.requestPermissionsAndStart()
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session { uiView.previewLayer.session = session }
    }
}

final class PreviewUIView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
