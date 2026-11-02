import Foundation
import UIKit
import AVFoundation
import CoreMedia
import Combine

/// Records videos locally. All AVFoundation session work is serialized on captureQueue.
final class CameraService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published private(set) var cameraStatus = "Waiting for camera permission"
    @Published private(set) var isReady = false
    @Published private(set) var isRecording = false
    @Published private(set) var currentMode = "1080P30"
    @Published private(set) var cameraSide = "BACK"
    @Published private(set) var availableModes: [String] = []
    @Published private(set) var lastFile = "No recording yet"

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
            DispatchQueue.main.async { self.isReady = self.started }
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
