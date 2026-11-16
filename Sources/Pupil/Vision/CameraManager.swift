//
//  CameraManager.swift
//  Pupil
//
//  AVFoundation camera capture & device enumeration, running at a battery-efficient 10 FPS
//  for real-time Vision gaze analysis. Never writes frames to disk.
//

@preconcurrency import AVFoundation
import CoreGraphics
@preconcurrency import CoreImage
import Foundation
import Observation

public struct CameraDeviceInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isBuiltIn: Bool
}

@MainActor
@Observable
public final class CameraManager: NSObject {
    public private(set) var availableCameras: [CameraDeviceInfo] = []
    public private(set) var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    public private(set) var isRunning: Bool = false
    public private(set) var targetAnalysisFPS: Double = 10.0
    public internal(set) var lastFrameImage: CGImage?

    public var onGazeSample: ((GazeSample) -> Void)?
    public var onMotionSample: ((MotionSample) -> Void)?

    @ObservationIgnored private nonisolated(unsafe) let captureSession = AVCaptureSession()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.pupil.camera.session", qos: .userInitiated)
    @ObservationIgnored private nonisolated let videoOutputQueue = DispatchQueue(label: "com.pupil.camera.output", qos: .userInitiated)
    @ObservationIgnored private nonisolated(unsafe) let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    @ObservationIgnored private nonisolated(unsafe) var lastProcessedTime: TimeInterval = 0
    @ObservationIgnored private nonisolated(unsafe) var minimumFrameInterval: TimeInterval = 0.10
    @ObservationIgnored private nonisolated(unsafe) var activeROI: CameraROI = .default
    @ObservationIgnored private nonisolated(unsafe) var warmupFramesRemaining: Int = 3
    @ObservationIgnored public nonisolated(unsafe) var shouldReanchorOnFaceAcquisition: Bool = true
    @ObservationIgnored public nonisolated let motionDetector = VisionMotionDetector()
    /// Allows disabling hardware capture in headless test runners lacking NSCameraUsageDescription.
    public var isCaptureEnabled: Bool = {
        if Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") == nil {
            let proc = ProcessInfo.processInfo
            if proc.environment["XCTestConfigurationFilePath"] != nil || proc.processName.contains("swift-testing") || Bundle.main.bundleIdentifier == nil {
                return false
            }
        }
        return true
    }()

    public override init() {
        super.init()
        refreshCameras()
    }

    public func updateActiveROI(_ roi: CameraROI) {
        activeROI = roi
    }

    public func updateAnalysisRate(fps: Double) {
        let clampedFPS = min(max(fps, 1.0), 30.0)
        targetAnalysisFPS = clampedFPS
        minimumFrameInterval = 1.0 / clampedFPS
    }

    public var captureSessionReference: AVCaptureSession {
        captureSession
    }

    nonisolated private static let supportedDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera,
        .continuityCamera,
        .external
    ]

    public func refreshCameras() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.supportedDeviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        availableCameras = discovery.devices.map { device in
            CameraDeviceInfo(
                id: device.uniqueID,
                name: device.localizedName,
                isBuiltIn: device.deviceType == .builtInWideAngleCamera
            )
        }
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    public func requestCameraAccess() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            authorizationStatus = .authorized
            return true
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        return granted
    }

    public func startCapture(preferredDeviceID: String? = nil) {
        guard isCaptureEnabled, !isRunning else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            Task {
                let granted = await requestCameraAccess()
                if granted {
                    self.startCapture(preferredDeviceID: preferredDeviceID)
                }
            }
            return
        }
        guard status == .authorized else { return }

        let targetID = preferredDeviceID ?? PupilSettings.shared.preferredCameraID
        isRunning = true
        warmupFramesRemaining = 3
        motionDetector.resetAnchor()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureAndStartSession(preferredID: targetID)
        }
    }

    public nonisolated func resetMotionAnchor() {
        warmupFramesRemaining = 2
        motionDetector.resetAnchor()
    }

    public func stopCapture() {
        guard isRunning else { return }
        isRunning = false
        lastFrameImage = nil
        motionDetector.resetAnchor()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    /// Temporarily starts the camera (if already authorized and not currently running) to grab a single
    /// in-memory frame for mobile verification snapshots, then stops capture immediately.
    public func captureOneShotFrame(preferredDeviceID: String? = nil, timeoutSeconds: TimeInterval = 2.0) async -> CGImage? {
        if let existing = lastFrameImage {
            return existing
        }
        guard isCaptureEnabled else { return nil }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else { return nil }

        let startedHere = !isRunning
        if startedHere {
            startCapture(preferredDeviceID: preferredDeviceID)
        }

        defer {
            if startedHere {
                stopCapture()
            }
        }

        let deadline = Date().addingTimeInterval(max(0.3, timeoutSeconds))
        // Wait for at least 1 frame (or brief auto-exposure settle) up to timeout
        while Date() < deadline {
            if let frame = lastFrameImage {
                return frame
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
        return lastFrameImage
    }

    private nonisolated func configureAndStartSession(preferredID: String?) {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .vga640x480

        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.supportedDeviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        let device = discovery.devices.first(where: { $0.uniqueID == preferredID })
            ?? discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            ?? discovery.devices.first

        if let device, let input = try? AVCaptureDeviceInput(device: device), captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: videoOutputQueue)
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }

        captureSession.commitConfiguration()
        captureSession.startRunning()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date().timeIntervalSince1970
        // Throttle Vision inference dynamically based on governor policy
        guard (now - lastProcessedTime) >= minimumFrameInterval else { return }
        lastProcessedTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            return
        }

        let sample = (try? VisionGazeDetector.analyzeFrame(cgImage, roi: activeROI, timestamp: now)) ?? .empty(at: now)

        if warmupFramesRemaining > 0 {
            warmupFramesRemaining -= 1
            motionDetector.resetAnchor()
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.lastFrameImage = cgImage
                self.onGazeSample?(sample)
            }
            return
        }

        let motionSample = motionDetector.analyzeFrame(
            cgImage,
            faceBoundingBoxes: sample.faceBoundingBoxes,
            metricDepthZ0: sample.estimatedMetricDepthMeters,
            timestamp: now,
            allowReanchorOnFaceAcquisition: shouldReanchorOnFaceAcquisition
        )

        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            self.lastFrameImage = cgImage
            self.onGazeSample?(sample)
            self.onMotionSample?(motionSample)
        }
    }
}
