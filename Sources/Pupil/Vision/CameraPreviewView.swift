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

// MARK: - Spatial Focus & Background Noise Profiler Inspection Overlay

public struct SpatialFocusOverlayView: View {
    public let faceBoundingBoxes: [CGRect]
    public let textureEnergy: Float
    public let isTextureAdequate: Bool
    public let isCalibrating: Bool
    public let calibrationSecondsRemaining: Int
    public let displacementScore: Float
    public var showGrid: Bool

    public init(
        faceBoundingBoxes: [CGRect],
        textureEnergy: Float,
        isTextureAdequate: Bool,
        isCalibrating: Bool = false,
        calibrationSecondsRemaining: Int = 0,
        displacementScore: Float = 0,
        showGrid: Bool = true
    ) {
        self.faceBoundingBoxes = faceBoundingBoxes
        self.textureEnergy = textureEnergy
        self.isTextureAdequate = isTextureAdequate
        self.isCalibrating = isCalibrating
        self.calibrationSecondsRemaining = calibrationSecondsRemaining
        self.displacementScore = displacementScore
        self.showGrid = showGrid
    }

    public init(coordinator: SecurityCoordinator) {
        self.init(
            faceBoundingBoxes: coordinator.latestFaceBoundingBoxes,
            textureEnergy: coordinator.latestTextureEnergy,
            isTextureAdequate: coordinator.isTextureAdequate,
            isCalibrating: coordinator.isLiveCalibrating,
            calibrationSecondsRemaining: coordinator.liveCalibrationSecondsRemaining,
            displacementScore: coordinator.latestMotionDisplacementScore,
            showGrid: coordinator.isPreviewFocusOverlayEnabled
        )
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .topLeading) {
                // 1. Subtle spatial tracking grid & corner reticles for the active room background
                if showGrid {
                    backgroundTrackingCanvas(width: w, height: h)
                }

                // 2. Foreground Face / Subject Exclusion Zones
                ForEach(Array(faceBoundingBoxes.enumerated()), id: \.offset) { index, box in
                    let rect = convertVisionRectToMirroredView(box, viewSize: geo.size)
                    faceExclusionZone(rect: rect, index: index)
                }

                // 3. Top Telemetry Banner
                HStack(alignment: .top) {
                    // Left pill: Room focus state
                    HStack(spacing: 5) {
                        Circle()
                            .fill(faceBoundingBoxes.isEmpty ? PupilTheme.armedGreen : PupilTheme.warningAmber)
                            .frame(width: 6, height: 6)
                        Text(faceBoundingBoxes.isEmpty ? "Full Background Focus" : "\(faceBoundingBoxes.count) Subject Masked")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.72))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                    )

                    Spacer()

                    // Right pill: Texture Energy gauge
                    HStack(spacing: 5) {
                        Image(systemName: isTextureAdequate ? "waveform.path" : "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isTextureAdequate ? PupilTheme.armedGreen : PupilTheme.warningAmber)
                        Text(isTextureAdequate ? String(format: "Texture: %.3f", textureEnergy) : "Low Detail")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isTextureAdequate ? Color.white : PupilTheme.warningAmber)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.72))
                            .overlay(
                                Capsule().strokeBorder(
                                    isTextureAdequate ? Color.white.opacity(0.16) : PupilTheme.warningAmber.opacity(0.4),
                                    lineWidth: 1
                                )
                            )
                    )
                }
                .padding(8)

                // 4. Calibration In-Progress Overlay
                if isCalibrating {
                    calibrationProgressBanner(width: w, height: h)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func convertVisionRectToMirroredView(_ box: CGRect, viewSize: CGSize) -> CGRect {
        let videoAspect: CGFloat = 4.0 / 3.0
        let containerAspect = viewSize.width / max(1, viewSize.height)
        let renderW: CGFloat
        let renderH: CGFloat
        if containerAspect > videoAspect {
            renderW = viewSize.width
            renderH = viewSize.width / videoAspect
        } else {
            renderH = viewSize.height
            renderW = viewSize.height * videoAspect
        }
        let offsetX = (viewSize.width - renderW) / 2.0
        let offsetY = (viewSize.height - renderH) / 2.0

        // Invert horizontal for mirror, invert vertical for Vision bottom-left to SwiftUI top-left
        let mirroredMinX = 1.0 - box.maxX
        let mirroredMinY = 1.0 - box.maxY

        // Expand by 25% matching VisionMotionDetector.makeFaceMaskedBackgroundImage
        let expandedMinX = max(0, mirroredMinX - box.width * 0.25)
        let expandedMinY = max(0, mirroredMinY - box.height * 0.25)
        let expandedW = min(1.0 - expandedMinX, box.width * 1.5)
        let expandedH = min(1.0 - expandedMinY, box.height * 1.5)

        return CGRect(
            x: offsetX + expandedMinX * renderW,
            y: offsetY + expandedMinY * renderH,
            width: expandedW * renderW,
            height: expandedH * renderH
        )
    }

    private func faceExclusionZone(rect: CGRect, index: Int) -> some View {
        ZStack(alignment: .topLeading) {
            // Translucent orange wash over the masked face area
            RoundedRectangle(cornerRadius: 6)
                .fill(PupilTheme.warningAmber.opacity(0.18))

            // Dashed orange exclusion border
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    PupilTheme.warningAmber.opacity(0.90),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )

            // Exclusion tag badge
            HStack(spacing: 3) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 8, weight: .bold))
                Text("EXCLUDED SUBJECT")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(PupilTheme.warningAmber)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(3)
        }
        .frame(width: max(20, rect.width), height: max(20, rect.height))
        .position(x: rect.midX, y: rect.midY)
    }

    private func backgroundTrackingCanvas(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Corner reticles indicating active background bounds
            Path { path in
                let len: CGFloat = 14
                let pad: CGFloat = 6

                // Top-left
                path.move(to: CGPoint(x: pad, y: pad + len))
                path.addLine(to: CGPoint(x: pad, y: pad))
                path.addLine(to: CGPoint(x: pad + len, y: pad))

                // Top-right
                path.move(to: CGPoint(x: width - pad - len, y: pad))
                path.addLine(to: CGPoint(x: width - pad, y: pad))
                path.addLine(to: CGPoint(x: width - pad, y: pad + len))

                // Bottom-left
                path.move(to: CGPoint(x: pad, y: height - pad - len))
                path.addLine(to: CGPoint(x: pad, y: height - pad))
                path.addLine(to: CGPoint(x: pad + len, y: height - pad))

                // Bottom-right
                path.move(to: CGPoint(x: width - pad - len, y: height - pad))
                path.addLine(to: CGPoint(x: width - pad, y: height - pad))
                path.addLine(to: CGPoint(x: width - pad, y: height - pad - len))
            }
            .stroke(PupilTheme.armedGreen.opacity(0.40), lineWidth: 1.5)
        }
    }

    private func calibrationProgressBanner(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(PupilTheme.armedGreen)
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
                            .strokeBorder(PupilTheme.armedGreen.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .frame(width: width, height: height)
    }
}

