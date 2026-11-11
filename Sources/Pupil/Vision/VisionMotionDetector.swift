//
//  VisionMotionDetector.swift
//  Pupil
//
//  Zero-dependency Apple Vision Spatial Lift & Motion Detector ("Lift & Walk" Trigger).
//  Closes the "Unplugged Open-Lid Grab & Walk" blindspot when armed on battery power.
//  Processes frames strictly in memory; zero images or crops are written to disk.
//

import Accelerate
import CoreGraphics
import Foundation
import Vision
import simd

public struct MotionSample: Sendable, Equatable {
    public let timestamp: TimeInterval
    /// Normalized global background translation magnitude ||Δt|| (fraction of frame width).
    public let translationMagnitude: Float
    /// Frobenius deviation ||H - I||_F of upper-background homography warp.
    public let homographyWarpMagnitude: Float
    /// Full-frame mean luminance in [0, 1].
    public let meanLuminance: Float
    /// Full-frame luminance variance in [0, 1].
    public let luminanceVariance: Float
    /// Optional metric depth anchor Z_0 in meters from inter-pupillary distance.
    public let metricDepthZ0: Float?
    /// Whether this frame was captured as the initial Frame 0 anchor.
    public let isAnchorFrame: Bool
    /// Normalized frame-to-frame translation ||Δt|| versus the previous frame. Unlike the anchor
    /// comparison this stays meaningful after a large move (e.g. a lift) when the scene no longer
    /// overlaps the anchor.
    public let interFrameTranslation: Float
    /// False when the background had too little texture for image registration to be trusted.
    public let isRegistrationReliable: Bool

    public init(
        timestamp: TimeInterval,
        translationMagnitude: Float,
        homographyWarpMagnitude: Float = 0,
        meanLuminance: Float = 0.45,
        luminanceVariance: Float = 0.04,
        metricDepthZ0: Float? = nil,
        isAnchorFrame: Bool = false,
        interFrameTranslation: Float = 0,
        isRegistrationReliable: Bool = true
    ) {
        self.timestamp = timestamp
        self.translationMagnitude = translationMagnitude
        self.homographyWarpMagnitude = homographyWarpMagnitude
        self.meanLuminance = meanLuminance
        self.luminanceVariance = luminanceVariance
        self.metricDepthZ0 = metricDepthZ0
        self.isAnchorFrame = isAnchorFrame
        self.interFrameTranslation = interFrameTranslation
        self.isRegistrationReliable = isRegistrationReliable
    }

    public var isFrameOccluded: Bool {
        meanLuminance < 0.035 && luminanceVariance < 0.0008
    }

    public static func anchor(at timestamp: TimeInterval, metricDepthZ0: Float? = nil) -> MotionSample {
        MotionSample(
            timestamp: timestamp,
            translationMagnitude: 0,
            homographyWarpMagnitude: 0,
            meanLuminance: 0.45,
            luminanceVariance: 0.04,
            metricDepthZ0: metricDepthZ0,
            isAnchorFrame: true
        )
    }
}

/// Profile measured automatically during the ARMING exit countdown.
public struct RoomCalibrationProfile: Sendable, Equatable, Codable {
    public let sampleCount: Int
    public let averageLuminance: Float
    public let noiseFloorScore: Float
    public let timestamp: Date

    public init(
        sampleCount: Int,
        averageLuminance: Float,
        noiseFloorScore: Float,
        timestamp: Date = Date()
    ) {
        self.sampleCount = sampleCount
        self.averageLuminance = averageLuminance
        self.noiseFloorScore = noiseFloorScore
        self.timestamp = timestamp
    }

    public var noiseLevelDescription: String {
        if noiseFloorScore < 0.20 {
            return "Clean (Low Jitter)"
        } else if noiseFloorScore < 0.45 {
            return "Moderate Ambient Jitter"
        } else {
            return "Elevated Sensor Grain"
        }
    }
}

/// Accumulates camera frames during the arming exit countdown to profile baseline room jitter and lighting.
public struct RoomNoiseProfiler: Sendable {
    private var samples: [MotionSample] = []

    public init() {}

    public mutating func reset() {
        samples.removeAll()
    }

