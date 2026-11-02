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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("iPhone BLE Camera")
                    .font(.largeTitle.bold())
                Text("Video records on this iPhone. Bluetooth carries remote-control commands only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                CameraPreview(session: camera.session)
                    .frame(height: 310)
                    .clipShape(RoundedRectangle(cornerRadius: 17))
                    .overlay(alignment: .topTrailing) {
                        if camera.isRecording {
                            Label("REC", systemImage: "record.circle.fill")
                                .font(.caption.bold())
                                .padding(9)
                                .background(.red.opacity(0.85), in: Capsule())
                                .padding(12)
                        }
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                    Text(bluetooth.displayState)
                        .font(.subheadline)
                    HStack {
                        Text("Laptop connection PIN")
                        Spacer()
                        Text(bluetooth.sessionPIN)
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    Text("Enter this code in the Windows controller. Keep this app in the foreground and the phone unlocked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 8) {
                    Label("Camera", systemImage: "video")
                        .font(.headline)
                    Text(camera.cameraStatus)
                        .font(.subheadline)
                    Text("Current: \(camera.currentMode)  |  \(camera.cameraSide)")
                        .font(.subheadline.monospaced())
                    Text("Supported: \(camera.availableModes.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Start") { camera.execute("START") { bluetooth.send($0) } }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(!camera.isReady || camera.isRecording)
                        Button("Stop") { camera.execute("STOP") { bluetooth.send($0) } }
                            .buttonStyle(.bordered)
                            .disabled(!camera.isRecording)
                    }
                    Text("Latest file: \(camera.lastFile)")
                        .font(.caption)
                        .textSelection(.enabled)
                }
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                Text("Files app → On My iPhone → iPhone BLE Camera. You can also transfer recordings over USB using Apple Devices file sharing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
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
