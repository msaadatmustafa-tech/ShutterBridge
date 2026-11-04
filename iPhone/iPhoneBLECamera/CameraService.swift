import Foundation
import UIKit
import AVFoundation
import CoreMedia
import Combine
import Photos
import Network
import CoreImage
import Darwin
import QuartzCore
import ImageIO

/// Records videos locally. All AVFoundation session work is serialized on captureQueue.
final class CameraService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var cameraStatus = "Waiting for camera permission"
    @Published private(set) var isReady = false
    @Published private(set) var isRecording = false
    @Published private(set) var currentMode = "1080P30"
    @Published private(set) var cameraSide = "BACK"
    @Published private(set) var availableModes: [String] = []
    @Published private(set) var lastFile = "No recording yet"

    @Published private(set) var photosStatus = "Photos access will be requested when saving a clip"
    @Published private(set) var recordingStartedAt: Date?
    private var photosInFlight: Set<String> = []
    private var importingExisting = false

    // Called on the main queue. Keep the Documents original even if Photos fails.
    private func saveToPhotos(_ url: URL, completion: (() -> Void)? = nil) {
        let key = url.lastPathComponent
        let saved = UserDefaults.standard.stringArray(forKey: "photosImportedClips") ?? []
        guard !saved.contains(key), !photosInFlight.contains(key) else { completion?(); return }
        photosInFlight.insert(key)
        photosStatus = "Saving to Photos... Files backup is safe"
        onCameraEvent?("SAVE:PHOTOS_PENDING")
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    self.photosInFlight.remove(key)
                    self.photosStatus = "Photos access denied. Video is in Files. Allow Add Photos in Settings, then retry."
                    self.onCameraEvent?("SAVE:FILES_ONLY")
                    completion?()
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
                }) { success, error in
                    DispatchQueue.main.async {
                        self.photosInFlight.remove(key)
                        if success {
                            var imported = UserDefaults.standard.stringArray(forKey: "photosImportedClips") ?? []
                            if !imported.contains(key) { imported.append(key) }
                            UserDefaults.standard.set(imported, forKey: "photosImportedClips")
                            self.photosStatus = "Saved to Photos / Recents and Files"
                            self.onCameraEvent?("SAVE:PHOTOS_OK")
                        } else {
                            self.photosStatus = "Photos save failed: \(error?.localizedDescription ?? "Unknown error"). Video remains in Files; retry below."
                            self.onCameraEvent?("SAVE:PHOTOS_FAILED")
                        }
                        completion?()
                    }
                }
            }
        }
    }

    func importExistingRecordings() {
        guard !isRecording, !importingExisting else { return }
        importingExisting = true
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let urls = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "mov" }
        let imported = UserDefaults.standard.stringArray(forKey: "photosImportedClips") ?? []
        let pending = urls.filter { !imported.contains($0.lastPathComponent) }
        guard !pending.isEmpty else {
            importingExisting = false
            photosStatus = "No unsaved clips to import into Photos"
            return
        }
        importNext(pending)
    }

    private func importNext(_ urls: [URL]) {
        guard let first = urls.first else { importingExisting = false; return }
        saveToPhotos(first) {
            // Stop retries if access is denied; retain every original file.
            guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
                self.importingExisting = false
                return
            }
            self.importNext(Array(urls.dropFirst()))
        }
    }

    @Published private(set) var wifiEnabled = false
    @Published private(set) var wifiAddress = ""
    @Published private(set) var wifiStatus = "Wi-Fi preview is off"
    @Published var wifiRemoteEnabled = false
    private let previewServer = LocalCameraServer()
    private let previewOutput = AVCaptureVideoDataOutput()
    private let previewQueue = DispatchQueue(label: "camera.preview.frames", qos: .utility)
    private let previewContext = CIContext(options: [.cacheIntermediates: false])
    private var lastPreviewTime: CFTimeInterval = 0
    private var previewAvailable = false

    func toggleWiFi() {
        if wifiEnabled {
            stopWiFi()
            return
        }
        captureQueue.async {
            guard self.foreground, self.started else {
                DispatchQueue.main.async { self.wifiStatus = "Open the camera in foreground first" }
                return
            }
            guard !self.movieOutput.isRecording, !self.recordingPending else {
                DispatchQueue.main.async { self.wifiStatus = "Stop recording before enabling Wi-Fi preview" }
                return
            }
            if !self.previewAvailable {
                self.session.beginConfiguration()
                self.previewOutput.alwaysDiscardsLateVideoFrames = true
                self.previewOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                self.previewOutput.setSampleBufferDelegate(self, queue: self.previewQueue)
                if self.session.canAddOutput(self.previewOutput) {
                    self.session.addOutput(self.previewOutput)
                    self.previewAvailable = true
                    if let connection = self.previewOutput.connection(with: .video), connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
                self.session.commitConfiguration()
            }
            if let connection = self.previewOutput.connection(with: .video) { connection.isEnabled = true }
            _ = self.videoInput.map { self.applyModeInternal(self.activeMode, device: $0.device) }
            guard self.previewAvailable else {
                DispatchQueue.main.async { self.wifiStatus = "Live preview is unavailable with this camera configuration. Bluetooth recording still works." }
                return
            }
            DispatchQueue.main.async {
                self.wifiEnabled = true
                self.wifiStatus = "Starting local preview... Allow Local Network when prompted."
                self.previewServer.onState = { [weak self] address, status in
                    self?.wifiAddress = address
                    self?.wifiStatus = status
                    if address.isEmpty { self?.wifiEnabled = false }
                }
                self.previewServer.onCommand = { [weak self] command, reply in
                    guard let self = self else { reply("ERR:CAMERA_UNAVAILABLE"); return }
                    if command != "STATUS" && !self.wifiRemoteEnabled {
                        reply("ERR:WIFI_REMOTE_DISABLED")
                        return
                    }
                    self.execute(command) { response in
                        if command == "STATUS" {
                            reply(response + ";SAVE=" + self.photosStatus)
                        } else { reply(response) }
                    }
                }
                self.previewServer.start()
            }
        }
    }

    func stopWiFi() {
        previewServer.stop()
        captureQueue.async {
            self.previewOutput.connection(with: .video)?.isEnabled = false
        }
        wifiEnabled = false
        wifiRemoteEnabled = false
        wifiAddress = ""
        wifiStatus = "Wi-Fi preview is off"
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard previewServer.running else { return }
        let now = CACurrentMediaTime()
        guard now - lastPreviewTime >= 0.2 else { return }
        lastPreviewTime = now
        autoreleasepool {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let source = CIImage(cvPixelBuffer: buffer)
            let scale = min(1, 640 / max(source.extent.width, source.extent.height))
            let resized = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let jpeg = previewContext.jpegRepresentation(of: resized,
                colorSpace: CGColorSpaceCreateDeviceRGB(), options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.55]) else { return }
            previewServer.updateFrame(jpeg)
        }
    }

    let session = AVCaptureSession()
    var onCameraEvent: ((String) -> Void)?

    private let captureQueue = DispatchQueue(label: "com.local.blecamera.capture")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var activeMode = "1080P30"
    private var activeSide = "BACK"
    private var configured = false
    private var started = false
    private var foreground = true
    private var recordingPending = false

    func setForeground(_ active: Bool) {
        if !active, wifiEnabled {
            previewServer.stop(resetSession: false)
            wifiStatus = "Preview paused. Return to this app to reconnect the same link."
        }
        captureQueue.async {
            self.foreground = active
            if !active {
                if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
                self.session.stopRunning()
                self.started = false
            } else if self.configured {
                self.session.startRunning()
                self.started = self.session.isRunning
            }
            DispatchQueue.main.async {
                self.isReady = self.started
                if active, self.started, self.wifiEnabled {
                    self.previewServer.start()
                }
            }
        }
    }

    private struct VideoMode {
        let name: String
        let width: Int32
        let height: Int32
        let framesPerSecond: Int32
    }

    private let modes: [VideoMode] = [
        VideoMode(name: "4K60", width: 3840, height: 2160, framesPerSecond: 60),
        VideoMode(name: "4K30", width: 3840, height: 2160, framesPerSecond: 30),
        VideoMode(name: "1080P60", width: 1920, height: 1080, framesPerSecond: 60),
        VideoMode(name: "1080P30", width: 1920, height: 1080, framesPerSecond: 30),
        VideoMode(name: "720P60", width: 1280, height: 720, framesPerSecond: 60),
        VideoMode(name: "720P30", width: 1280, height: 720, framesPerSecond: 30)
    ]

    func requestPermissionsAndStart() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] videoAllowed in
            guard let self = self else { return }
            guard videoAllowed else {
                self.postStatus("Camera permission denied. Enable it in iPhone Settings.")
                return
            }
            // If microphone access is declined, silent video is still possible.
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                self.captureQueue.async { self.prepareSession() }
            }
        }
    }

    private func prepareSession() {
        guard !configured else { return }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            postStatus("No compatible back camera found")
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            session.beginConfiguration()
            session.sessionPreset = .inputPriority
            guard session.canAddInput(input), session.canAddOutput(movieOutput) else {
                session.commitConfiguration()
                postStatus("Unable to initialize camera input/output")
                return
            }
            session.addInput(input)
            videoInput = input

            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let microphone = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: microphone),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
            session.addOutput(movieOutput)
            session.commitConfiguration()

            let detected = supportedModes(for: camera)
            let preferred = detected.contains("1080P30") ? "1080P30" : (detected.first ?? "")
            guard !preferred.isEmpty, applyModeInternal(preferred, device: camera) else {
                postStatus("No compatible video recording format detected")
                return
            }

            // No app-imposed duration limit. The recording is still limited by
            // disk space, power, temperature, and iOS system behavior.
            movieOutput.maxRecordedDuration = .invalid
            configured = true
            if foreground { session.startRunning() }
            started = session.isRunning
            DispatchQueue.main.async {
                self.availableModes = detected
                self.currentMode = preferred
                self.isReady = self.started
                self.cameraStatus = self.started ? "Camera ready" : "Camera did not start"
            }
            postEvent(started ? "READY" : "ERR:CAMERA_NOT_READY")
        } catch {
            postStatus("Camera initialization failed: \(error.localizedDescription)")
        }
    }

    private func supportedModes(for device: AVCaptureDevice) -> [String] {
        modes.filter { findFormat(on: device, for: $0) != nil }.map(\.name)
    }

    private func findFormat(on device: AVCaptureDevice, for mode: VideoMode) -> AVCaptureDevice.Format? {
        return device.formats.first { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dimensions.width == mode.width && dimensions.height == mode.height else { return false }
            return format.videoSupportedFrameRateRanges.contains { frameRateRange in
                frameRateRange.minFrameRate <= Double(mode.framesPerSecond) + 0.01 &&
                frameRateRange.maxFrameRate >= Double(mode.framesPerSecond) - 0.01
            }
        }
    }

    @discardableResult
    private func applyModeInternal(_ name: String, device: AVCaptureDevice) -> Bool {
        guard let mode = modes.first(where: { $0.name == name }),
              let format = findFormat(on: device, for: mode) else { return false }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let frameDuration = CMTime(value: 1, timescale: mode.framesPerSecond)
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    /// BLE commands are not trusted until BluetoothService validates the PIN.
    func execute(_ command: String, reply: @escaping (String) -> Void) {
        captureQueue.async {
            let response = self.executeOnCaptureQueue(command)
            DispatchQueue.main.async { reply(response) }
        }
    }

    private func executeOnCaptureQueue(_ command: String) -> String {
        if command == "STATUS" {
            let active = movieOutput.isRecording ? "1" : "0"
            let readiness = started ? "1" : "0"
            return "STATUS:READY=\(readiness);REC=\(active);MODE=\(activeMode);CAM=\(activeSide)"
        }
        guard foreground else { return "ERR:FOREGROUND_REQUIRED" }
        guard configured, started, session.isRunning else { return "ERR:CAMERA_NOT_READY" }
        if command == "START" {
            guard !movieOutput.isRecording, !recordingPending else { return "ERR:ALREADY_RECORDING" }
            let fileURL = nextOutputURL()
            if let connection = movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
                // Portrait default. Landscape clips can be created by rotating the device
                // before starting the recording.
                switch UIDevice.current.orientation {
                case .landscapeLeft: connection.videoOrientation = .landscapeRight
                case .landscapeRight: connection.videoOrientation = .landscapeLeft
                default: connection.videoOrientation = .portrait
                }
            }
            if let previewConnection = previewOutput.connection(with: .video),
               let recordingConnection = movieOutput.connection(with: .video), previewConnection.isVideoOrientationSupported {
                previewConnection.videoOrientation = recordingConnection.videoOrientation
            }
            recordingPending = true
            movieOutput.startRecording(to: fileURL, recordingDelegate: self)
            return "OK:STARTING"
        }
        if command == "STOP" {
            guard movieOutput.isRecording else { return "ERR:NOT_RECORDING" }
            movieOutput.stopRecording()
            return "OK:STOPPING"
        }
        if (movieOutput.isRecording || recordingPending) && !command.hasPrefix("ZOOM:") { return "ERR:STOP_RECORDING_FIRST" }
        if command.hasPrefix("MODE:") {
            let requested = String(command.dropFirst("MODE:".count))
            guard let camera = videoInput?.device else { return "ERR:NO_CAMERA" }
            guard applyModeInternal(requested, device: camera) else { return "ERR:UNSUPPORTED_MODE" }
            activeMode = requested
            DispatchQueue.main.async { self.currentMode = requested }
            return "OK:MODE:\(requested)"
        }
        if command.hasPrefix("CAM:") {
            let side = String(command.dropFirst("CAM:".count))
            guard side == "FRONT" || side == "BACK" else { return "ERR:UNKNOWN_CAMERA" }
            return changeCamera(to: side)
        }
        if command.hasPrefix("ZOOM:") {
            guard let amount = Double(command.dropFirst("ZOOM:".count)),
                  amount >= 1.0, amount <= 5.0,
                  let device = videoInput?.device else { return "ERR:BAD_ZOOM" }
            do {
                try device.lockForConfiguration()
                let zoom = min(CGFloat(amount), device.activeFormat.videoMaxZoomFactor)
                device.videoZoomFactor = zoom
                device.unlockForConfiguration()
                return "OK:ZOOM:\(String(format: "%.1f", Double(zoom)))"
            } catch {
                return "ERR:ZOOM_UNAVAILABLE"
            }
        }
        return "ERR:UNKNOWN_COMMAND"
    }

    private func changeCamera(to side: String) -> String {
        guard let existingInput = videoInput else { return "ERR:NO_CAMERA" }
        let position: AVCaptureDevice.Position = side == "FRONT" ? .front : .back
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
            return "ERR:CAMERA_NOT_AVAILABLE"
        }
        session.beginConfiguration()
        session.removeInput(existingInput)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoInput = newInput
        } else {
            session.addInput(existingInput)
            session.commitConfiguration()
            return "ERR:CANNOT_SWITCH_CAMERA"
        }
        session.commitConfiguration()

        let detected = supportedModes(for: newDevice)
        let oldMode = activeMode
        let fallback = detected.contains(oldMode) ? oldMode : (detected.contains("1080P30") ? "1080P30" : (detected.first ?? ""))
        guard !fallback.isEmpty, applyModeInternal(fallback, device: newDevice) else {
            session.beginConfiguration()
            session.removeInput(newInput)
            session.addInput(existingInput)
            videoInput = existingInput
            session.commitConfiguration()
            _ = applyModeInternal(activeMode, device: existingInput.device)
            return "ERR:UNSUPPORTED_MODE"
        }
        activeMode = fallback
        activeSide = side
        DispatchQueue.main.async {
            self.cameraSide = side
            self.availableModes = detected
            self.currentMode = fallback
        }
        return "OK:CAM:\(side);MODE=\(fallback)"
    }

    private func nextOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let name = "Camera_\(formatter.string(from: Date())).mov"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    // These delegate callbacks may arrive on arbitrary threads.
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.recordingStartedAt = Date()
            self.isRecording = true
            self.cameraStatus = "Recording"
            self.onCameraEvent?("REC:1")
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        captureQueue.async { self.recordingPending = false }
        DispatchQueue.main.async {
            self.recordingStartedAt = nil
            self.isRecording = false
            self.onCameraEvent?("REC:0")
            if let error = error, !((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false) {
                self.cameraStatus = "Recording ended with an error: \(error.localizedDescription)"
                self.onCameraEvent?("ERR:RECORDING_FAILED")
            } else {
                self.lastFile = outputFileURL.lastPathComponent
                self.cameraStatus = "Saved to Files > On My iPhone > iPhone BLE Camera"
                self.onCameraEvent?("REC:0")
                self.onCameraEvent?("OK:SAVED")
                self.saveToPhotos(outputFileURL)
            }
        }
    }

    private func postStatus(_ text: String) {
        DispatchQueue.main.async { self.cameraStatus = text }
    }

    private func postEvent(_ text: String) {
        DispatchQueue.main.async { self.onCameraEvent?(text) }
    }
}