    public mutating func ingest(_ sample: MotionSample) {
        // Skip the initial anchor frame itself
        guard !sample.isAnchorFrame else { return }
        samples.append(sample)
    }

    public func finalizeCalibration() -> RoomCalibrationProfile? {
        guard !samples.isEmpty else { return nil }
        let count = samples.count
        var totalLuma: Float = 0
        var maxNoise: Float = 0
        for s in samples {
            totalLuma += s.meanLuminance
            let noise = max(s.translationMagnitude, s.interFrameTranslation, s.homographyWarpMagnitude)
            if noise > maxNoise {
                maxNoise = noise
            }
        }
        let avgLuma = totalLuma / Float(count)
        return RoomCalibrationProfile(
            sampleCount: count,
            averageLuminance: avgLuma,
            noiseFloorScore: maxNoise,
            timestamp: Date()
        )
    }
}

public struct MotionEscalationSnapshot: Sendable, Equatable {
    public let isTamperTriggered: Bool
    public let isSustainedLiftDetected: Bool
    public let isSustainedOcclusionDetected: Bool
    public let isTransientBumpSuppressed: Bool
    public let continuousDisplacementSeconds: Double
    public let continuousOcclusionSeconds: Double
    public let effectiveDisplacementScore: Float
    public let anchorDepthMeters: Float?
    public let hasCapturedAnchor: Bool
}

/// Deterministic temporal aggregator for spatial lift & webcam occlusion detection.
/// Suppresses transient < 0.5s table-bump spikes and triggers tamper escalation only when
/// background displacement or lens occlusion persists continuously for > 1.2s.
public struct MotionTemporalAggregator: Sendable {
    public static let tableBumpSuppressionSeconds: Double = 0.5
    public static let sustainedEscalationSeconds: Double = 1.2
    /// Sub-threshold dropouts shorter than this do not restart the sustained-motion timer, so a
    /// noisy score during a real lift cannot keep resetting the 1.2s clock.
    public static let motionDropoutToleranceSeconds: Double = 0.4

    public private(set) var hasCapturedAnchor: Bool = false
    public private(set) var anchorTimestamp: TimeInterval?
    public private(set) var anchorDepthMeters: Float?
    private var continuousMotionStart: TimeInterval?
    private var lastMotionExceedTime: TimeInterval?
    private var continuousOcclusionStart: TimeInterval?

    public init() {}

    public mutating func reset() {
        hasCapturedAnchor = false
        anchorTimestamp = nil
        anchorDepthMeters = nil
        continuousMotionStart = nil
        lastMotionExceedTime = nil
        continuousOcclusionStart = nil
    }

