import SwiftUI
import AVFoundation
import CoreImage

private enum Studio {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.085)
    static let panel = Color(red: 0.07, green: 0.105, blue: 0.15)
    static let accent = Color(red: 0.44, green: 0.94, blue: 0.77)
    static let muted = Color(red: 0.68, green: 0.74, blue: 0.81)
}

private struct StudioCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content
    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.symbol = symbol; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Studio.muted)
            content
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Studio.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07)))
    }
}

@main
struct iPhoneBLECameraApp: App {
    @StateObject private var camera = CameraService()
    @StateObject private var bluetooth = BluetoothService()
    var body: some Scene { WindowGroup { ContentView(camera: camera, bluetooth: bluetooth) } }
}

struct ContentView: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var bluetooth: BluetoothService
    @Environment(\.scenePhase) private var scenePhase
    @State private var didInitialize = false
    @State private var showFullScreen = false
    @State private var selectedQuality = "1080P30"
    @State private var localFeedback = "Select a quality, then Apply while recording is stopped"

    private func perform(_ command: String) {
        camera.execute(command) { response in
            bluetooth.send(response)
            switch response {
            case "ERR:STOP_RECORDING_FIRST": localFeedback = "Stop & Save and wait for saving to finish first."
            case "ERR:UNSUPPORTED_MODE": localFeedback = "This camera does not support that quality."
            case "ERR:MODE_APPLY_FAILED": localFeedback = "Format/FPS could not be applied. Check confirmed quality below."
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
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }

    private var recordingPill: some View {
        Label(camera.isRecording ? "RECORDING" : camera.isReady ? "CAMERA READY" : "PREPARING",
              systemImage: camera.isRecording ? "record.circle.fill" : "circle.fill")
            .font(.caption2.weight(.bold)).tracking(0.8)
            .foregroundStyle(camera.isRecording ? .red : Studio.accent)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.black.opacity(0.7), in: Capsule())
    }

    private var qualityCard: some View {
        StudioCard("RECORDING QUALITY", symbol: "slider.horizontal.3") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
                ForEach(camera.availableModes, id: \.self) { mode in
                    Button { selectedQuality = mode } label: {
                        Text(mode).font(.subheadline.monospaced().weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(selectedQuality == mode ? Studio.background : .white)
                            .background(selectedQuality == mode ? Studio.accent : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain).disabled(camera.isBusy || !camera.isReady)
                    .accessibilityAddTraits(selectedQuality == mode ? .isSelected : [])
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONFIRMED · \(camera.currentMode)").font(.caption.weight(.bold)).foregroundStyle(Studio.accent)
                    Text(camera.actualFormatText).font(.caption.monospaced()).foregroundStyle(Studio.muted)
                }
                Spacer(minLength: 8)
                Button { perform("MODE:" + selectedQuality) } label: { Label("Apply", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(Studio.accent).foregroundStyle(Studio.background)
                    .controlSize(.large)
                    .disabled(camera.isBusy || !camera.isReady || !camera.availableModes.contains(selectedQuality))
            }
            HStack(spacing: 8) {
                Button { perform("CAM:BACK") } label: { Label("Back", systemImage: "camera") }
                    .disabled(camera.isBusy || !camera.isReady)
                Button { perform("CAM:FRONT") } label: { Label("Front", systemImage: "camera.rotate") }
                    .disabled(camera.isBusy || !camera.isReady)
                Spacer(minLength: 0)
                Button("1×") { perform("ZOOM:1") }.disabled(!camera.isReady)
                Button("2×") { perform("ZOOM:2") }.disabled(!camera.isReady)
            }
            .font(.subheadline.weight(.semibold)).buttonStyle(.bordered).tint(Studio.accent).controlSize(.large)
            Text(localFeedback).font(.caption).foregroundStyle(Studio.muted)
        }
    }

    private var connectionCard: some View {
        StudioCard("CONNECT YOUR REMOTES", symbol: "antenna.radiowaves.left.and.right") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bluetooth PIN").font(.subheadline.weight(.semibold))
                    Text(bluetooth.displayState).font(.caption).foregroundStyle(Studio.muted)
                }
                Spacer()
                Text(bluetooth.sessionPIN).font(.title2.monospaced().weight(.bold)).foregroundStyle(Studio.accent).textSelection(.enabled)
            }
            Divider().overlay(.white.opacity(0.1))
            Text(camera.wifiStatus).font(.subheadline)
            Button { camera.toggleWiFi() } label: {
                Label(camera.wifiEnabled ? "Turn Wi-Fi preview off" : "Enable Wi-Fi preview", systemImage: "wifi")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.bordered).tint(Studio.accent)
            .disabled(camera.isRecording && !camera.wifiEnabled)
            if camera.wifiEnabled {
                Toggle("Allow Wi-Fi remote controls", isOn: $camera.wifiRemoteEnabled).font(.subheadline).tint(Studio.accent)
                if let qr = wifiQR(camera.wifiAddress) {
                    HStack {
                        Spacer()
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                            .frame(width: 172, height: 172).padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Scan with Android to open the local camera remote")
                        Spacer()
                    }
                    Text("Android: scan with Camera or Google Lens. Keep this iPhone app open.")
                        .font(.caption).foregroundStyle(Studio.muted)
                }
                Text(camera.wifiAddress).font(.caption.monospaced()).foregroundStyle(Studio.muted).textSelection(.enabled)
                if !camera.wifiAddress.isEmpty, let url = URL(string: camera.wifiAddress) {
                    ShareLink(item: url) { Label("Share connection link", systemImage: "square.and.arrow.up") }
                        .font(.subheadline).tint(Studio.accent)
                }
                Text("Trusted local Wi-Fi only. Background pauses camera and preview; return here to reconnect. Turning Wi-Fi preview off revokes this link.")
                    .font(.caption).foregroundStyle(Studio.muted)
            }
        }
    }

    private var recordingsCard: some View {
        StudioCard("YOUR RECORDINGS", symbol: "photo.stack") {
            Text(camera.photosStatus).font(.subheadline.weight(.medium))
            Text(camera.lastClipDetails).font(.caption.monospaced()).foregroundStyle(Studio.accent).textSelection(.enabled)
            Text(camera.lastFile).font(.caption).foregroundStyle(Studio.muted).textSelection(.enabled)
            Button { camera.importExistingRecordings() } label: {
                Label("Save existing clips to Photos", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered).tint(Studio.accent).disabled(camera.isBusy)
            Text("Originals stay in Files → On My iPhone → iPhone BLE Camera. Gallery saving requires Add Photos permission.")
                .font(.caption).foregroundStyle(Studio.muted)
        }
    }

    private var recordBar: some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                Button { perform("START") } label: {
                    Label("Record", systemImage: "record.circle")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(.white).background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain).disabled(!camera.isReady || camera.isBusy || camera.isRecording)
                .opacity(!camera.isReady || camera.isBusy ? 0.4 : 1)
                Button { perform("STOP") } label: {
                    Label("Stop & Save", systemImage: "stop.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(.white).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain).disabled(!camera.isBusy && !camera.isRecording)
                .opacity(camera.isBusy || camera.isRecording ? 1 : 0.4)
            }
            Text(camera.isRecording ? "Recording on iPhone · \(camera.currentMode)" : camera.isBusy ? "Starting / saving… please wait" : "\(camera.currentMode) · \(camera.cameraSide) · Local recording")
                .font(.caption).foregroundStyle(Studio.muted)
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
        .background(Studio.background.opacity(0.96))
    }

    private var settingsMenu: some View {
        Menu {
            Menu("Video quality") {
                ForEach(camera.availableModes, id: \.self) { mode in
                    Button(mode) { selectedQuality = mode; perform("MODE:" + mode) }.disabled(camera.isBusy)
                }
            }
            Button("Back camera") { perform("CAM:BACK") }.disabled(camera.isBusy)
            Button("Front camera") { perform("CAM:FRONT") }.disabled(camera.isBusy)
            Button("1× zoom") { perform("ZOOM:1") }
            Button("2× zoom") { perform("ZOOM:2") }
        } label: { Label("Settings", systemImage: "slider.horizontal.3").frame(minHeight: 44) }
    }

    private var immersiveCamera: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            VStack {
                HStack {
                    recordingPill
                    Spacer()
                    settingsMenu
                    Button { showFullScreen = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Return to dashboard")
                }
                .padding(12).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                Spacer()
                if let start = camera.recordingStartedAt {
                    Text(start, style: .timer).font(.system(size: 48, weight: .medium, design: .monospaced)).padding(12)
                        .background(.black.opacity(0.5), in: Capsule())
                }
                Text(camera.actualFormatText).font(.caption.monospaced()).padding(8).background(.black.opacity(0.5), in: Capsule())
                recordBar.clipShape(RoundedRectangle(cornerRadius: 20))
                if !camera.isRecording { Text(camera.photosStatus).font(.caption).padding(8).background(.black.opacity(0.7), in: Capsule()) }
            }
            .padding(16).foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("CAMERA / STUDIO").font(.caption2.weight(.bold)).tracking(2.5).foregroundStyle(Studio.accent)
                            Text("Your next shot.").font(.system(size: 30, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        Image(systemName: "camera.aperture").font(.system(size: 30, weight: .light)).foregroundStyle(Studio.accent)
                    }
                    .padding(.top, 8)
                    CameraPreview(session: camera.session)
                        .frame(height: max(250, min(420, geometry.size.height * 0.43)))
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.12)))
                        .overlay(alignment: .topLeading) { recordingPill.padding(14) }
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 5) {
                                if let start = camera.recordingStartedAt { Text(start, style: .timer).font(.title.monospaced().weight(.semibold)) }
                                Text("\(camera.currentMode)  /  \(camera.cameraSide)").font(.caption.monospaced().weight(.semibold))
                            }
                            .padding(12).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14)).padding(14)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Button { showFullScreen = true } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.headline).frame(width: 46, height: 46)
                                    .background(.black.opacity(0.65), in: Circle())
                            }
                            .buttonStyle(.plain).padding(14).accessibilityLabel("Open full-screen camera")
                        }
                    Text(camera.cameraStatus).font(.subheadline).foregroundStyle(Studio.muted)
                    qualityCard
                    connectionCard
                    recordingsCard
                    Text("Keep this app open and phone unlocked. Wi-Fi carries framing preview; full-quality recordings save on this iPhone.")
                        .font(.caption).foregroundStyle(Studio.muted).padding(.bottom, 8)
                }
                .padding(.horizontal, 18)
            }
            .background(Studio.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { recordBar }
        }
        .tint(Studio.accent).foregroundStyle(.white).preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showFullScreen) { immersiveCamera }
        .onChange(of: camera.currentMode) { selectedQuality = $0 }
        .onChange(of: camera.availableModes) { modes in
            if !modes.contains(selectedQuality) { selectedQuality = modes.contains(camera.currentMode) ? camera.currentMode : (modes.first ?? "1080P30") }
        }
        .onChange(of: camera.isRecording) { if $0 { showFullScreen = true } }
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
        let view = PreviewUIView(); view.previewLayer.session = session; view.previewLayer.videoGravity = .resizeAspectFill; return view
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session { uiView.previewLayer.session = session }
    }
}
final class PreviewUIView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
