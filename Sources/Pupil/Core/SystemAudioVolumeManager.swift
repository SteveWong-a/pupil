//
//  SystemAudioVolumeManager.swift
//  Pupil
//
//  Non-blocking, generation-guarded coordinator that executes CoreAudio HAL and
//  AVAudioEngine volume transitions off @MainActor in strict FIFO order.
//

import Foundation

public protocol SystemAudioVolumeManaging: Sendable {
    /// Starts alarm audio off the main thread. When `overrideSpeakers` is true, switches
    /// default output to built-in speakers and sets initial volume before starting synthesis.
    func beginAlarmAudio(
        sessionID: UInt64,
        baseFrequencyHz: Double,
        overrideSpeakers: Bool,
        initialEvaluation: SirenEscalationEvaluation
    )

    /// Applies an incremental volume/gain escalation step for `sessionID` off the main thread.
    /// Dropped immediately if `sessionID` is no longer active.
    func applyEscalationStep(
        sessionID: UInt64,
        overrideSpeakers: Bool,
        evaluation: SirenEscalationEvaluation
    )

    /// Invalidates `sessionID`, stops siren synthesis, and restores any captured
    /// `SystemAudioSnapshot` off the main thread.
    func endAlarmAudio(sessionID: UInt64)
}

public final class SystemAudioVolumeManager: SystemAudioVolumeManaging, @unchecked Sendable {
    public static let shared = SystemAudioVolumeManager()

    private static let minimumDeltaThreshold: Float = 0.005

    private let stateLock = NSLock()
    private let workerQueue: DispatchQueue
    private let audioController: SystemAudioController
    private let sirenSynthesizer: any SirenPlaybackControlling

    private var activeSessionID: UInt64 = 0
    private var lastAppliedHardwareVolume: Float?
    private var lastAppliedOutputGain: Float?

    public init(
        audioController: SystemAudioController = .shared,
        sirenSynthesizer: any SirenPlaybackControlling = SirenSynthesizer.shared,
        workerQueue: DispatchQueue = DispatchQueue(label: "com.pupil.system-audio-volume", qos: .userInitiated)
    ) {
        self.audioController = audioController
        self.sirenSynthesizer = sirenSynthesizer
        self.workerQueue = workerQueue
    }

    public func beginAlarmAudio(
        sessionID: UInt64,
        baseFrequencyHz: Double,
        overrideSpeakers: Bool,
        initialEvaluation: SirenEscalationEvaluation
    ) {
        let effectiveGain = overrideSpeakers ? initialEvaluation.synthesizerGain : initialEvaluation.volumeFactor

        stateLock.lock()
        activeSessionID = sessionID
        lastAppliedHardwareVolume = overrideSpeakers ? initialEvaluation.hardwareVolume : nil
        lastAppliedOutputGain = effectiveGain
        stateLock.unlock()

        workerQueue.async { [weak self] in
            guard let self else { return }
            guard self.isSessionActive(sessionID) else { return }

            if overrideSpeakers {
                self.audioController.forceBuiltInSpeakers(volume: initialEvaluation.hardwareVolume)
                guard self.isSessionActive(sessionID) else {
                    self.audioController.restoreIfNeeded()
                    return
                }
            }

            self.sirenSynthesizer.start(
                baseFrequencyHz: baseFrequencyHz,
                overrideSpeakers: false,
                targetVolume: initialEvaluation.targetVolume,
                outputGain: effectiveGain
            )
        }
    }

    public func applyEscalationStep(
        sessionID: UInt64,
        overrideSpeakers: Bool,
        evaluation: SirenEscalationEvaluation
    ) {
        let effectiveGain = overrideSpeakers ? evaluation.synthesizerGain : evaluation.volumeFactor

        stateLock.lock()
        guard activeSessionID == sessionID else {
            stateLock.unlock()
            return
        }

        let hardwareChanged: Bool
        if overrideSpeakers {
            let delta = abs(evaluation.hardwareVolume - (lastAppliedHardwareVolume ?? -1))
            hardwareChanged = delta >= Self.minimumDeltaThreshold
                || (evaluation.isComplete && evaluation.hardwareVolume != lastAppliedHardwareVolume)
        } else {
            hardwareChanged = false
        }

        let gainDelta = abs(effectiveGain - (lastAppliedOutputGain ?? -1))
        let gainChanged = gainDelta >= Self.minimumDeltaThreshold
            || (evaluation.isComplete && effectiveGain != lastAppliedOutputGain)

        guard hardwareChanged || gainChanged else {
            stateLock.unlock()
            return
        }

        if overrideSpeakers {
            lastAppliedHardwareVolume = evaluation.hardwareVolume
        }
        lastAppliedOutputGain = effectiveGain
        stateLock.unlock()

        workerQueue.async { [weak self] in
            guard let self else { return }
            guard self.isSessionActive(sessionID) else { return }

            if overrideSpeakers && hardwareChanged {
                self.audioController.updateOverrideVolume(evaluation.hardwareVolume)
            }
            if gainChanged {
                self.sirenSynthesizer.setOutputGain(effectiveGain)
            }
        }
    }

    public func endAlarmAudio(sessionID: UInt64) {
        stateLock.lock()
        let shouldEnd: Bool
        if sessionID == 0 || activeSessionID == sessionID {
            activeSessionID = 0
            lastAppliedHardwareVolume = nil
            lastAppliedOutputGain = nil
            shouldEnd = true
        } else {
            shouldEnd = false
        }
        stateLock.unlock()

        guard shouldEnd else { return }

        workerQueue.async { [weak self] in
            guard let self else { return }
            self.sirenSynthesizer.stop()
            self.audioController.restoreIfNeeded()
        }
    }

    private func isSessionActive(_ sessionID: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return sessionID != 0 && activeSessionID == sessionID
    }
}