    public mutating func ingest(
        _ sample: MotionSample,
        sensitivity: SpatialMotionSensitivity = .medium,
        tableBumpDeadbandSeconds: Double = Self.tableBumpSuppressionSeconds,
        motionDropoutToleranceSeconds: Double = Self.motionDropoutToleranceSeconds,
        sustainedThresholdSeconds: Double = Self.sustainedEscalationSeconds
    ) -> MotionEscalationSnapshot {
        // Capture Frame 0 anchor when first sample arrives after arming/reset
        if !hasCapturedAnchor || sample.isAnchorFrame {
            hasCapturedAnchor = true
            anchorTimestamp = sample.timestamp
            if let z0 = sample.metricDepthZ0 {
                anchorDepthMeters = z0
            }
            continuousMotionStart = nil
            lastMotionExceedTime = nil
            continuousOcclusionStart = sample.isFrameOccluded ? sample.timestamp : nil

            return MotionEscalationSnapshot(
                isTamperTriggered: false,
                isSustainedLiftDetected: false,
                isSustainedOcclusionDetected: false,
                isTransientBumpSuppressed: false,
                continuousDisplacementSeconds: 0,
                continuousOcclusionSeconds: 0,
                effectiveDisplacementScore: 0,
                anchorDepthMeters: anchorDepthMeters,
                hasCapturedAnchor: true
            )
        }

        if anchorDepthMeters == nil, let z0 = sample.metricDepthZ0 {
            anchorDepthMeters = z0
        }

        // Scale translation by metric depth Z_0 relative to nominal 0.60m desk distance when available
        let depthScale: Float
        if let z0 = anchorDepthMeters {
            depthScale = max(0.75, min(1.50, z0 / 0.60))
        } else {
            depthScale = 1.0
        }

        // Anchor-based cues are only trusted when the background had enough texture to register.
        let scaledTranslation = sample.isRegistrationReliable ? sample.translationMagnitude * depthScale : 0
        let translationRatio = scaledTranslation / max(0.001, sensitivity.translationDeadband)
        let warpRatio = sample.isRegistrationReliable
            ? sample.homographyWarpMagnitude / max(0.001, sensitivity.warpDeadband)
            : 0
        // Frame-to-frame motion keeps working after a big move, when the anchor no longer overlaps.
        let interFrameRatio = sample.interFrameTranslation / max(0.001, sensitivity.interFrameDeadband)
        let effectiveScore = max(translationRatio, warpRatio, interFrameRatio)
        let exceedsDeadband = effectiveScore >= 1.0

        if exceedsDeadband {
            if continuousMotionStart == nil {
                continuousMotionStart = sample.timestamp
            }
            lastMotionExceedTime = sample.timestamp
        } else if let lastExceed = lastMotionExceedTime,
                  sample.timestamp - lastExceed <= motionDropoutToleranceSeconds,
                  continuousMotionStart != nil {
            // Brief dropout: keep the clock running but do not count this frame as motion.
        } else {
            continuousMotionStart = nil
            lastMotionExceedTime = nil
        }

        if sample.isFrameOccluded {
            if continuousOcclusionStart == nil {
                continuousOcclusionStart = sample.timestamp
            }
        } else {
            continuousOcclusionStart = nil
        }

        let elapsedMotion: Double
        if exceedsDeadband, let start = continuousMotionStart {
            elapsedMotion = max(0, sample.timestamp - start)
        } else {
            elapsedMotion = 0
        }

        let elapsedOcclusion: Double
        if let start = continuousOcclusionStart {
            elapsedOcclusion = max(0, sample.timestamp - start)
        } else {
            elapsedOcclusion = 0
        }

        // Transient motion spikes lasting < 0.5s (e.g., desk bumps) are suppressed
        let isBumpSuppressed = elapsedMotion > 0 && elapsedMotion < tableBumpDeadbandSeconds
        // Sustained displacement or occlusion continuously for > 1.2s triggers tamper escalation
        let liftTriggered = elapsedMotion > sustainedThresholdSeconds
        let occlusionTriggered = elapsedOcclusion > sustainedThresholdSeconds

        return MotionEscalationSnapshot(
            isTamperTriggered: liftTriggered || occlusionTriggered,
            isSustainedLiftDetected: liftTriggered,
            isSustainedOcclusionDetected: occlusionTriggered,
            isTransientBumpSuppressed: isBumpSuppressed,
            continuousDisplacementSeconds: elapsedMotion,
            continuousOcclusionSeconds: elapsedOcclusion,
            effectiveDisplacementScore: effectiveScore,
            anchorDepthMeters: anchorDepthMeters,
            hasCapturedAnchor: hasCapturedAnchor
        )
    }
}

/// On-device Apple Vision upper-background registration & occlusion analyzer.
/// Evaluates `VNTrackTranslationalImageRegistrationRequest` and `VNTrackHomographyImageRegistrationRequest`
/// on the face-masked top 25% ROI against the armed anchor frame.
public final class VisionMotionDetector: @unchecked Sendable {
    private let lock = NSLock()
    private var anchorImage: CGImage?
    private var anchorTextureEnergyValue: Float?
    private var previousImage: CGImage?
    private var anchorMetricDepthZ0: Float?

    /// Registration runs on a downscaled copy: faster, and averaging smooths sensor noise.
    public static let analysisWidth = 320
    public static let analysisHeight = 240
    /// Mean absolute luminance gradient below which image registration is not trustworthy.
    public static let minimumTextureEnergy: Float = 0.006

    public init() {}

