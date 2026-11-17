//
//  SirenEscalationEvaluator.swift
//  Pupil
//
//  Pure, deterministic siren volume escalation curve evaluator.
//

import Foundation

public enum SirenEscalationProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case immediate
    case stepped
    case smoothRamp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .immediate: return "Immediate"
        case .stepped: return "Stepped"
        case .smoothRamp: return "Smooth ramp"
        }
    }

    public var subtitle: String {
        switch self {
        case .immediate:
            return "Starts immediately at 100% of configured volume."
        case .stepped:
            return "Escalates in three discrete steps (30% → 60% → 100% over 8 seconds)."
        case .smoothRamp:
            return "Continuously ramps from 30% to 100% of configured volume over 8 seconds."
        }
    }
}

public struct SirenEscalationEvaluation: Sendable, Equatable {
    /// Normalized escalation progress along the active duration in [0.0, 1.0].
    public let progress: Double

    /// Relative curve multiplier in [0.30, 1.00] (1.00 when immediate or disabled).
    public let volumeFactor: Float

    /// Acoustic target volume relative to full scale (`volumeFactor * clampedMaxVolume`).
    public let targetVolume: Float

    /// Hardware-clamped system speaker volume in [0.10, 1.00] for `SystemAudioController`.
    public let hardwareVolume: Float

    /// Residual mixer gain (`targetVolume / hardwareVolume`) in (0.0, 1.0] for `SirenSynthesizer`
    /// when `hardwareVolume` is clamped at the 0.10 CoreAudio minimum floor.
    public let synthesizerGain: Float

    /// Discrete stage indicator (0 = immediate/disabled, 1...3 = escalation stage).
    public let stageIndex: Int

    /// `true` once the curve has reached its 1.00 plateau and no further ticks are needed.
    public let isComplete: Bool

    public init(
        progress: Double,
        volumeFactor: Float,
        targetVolume: Float,
        hardwareVolume: Float,
        synthesizerGain: Float,
        stageIndex: Int,
        isComplete: Bool
    ) {
        self.progress = progress
        self.volumeFactor = volumeFactor
        self.targetVolume = targetVolume
        self.hardwareVolume = hardwareVolume
        self.synthesizerGain = synthesizerGain
        self.stageIndex = stageIndex
        self.isComplete = isComplete
    }
}

public struct SirenEscalationEvaluator: Sendable, Equatable {
    public static let initialVolumeFactor: Float = 0.30
    public static let steppedMidVolumeFactor: Float = 0.60
    public static let fullVolumeFactor: Float = 1.00
    public static let minimumHardwareVolume: Float = 0.10
    public static let defaultRampDurationSeconds: TimeInterval = 8.0
    public static let evaluationTickIntervalSeconds: TimeInterval = 0.25

    public init() {}

    /// Evaluates the siren escalation curve at `elapsedSeconds` and splits the target output
    /// into hardware speaker volume (clamped to CoreAudio's 0.10 floor) and residual mixer gain.
    public static func evaluate(
        elapsedSeconds: TimeInterval,
        profile: SirenEscalationProfile,
        maxVolume: Float = 1.0,
        enabled: Bool = true,
        rampDurationSeconds: TimeInterval = SirenEscalationEvaluator.defaultRampDurationSeconds
    ) -> SirenEscalationEvaluation {
        let clampedMax = min(max(maxVolume.isFinite ? maxVolume : 1.0, minimumHardwareVolume), 1.0)
        let effectiveDuration = rampDurationSeconds.isFinite ? max(0.0, rampDurationSeconds) : defaultRampDurationSeconds

        let clampedElapsed: TimeInterval
        if elapsedSeconds.isNaN {
            clampedElapsed = 0.0
        } else if elapsedSeconds == .infinity {
            clampedElapsed = effectiveDuration
        } else if elapsedSeconds <= 0.0 {
            clampedElapsed = 0.0
        } else {
            clampedElapsed = elapsedSeconds
        }

        let progress: Double
        let volumeFactor: Float
        let stageIndex: Int
        let isComplete: Bool

        if !enabled || profile == .immediate || effectiveDuration <= 0.0 {
            progress = 1.0
            volumeFactor = fullVolumeFactor
            stageIndex = 0
            isComplete = true
        } else {
            progress = min(max(clampedElapsed / effectiveDuration, 0.0), 1.0)
            switch profile {
            case .immediate:
                volumeFactor = fullVolumeFactor
                stageIndex = 0
                isComplete = true
            case .stepped:
                if clampedElapsed < effectiveDuration * 0.5 {
                    volumeFactor = initialVolumeFactor
                    stageIndex = 1
                    isComplete = false
                } else if clampedElapsed < effectiveDuration {
                    volumeFactor = steppedMidVolumeFactor
                    stageIndex = 2
                    isComplete = false
                } else {
                    volumeFactor = fullVolumeFactor
                    stageIndex = 3
                    isComplete = true
                }
            case .smoothRamp:
                volumeFactor = initialVolumeFactor + (fullVolumeFactor - initialVolumeFactor) * Float(progress)
                isComplete = progress >= 1.0
                if isComplete {
                    stageIndex = 3
                } else if progress < 0.5 {
                    stageIndex = 1
                } else {
                    stageIndex = 2
                }
            }
        }

        let targetVolume = volumeFactor * clampedMax
        let hardwareVolume = min(max(targetVolume, minimumHardwareVolume), 1.0)
        let synthesizerGain = hardwareVolume > 0 ? min(max(targetVolume / hardwareVolume, 0.0), 1.0) : 1.0

        return SirenEscalationEvaluation(
            progress: progress,
            volumeFactor: volumeFactor,
            targetVolume: targetVolume,
            hardwareVolume: hardwareVolume,
            synthesizerGain: synthesizerGain,
            stageIndex: stageIndex,
            isComplete: isComplete
        )
    }

    public static func targetVolume(
        elapsedSeconds: TimeInterval,
        profile: SirenEscalationProfile,
        maxVolume: Float = 1.0,
        enabled: Bool = true,
        rampDurationSeconds: TimeInterval = SirenEscalationEvaluator.defaultRampDurationSeconds
    ) -> Float {
        evaluate(
            elapsedSeconds: elapsedSeconds,
            profile: profile,
            maxVolume: maxVolume,
            enabled: enabled,
            rampDurationSeconds: rampDurationSeconds
        ).targetVolume
    }

    public func evaluate(
        elapsedSeconds: TimeInterval,
        profile: SirenEscalationProfile,
        maxVolume: Float = 1.0,
        enabled: Bool = true,
        rampDurationSeconds: TimeInterval = SirenEscalationEvaluator.defaultRampDurationSeconds
    ) -> SirenEscalationEvaluation {
        Self.evaluate(
            elapsedSeconds: elapsedSeconds,
            profile: profile,
            maxVolume: maxVolume,
            enabled: enabled,
            rampDurationSeconds: rampDurationSeconds
        )
    }
}