// Local HTTP server: short-lived capability link, no Internet service or cloud upload.
// All network operations are serialized. Frames are throttled and downscaled separately
// from the full-quality movie file. Disabled whenever the app loses foreground.
final class LocalCameraServer {
    var onState: ((String, String) -> Void)?
    var onCommand: ((String, @escaping (String) -> Void) -> Void)?
    private let queue = DispatchQueue(label: "camera.local.http", qos: .utility)
    private let lock = NSLock()
    private var active = false
    private var frame: Data?
    private var frameTime = Date.distantPast
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var token = ""
    private var sessionPort: NWEndpoint.Port?

    var running: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func updateFrame(_ jpeg: Data) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        frame = jpeg
        frameTime = Date()
    }
    func start() {
        queue.async {
            guard self.listener == nil else { return }
            guard let ip = Self.wifiIPv4() else {
                self.report("", "Connect the iPhone to Wi-Fi, then enable preview again")
                return
            }
            do {
                if self.token.isEmpty { self.token = UUID().uuidString.replacingOccurrences(of: "-", with: "") }
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                let listener = try NWListener(using: parameters, on: self.sessionPort ?? .any)
                listener.service = NWListener.Service(name: "iPhone Camera Remote", type: "_iphonecam._tcp")
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self = self, let listener = listener, self.listener === listener else { return }
                    switch state {
                    case .ready:
                        guard let port = listener.port else { return }
                        self.sessionPort = port
                        self.lock.lock(); self.active = true; self.lock.unlock()
                        self.report("http://\(ip):\(port.rawValue)/?key=\(self.token)", "Wi-Fi preview ON · same Wi-Fi only")
                    case .failed(let error):
                        self.stop()
                        self.report("", "Preview failed: \(error.localizedDescription). Check Local Network permission.")
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self = self, self.connections.count < 8, self.running else { connection.cancel(); return }
                    self.connections[ObjectIdentifier(connection)] = connection
                    connection.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + 5) { [weak self, weak connection] in
                        if let connection = connection { self?.close(connection) }
                    }
                    self.receive(connection, accumulated: Data())
                }
                listener.start(queue: self.queue)
            } catch { self.report("", "Cannot start preview: \(error.localizedDescription)") }
        }
    }
    func stop(resetSession: Bool = true) {
        lock.lock(); active = false; frame = nil; lock.unlock()
        queue.async {
            self.listener?.cancel(); self.listener = nil
            for connection in self.connections.values { connection.cancel() }
            self.connections.removeAll()
            if resetSession { self.token = ""; self.sessionPort = nil }
        }
    }
    private func report(_ address: String, _ state: String) {
        DispatchQueue.main.async { self.onState?(address, state) }
    }
    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] bytes, _, complete, error in
            guard let self = self else { connection.cancel(); return }
            var data = accumulated
            if let bytes = bytes { data.append(bytes) }
            guard data.count <= 8192, error == nil, self.running else { self.close(connection); return }
            guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
                if complete { self.close(connection) } else { self.receive(connection, accumulated: data) }
                return
            }
            guard boundary.lowerBound <= 4096,
                  let header = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { self.close(connection); return }
            let lines = header.components(separatedBy: "\r\n")
            let first = (lines.first ?? "").split(separator: " ")
            guard first.count == 3 else { self.close(connection); return }
            let lengthHeader = lines.dropFirst().first { $0.lowercased().hasPrefix("content-length:") }
            let lengthString = lengthHeader?.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "0"
            guard let length = Int(lengthString), (0...64).contains(length),
                  !lines.contains(where: { $0.lowercased().hasPrefix("transfer-encoding:") }) else { self.close(connection); return }
            let body = data[boundary.upperBound...]
            if body.count < length {
                if complete { self.close(connection) } else { self.receive(connection, accumulated: data) }
                return
            }
            guard let url = URLComponents(string: "http://localhost" + String(first[1])),
                  url.queryItems?.first(where: { $0.name == "key" })?.value == self.token else {
                self.respond(connection, code: "403 Forbidden", type: "text/plain", body: Data("Access denied. Open the current iPhone link.".utf8)); return
            }
            if first[0] == "GET" && url.path == "/" {
                self.respond(connection, code: "200 OK", type: "text/html; charset=utf-8", body: Data(Self.remoteHTML.utf8))
            } else if first[0] == "GET" && url.path == "/frame" {
                self.lock.lock()
                let jpeg = self.frame
                let fresh = Date().timeIntervalSince(self.frameTime) < 2
                self.lock.unlock()
                self.respond(connection, code: jpeg != nil && fresh ? "200 OK" : "503 Service Unavailable", type: "image/jpeg", body: fresh ? (jpeg ?? Data()) : Data())
            } else if first[0] == "POST" && url.path == "/command" {
                let command = String(data: body.prefix(length), encoding: .utf8) ?? ""
                let valid = ["START", "STOP", "STATUS", "CAM:BACK", "CAM:FRONT", "ZOOM:1", "ZOOM:2", "ZOOM:3", "ZOOM:4", "ZOOM:5", "MODE:4K30", "MODE:4K60", "MODE:1080P30", "MODE:1080P60", "MODE:720P30", "MODE:720P60"].contains(command)
                guard valid else { self.respond(connection, code: "400 Bad Request", type: "text/plain", body: Data("ERR:UNKNOWN_COMMAND".utf8)); return }
                DispatchQueue.main.async {
                    guard self.running, let handler = self.onCommand else { self.queue.async { self.close(connection) }; return }
                    handler(command) { result in
                        self.queue.async {
                            guard self.running else { self.close(connection); return }
                            self.respond(connection, code: "200 OK", type: "text/plain; charset=utf-8", body: Data(result.utf8))
                        }
                    }
                }
            } else { self.respond(connection, code: "404 Not Found", type: "text/plain", body: Data()) }
        }
    }
    private func respond(_ connection: NWConnection, code: String, type: String, body: Data) {
        let header = "HTTP/1.1 \(code)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak self] _ in self?.close(connection) })
    }
    private static func wifiIPv4() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var cursor = addresses
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard String(cString: item.pointee.ifa_name) == "en0",
                  let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
    private static let remoteHTML = """
<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>iPhone Camera Remote</title>
<style>:root{color-scheme:dark;font:16px system-ui;background:#101827;color:#f0f5fb}body{max-width:900px;margin:auto;padding:16px}h1{font-size:24px}img{display:block;width:100%;height:50vh;object-fit:contain;background:#050a12;border-radius:16px}section{background:#192539;border-radius:16px;padding:16px;margin:16px 0}.row{display:flex;gap:12px;flex-wrap:wrap}button,select{font:inherit;min-height:48px;border:1px solid #52647a;border-radius:9px;padding:12px;background:#31445f;color:white;flex:1}button:disabled{opacity:.45}.start{background:#aa2741}.stop{background:#245b48}#status,#save{min-height:24px;overflow-wrap:anywhere}small{color:#b6c3d3}#elapsed{font:32px monospace}.error{color:#ffb2bf}</style>
<h1>iPhone Camera Remote</h1><small>Local Wi-Fi preview • Full-quality video saves on iPhone</small>
<section><img id="preview" alt="Live camera preview"><p id="connection" role="status">Connecting to iPhone…</p><div id="elapsed">00:00:00</div><p id="status" role="status">Waiting for camera status</p><p id="save" role="status"></p></section>
<section><div class="row"><button class="start" id="start">START RECORDING</button><button class="stop" id="stop">STOP &amp; SAVE</button></div><p><label for="mode">Recording quality</label></p><div class="row"><select id="mode"><option>1080P30</option><option>1080P60</option><option>4K30</option><option>4K60</option><option>720P30</option><option>720P60</option></select><button id="apply">Apply quality</button></div><p>Camera &amp; zoom</p><div class="row"><button id="back">Back</button><button id="front">Front</button><button id="one">1×</button><button id="two">2×</button></div></section>
<small>Enable “Allow Wi-Fi remote controls” in the iPhone app. Keep the app open and phone unlocked. No microphone audio is sent in this framing preview. The elapsed timer starts when this browser observes recording.</small>
<script>
const key=new URLSearchParams(location.search).get('key');
const $=id=>document.getElementById(id);let busy=false,started=null,previousURL=null;
const request=(path,options={})=>fetch(path+'?key='+encodeURIComponent(key),{...options,cache:'no-store',referrerPolicy:'no-referrer'});
function showStatus(s){$('status').textContent=s;const rec=s.includes('REC=1');if(rec&&!started)started=Date.now();if(!rec)started=null;$('start').disabled=rec;$('apply').disabled=rec;$('front').disabled=rec;$('back').disabled=rec;const mode=s.match(/MODE=([^;]+)/);if(mode)$('mode').value=mode[1];const save=s.match(/;SAVE=(.*)$/);if(save)$('save').textContent=save[1];}
async function command(c){if(busy)return;busy=true;try{const r=await request('/command',{method:'POST',headers:{'Content-Type':'text/plain'},body:c});const s=await r.text();$('save').textContent=s.startsWith('ERR:WIFI_REMOTE_DISABLED')?'Enable Wi-Fi remote controls on the iPhone.':s; if(!r.ok)throw Error('Connection denied; reopen current link from iPhone');}catch(e){$('save').textContent=e.message;}finally{busy=false;}}
$('start').onclick=()=>command('START');$('stop').onclick=()=>command('STOP');$('apply').onclick=()=>command('MODE:'+$('mode').value);$('back').onclick=()=>command('CAM:BACK');$('front').onclick=()=>command('CAM:FRONT');$('one').onclick=()=>command('ZOOM:1');$('two').onclick=()=>command('ZOOM:2');
async function frame(){try{const r=await request('/frame');if(!r.ok)throw Error(r.status===503?'Waiting for camera frames…':'Preview link expired or access denied');const b=await r.blob();const u=URL.createObjectURL(b);$('preview').src=u;if(previousURL)URL.revokeObjectURL(previousURL);previousURL=u;$('connection').textContent='LIVE · local Wi-Fi framing preview';}catch(e){$('connection').textContent=e.message;$('preview').removeAttribute('src');}setTimeout(frame,200);}
async function status(){try{const r=await request('/command',{method:'POST',headers:{'Content-Type':'text/plain'},body:'STATUS'});if(!r.ok)throw Error('Reconnect using the link shown on iPhone');showStatus(await r.text());}catch(e){$('status').textContent=e.message;started=null;$('start').disabled=true;}setTimeout(status,1000);}
setInterval(()=>{const n=started?Math.floor((Date.now()-started)/1000):0;$('elapsed').textContent=[Math.floor(n/3600),Math.floor(n/60)%60,n%60].map(v=>String(v).padStart(2,'0')).join(':');},250);frame();status();
</script></html>

"""
}