    public var hasAnchorFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        return anchorImage != nil
    }

    public var currentAnchorDepthZ0: Float? {
        lock.lock()
        defer { lock.unlock() }
        return anchorMetricDepthZ0
    }

    public func resetAnchor() {
        lock.lock()
        anchorImage = nil
        anchorTextureEnergyValue = nil
        previousImage = nil
        anchorMetricDepthZ0 = nil
        lock.unlock()
    }

    /// Evaluates a camera frame against the armed Frame 0 anchor and the previous frame using Apple
    /// Vision image registration on the face-masked, downscaled full frame, plus luminance/variance
    /// occlusion checks.
    public func analyzeFrame(
        _ image: CGImage,
        faceBoundingBoxes: [CGRect] = [],
        metricDepthZ0: Float? = nil,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) -> MotionSample {
        let (meanLuma, lumaVariance) = Self.computeFrameLuminanceStats(image)
        guard let current = Self.makeFaceMaskedBackgroundImage(
            from: image,
            faceBoundingBoxes: faceBoundingBoxes
        ) else {
            return MotionSample(
                timestamp: timestamp,
                translationMagnitude: 0,
                homographyWarpMagnitude: 0,
                meanLuminance: meanLuma,
                luminanceVariance: lumaVariance,
                metricDepthZ0: metricDepthZ0,
                isAnchorFrame: false
            )
        }

        lock.lock()
        let existingAnchor = anchorImage
        let previous = previousImage
        previousImage = current
        if existingAnchor == nil {
            anchorImage = current
            anchorMetricDepthZ0 = metricDepthZ0
            anchorTextureEnergyValue = Self.textureEnergy(of: current)
            lock.unlock()
            return MotionSample(
                timestamp: timestamp,
                translationMagnitude: 0,
                homographyWarpMagnitude: 0,
                meanLuminance: meanLuma,
                luminanceVariance: lumaVariance,
                metricDepthZ0: metricDepthZ0,
                isAnchorFrame: true
            )
        }
        if anchorMetricDepthZ0 == nil, let z0 = metricDepthZ0 {
            anchorMetricDepthZ0 = z0
        }
        let anchorZ0 = anchorMetricDepthZ0
        let cachedAnchorEnergy = anchorTextureEnergyValue
        lock.unlock()

        guard let anchor = existingAnchor else {
            return .anchor(at: timestamp, metricDepthZ0: anchorZ0)
        }

        let anchorEnergy = cachedAnchorEnergy ?? Self.textureEnergy(of: anchor)
        let reliable = anchorEnergy >= Self.minimumTextureEnergy
            && Self.textureEnergy(of: current) >= Self.minimumTextureEnergy

        var translationMag: Float = 0
        var warpMag: Float = 0
        var interFrameMag: Float = 0
        if reliable {
            (translationMag, warpMag) = Self.computeRegistrationDisplacement(
                anchorImage: anchor,
                currentImage: current
            )
            if let previous {
                interFrameMag = Self.computeRegistrationDisplacement(
                    anchorImage: previous,
                    currentImage: current,
                    includeHomography: false
                ).translationMagnitude
            }
        }

        return MotionSample(
            timestamp: timestamp,
            translationMagnitude: translationMag,
            homographyWarpMagnitude: warpMag,
            meanLuminance: meanLuma,
            luminanceVariance: lumaVariance,
            metricDepthZ0: anchorZ0,
            isAnchorFrame: false,
            interFrameTranslation: interFrameMag,
            isRegistrationReliable: reliable
        )
    }

    /// Downscales the full frame to `analysisWidth x analysisHeight` and masks any expanded
    /// `VNFaceObservation` bounding boxes (Vision normalized, bottom-left origin) with neutral gray.
    /// Uses the whole frame, not just the ceiling band, so there is texture to register against.
    public static func makeFaceMaskedBackgroundImage(
        from image: CGImage,
        faceBoundingBoxes: [CGRect]
    ) -> CGImage? {
        guard image.width >= 8, image.height >= 8 else { return nil }
        let w = analysisWidth
        let h = analysisHeight
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        for box in faceBoundingBoxes {
            let expanded = box.insetBy(dx: -box.width * 0.25, dy: -box.height * 0.25)
            // CGContext is bottom-left origin, same as Vision's normalized space.
            ctx.fill(CGRect(
                x: max(0, expanded.minX) * CGFloat(w),
                y: max(0, expanded.minY) * CGFloat(h),
                width: min(1, expanded.maxX) * CGFloat(w) - max(0, expanded.minX) * CGFloat(w),
                height: min(1, expanded.maxY) * CGFloat(h) - max(0, expanded.minY) * CGFloat(h)
            ))
        }
        return ctx.makeImage()
    }

    /// Mean absolute horizontal+vertical luminance gradient in [0, 1]; ~0 for flat walls and ceilings.
    public static func textureEnergy(of image: CGImage) -> Float {
        let w = 80
        let h = 60
        var raw = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &raw,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        func luma(_ x: Int, _ y: Int) -> Float {
            let o = (y * w + x) * 4
            return (0.2126 * Float(raw[o]) + 0.7152 * Float(raw[o + 1]) + 0.0722 * Float(raw[o + 2])) / 255
        }
        var sum: Float = 0
        for y in 0..<(h - 1) {
            for x in 0..<(w - 1) {
                let l = luma(x, y)
                sum += abs(luma(x + 1, y) - l) + abs(luma(x, y + 1) - l)
            }
        }
        return sum / Float((w - 1) * (h - 1))
    }

    /// Runs `VNTranslationalImageRegistrationRequest` and `VNHomographyImageRegistrationRequest`
    /// between the armed anchor crop and the current upper-background crop.
    public static func computeRegistrationDisplacement(
        anchorImage: CGImage,
        currentImage: CGImage,
        includeHomography: Bool = true
    ) -> (translationMagnitude: Float, warpMagnitude: Float) {
        let translationRequest = VNTranslationalImageRegistrationRequest(
            targetedCGImage: anchorImage,
            options: [:]
        )
        let homographyRequest = VNHomographicImageRegistrationRequest(
            targetedCGImage: anchorImage,
            options: [:]
        )

        let handler = VNImageRequestHandler(cgImage: currentImage, options: [:])
        do {
            try handler.perform(includeHomography ? [translationRequest, homographyRequest] : [translationRequest])
        } catch {
            return (0, 0)
        }

        var translationMag: Float = 0
        if let transObs = translationRequest.results?.first as? VNImageTranslationAlignmentObservation {
            let transform = transObs.alignmentTransform
            let dx = Float(transform.tx) / Float(max(1, currentImage.width))
            let dy = Float(transform.ty) / Float(max(1, currentImage.height))
            translationMag = sqrtf(dx * dx + dy * dy)
        }

        var warpMag: Float = 0
        if includeHomography, let homoObs = homographyRequest.results?.first as? VNImageHomographicAlignmentObservation {
            let H = homoObs.warpTransform
            let scale = H[2][2]
            if abs(scale) > 1e-5 {
                let n = H * (1.0 / scale)
                let identity = matrix_identity_float3x3
                let diff = n - identity
                // Frobenius norm of normalized homography deviation
                var sumSq: Float = 0
                for c in 0..<3 {
                    for r in 0..<3 {
                        let v = diff[c][r]
                        // Normalize translation column entries by image dimension if unnormalized
                        let adjusted: Float
                        if c == 2 && r < 2 {
                            let dim = Float(r == 0 ? max(1, currentImage.width) : max(1, currentImage.height))
                            adjusted = abs(v) > 2.0 ? (v / dim) : v
                        } else {
                            adjusted = v
                        }
                        sumSq += adjusted * adjusted
                    }
                }
                warpMag = sqrtf(sumSq)
            }
        }

        return (translationMag, warpMag)
    }

    /// Downsamples the frame in memory to a 32x24 grid and computes Rec. 709 mean luminance and variance
    /// across 100% of the frame for webcam occlusion detection.
    public static func computeFrameLuminanceStats(_ image: CGImage) -> (mean: Float, variance: Float) {
        let sampleW = 32
        let sampleH = 24
        let count = sampleW * sampleH
        var rawBytes = [UInt8](repeating: 0, count: count * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: &rawBytes,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (0.5, 0.05)
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))

        var lumaValues = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let offset = i * 4
            let r = Float(rawBytes[offset]) / 255.0
            let g = Float(rawBytes[offset + 1]) / 255.0
            let b = Float(rawBytes[offset + 2]) / 255.0
            lumaValues[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        var mean: Float = 0
        vDSP_meanv(lumaValues, 1, &mean, vDSP_Length(count))

        var meanSq: Float = 0
        vDSP_measqv(lumaValues, 1, &meanSq, vDSP_Length(count))
        let variance = max(0, meanSq - mean * mean)

        return (mean, variance)
    }
}
