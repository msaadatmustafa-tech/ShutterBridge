import SwiftUI
import AVFoundation

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
                    HStack(spacing: 12) {
                        Button("START RECORDING") { camera.execute("START") { bluetooth.send($0) } }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.red, in: RoundedRectangle(cornerRadius: 12))
                            .disabled(!camera.isReady || camera.isRecording)
                        Button("STOP & SAVE") { camera.execute("STOP") { bluetooth.send($0) } }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                            .disabled(!camera.isRecording)
                    }
                    .buttonStyle(.plain).font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("RECORDINGS", systemImage: "photo.on.rectangle")
                            .font(.headline)
                        Text(camera.photosStatus).font(.subheadline)
                        Text("Latest: \(camera.lastFile)").font(.caption).textSelection(.enabled)
                        Button("Save existing Files recordings to Photos") { camera.importExistingRecordings() }
                            .buttonStyle(.bordered).disabled(camera.isRecording)
                        Text("Originals stay in Files → On My iPhone → iPhone BLE Camera. Photos needs Add Photos permission.")
                            .font(.caption).foregroundStyle(.secondary)
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
                            Button("START") { camera.execute("START") { bluetooth.send($0) } }
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(.red, in: RoundedRectangle(cornerRadius: 12))
                                .disabled(!camera.isReady || camera.isRecording)
                            Button("STOP & SAVE") { camera.execute("STOP") { bluetooth.send($0) } }
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                                .disabled(!camera.isRecording)
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
