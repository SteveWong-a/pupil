//
//  CameraPreviewView.swift
//  Pupil
//
//  Live AVCaptureVideoPreviewLayer host view for the Gaze Settings page,
//  modeled after Glance's CameraPreviewView.swift.
//

import AppKit
import AVFoundation
import SwiftUI

public struct CameraPreviewView: NSViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> CameraPreviewHostView {
        let view = CameraPreviewHostView()
        view.previewLayer.session = session
        return view
    }

    public func updateNSView(_ nsView: CameraPreviewHostView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
    }
}

public final class CameraPreviewHostView: NSView {
    public let previewLayer = AVCaptureVideoPreviewLayer()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        // Mirror horizontally so the preview acts like a natural mirror
        previewLayer.transform = CATransform3DMakeScale(-1, 1, 1)
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - Minimal Calibration Progress Overlay for Preview

public struct SpatialFocusOverlayView: View {
    public let isCalibrating: Bool
    public let calibrationSecondsRemaining: Int

    public init(
        faceBoundingBoxes: [CGRect] = [],
        textureEnergy: Float = 0,
        isTextureAdequate: Bool = true,
        isCalibrating: Bool = false,
        calibrationSecondsRemaining: Int = 0,
        displacementScore: Float = 0,
        showGrid: Bool = false
    ) {
        self.isCalibrating = isCalibrating
        self.calibrationSecondsRemaining = calibrationSecondsRemaining
    }

    public init(coordinator: SecurityCoordinator) {
        self.init(
            faceBoundingBoxes: coordinator.latestFaceBoundingBoxes,
            textureEnergy: coordinator.latestTextureEnergy,
            isTextureAdequate: coordinator.isTextureAdequate,
            isCalibrating: coordinator.isLiveCalibrating,
            calibrationSecondsRemaining: coordinator.liveCalibrationSecondsRemaining,
            displacementScore: coordinator.latestMotionDisplacementScore,
            showGrid: false
        )
    }

    public var body: some View {
        GeometryReader { geo in
            if isCalibrating {
                calibrationProgressBanner(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private func calibrationProgressBanner(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.white)
                    Text("PROFILING ROOM NOISE FLOOR: \(calibrationSecondsRemaining)s")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }
                Text("Hold laptop still to sample baseline ambient jitter")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .frame(width: width, height: height)
    }
}

