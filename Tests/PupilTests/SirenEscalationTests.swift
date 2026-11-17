import CoreAudio
import Foundation
import Testing
@testable import Pupil

private final class MockEscalationAudioBackend: AudioHardwareBackend, @unchecked Sendable {
    private let lock = NSLock()
    var currentDefaultDevice: AudioDeviceID
    var builtInDevice: AudioDeviceID?
    var mutedByDevice: [AudioDeviceID: Bool]
    var volumeByDevice: [AudioDeviceID: Float]
    var setDefaultCalls: [AudioDeviceID] = []
    var setMutedCalls: [(deviceID: AudioDeviceID, muted: Bool)] = []
    var setVolumeCalls: [(deviceID: AudioDeviceID, volume: Float)] = []

    init(
        defaultDevice: AudioDeviceID,
        builtInDevice: AudioDeviceID?,
        mutedByDevice: [AudioDeviceID: Bool],
        volumeByDevice: [AudioDeviceID: Float]
    ) {
        self.currentDefaultDevice = defaultDevice
        self.builtInDevice = builtInDevice
        self.mutedByDevice = mutedByDevice
        self.volumeByDevice = volumeByDevice
    }

    func defaultOutputDeviceID() -> AudioDeviceID? {
        lock.lock()
        defer { lock.unlock() }
        return currentDefaultDevice
    }

    func setDefaultOutputDeviceID(_ deviceID: AudioDeviceID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        currentDefaultDevice = deviceID
        setDefaultCalls.append(deviceID)
        return true
    }

    func builtInSpeakerDeviceID() -> AudioDeviceID? {
        lock.lock()
        defer { lock.unlock() }
        return builtInDevice
    }

    func isMuted(deviceID: AudioDeviceID) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return mutedByDevice[deviceID]
    }

    func setMuted(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        mutedByDevice[deviceID] = muted
        setMutedCalls.append((deviceID: deviceID, muted: muted))
        return true
    }

    func virtualMainVolume(deviceID: AudioDeviceID) -> Float? {
        lock.lock()
        defer { lock.unlock() }
        return volumeByDevice[deviceID]
    }

    func setVirtualMainVolume(_ volume: Float, deviceID: AudioDeviceID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        volumeByDevice[deviceID] = volume
        setVolumeCalls.append((deviceID: deviceID, volume: volume))
        return true
    }
}

private final class MockSirenPlaybackController: SirenPlaybackControlling, @unchecked Sendable {
    struct StartCall: Equatable {
        let baseFrequencyHz: Double
        let overrideSpeakers: Bool
        let targetVolume: Float
        let outputGain: Float
    }

    private let lock = NSLock()
    private var active = false
    var startCalls: [StartCall] = []
    var outputGainCalls: [Float] = []
    var stopCallCount = 0

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func start(
        baseFrequencyHz: Double,
        overrideSpeakers: Bool,
        targetVolume: Float,
        outputGain: Float
    ) {
        lock.lock()
        defer { lock.unlock() }
        active = true
        startCalls.append(StartCall(
            baseFrequencyHz: baseFrequencyHz,
            overrideSpeakers: overrideSpeakers,
            targetVolume: targetVolume,
            outputGain: outputGain
        ))
    }

    func setOutputGain(_ gain: Float) {
        lock.lock()
        defer { lock.unlock() }
        outputGainCalls.append(gain)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        active = false
        stopCallCount += 1
    }
}

private final class MockSystemAudioVolumeManager: SystemAudioVolumeManaging, @unchecked Sendable {
    struct BeginCall: Equatable {
        let sessionID: UInt64
        let baseFrequencyHz: Double
        let overrideSpeakers: Bool
        let initialEvaluation: SirenEscalationEvaluation
    }

    struct StepCall: Equatable {
        let sessionID: UInt64
        let overrideSpeakers: Bool
        let evaluation: SirenEscalationEvaluation
    }

    private let lock = NSLock()
    var beginCalls: [BeginCall] = []
    var stepCalls: [StepCall] = []
    var endedSessionIDs: [UInt64] = []

    func beginAlarmAudio(
        sessionID: UInt64,
        baseFrequencyHz: Double,
        overrideSpeakers: Bool,
        initialEvaluation: SirenEscalationEvaluation
    ) {
        lock.lock()
        defer { lock.unlock() }
        beginCalls.append(BeginCall(
            sessionID: sessionID,
            baseFrequencyHz: baseFrequencyHz,
            overrideSpeakers: overrideSpeakers,
            initialEvaluation: initialEvaluation
        ))
    }

    func applyEscalationStep(
        sessionID: UInt64,
        overrideSpeakers: Bool,
        evaluation: SirenEscalationEvaluation
    ) {
        lock.lock()
        defer { lock.unlock() }
        stepCalls.append(StepCall(
            sessionID: sessionID,
            overrideSpeakers: overrideSpeakers,
            evaluation: evaluation
        ))
    }

    func endAlarmAudio(sessionID: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        endedSessionIDs.append(sessionID)
    }
}

@Suite("Siren Escalation Curve Tests", .serialized)
struct SirenEscalationTests {
    @MainActor
    private func makeIsolatedSettings() -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.siren-escalation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    private func isApproximately(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    @Test("Immediate profile and disabled escalation evaluate at 100% immediately")
    func testImmediateAndDisabledCurveEvaluation() {
        let disabledStepped = SirenEscalationEvaluator.evaluate(
            elapsedSeconds: 0.0,
            profile: .stepped,
            maxVolume: 0.80,
            enabled: false
        )
        #expect(disabledStepped.progress == 1.0)
        #expect(disabledStepped.volumeFactor == 1.00)
        #expect(isApproximately(disabledStepped.targetVolume, 0.80))
        #expect(isApproximately(disabledStepped.hardwareVolume, 0.80))
        #expect(isApproximately(disabledStepped.synthesizerGain, 1.0))
        #expect(disabledStepped.stageIndex == 0)
        #expect(disabledStepped.isComplete == true)

        let disabledSmooth = SirenEscalationEvaluator.evaluate(
            elapsedSeconds: 0.0,
            profile: .smoothRamp,
            maxVolume: 0.65,
            enabled: false
        )
        #expect(disabledSmooth.volumeFactor == 1.00)
        #expect(isApproximately(disabledSmooth.targetVolume, 0.65))
        #expect(disabledSmooth.stageIndex == 0)
        #expect(disabledSmooth.isComplete == true)

        let immediateEnabled = SirenEscalationEvaluator.evaluate(
            elapsedSeconds: 0.0,
            profile: .immediate,
            maxVolume: 0.90,
            enabled: true
        )
        #expect(immediateEnabled.progress == 1.0)
        #expect(immediateEnabled.volumeFactor == 1.00)
        #expect(isApproximately(immediateEnabled.targetVolume, 0.90))
        #expect(immediateEnabled.stageIndex == 0)
        #expect(immediateEnabled.isComplete == true)
    }

    @Test("Stepped profile transitions cleanly across 30%, 60%, and 100% stage boundaries")
    func testSteppedProfileStageBoundaries() {
        let stage1Times: [TimeInterval] = [0.0, 1.5, 3.999]
        for t in stage1Times {
            let eval = SirenEscalationEvaluator.evaluate(
                elapsedSeconds: t,
                profile: .stepped,
                maxVolume: 1.0,
                enabled: true,
                rampDurationSeconds: 8.0
            )
            #expect(isApproximately(eval.volumeFactor, 0.30))
            #expect(isApproximately(eval.targetVolume, 0.30))
            #expect(eval.stageIndex == 1)
            #expect(eval.isComplete == false)
        }

        let stage2Times: [TimeInterval] = [4.0, 5.5, 7.999]
        for t in stage2Times {
            let eval = SirenEscalationEvaluator.evaluate(
                elapsedSeconds: t,
                profile: .stepped,
                maxVolume: 1.0,
                enabled: true,
                rampDurationSeconds: 8.0
            )
            #expect(isApproximately(eval.volumeFactor, 0.60))
            #expect(isApproximately(eval.targetVolume, 0.60))
            #expect(eval.stageIndex == 2)
            #expect(eval.isComplete == false)
        }

        let stage3Times: [TimeInterval] = [8.0, 12.0, 30.0]
        for t in stage3Times {
            let eval = SirenEscalationEvaluator.evaluate(
                elapsedSeconds: t,
                profile: .stepped,
                maxVolume: 1.0,
                enabled: true,
                rampDurationSeconds: 8.0
            )
            #expect(isApproximately(eval.volumeFactor, 1.00))
            #expect(isApproximately(eval.targetVolume, 1.00))
            #expect(eval.stageIndex == 3)
            #expect(eval.isComplete == true)
        }
    }

    @Test("Smooth ramp is monotonic non-decreasing and safely clamps boundary and non-finite inputs")
    func testSmoothRampMonotonicityAndBoundaryClamping() {
        let evaluator = SirenEscalationEvaluator()
        let samples: [(TimeInterval, Float)] = [
            (-5.0, 0.30),
            (0.0, 0.30),
            (2.0, 0.475),
            (4.0, 0.65),
            (6.0, 0.825),
            (8.0, 1.00),
            (25.0, 1.00)
        ]

        var previousFactor: Float = 0.0
        for (elapsed, expectedFactor) in samples {
            let eval = evaluator.evaluate(
                elapsedSeconds: elapsed,
                profile: .smoothRamp,
                maxVolume: 1.0,
                enabled: true,
                rampDurationSeconds: 8.0
            )
            #expect(isApproximately(eval.volumeFactor, expectedFactor))
            #expect(eval.volumeFactor >= previousFactor)
            previousFactor = eval.volumeFactor
            if elapsed >= 8.0 {
                #expect(eval.isComplete == true)
                #expect(eval.stageIndex == 3)
            } else {
                #expect(eval.isComplete == false)
            }
        }

        let nanEval = evaluator.evaluate(elapsedSeconds: .nan, profile: .smoothRamp, maxVolume: 1.0, enabled: true)
        #expect(isApproximately(nanEval.volumeFactor, 0.30))
        #expect(nanEval.progress == 0.0)
        #expect(nanEval.isComplete == false)

        let infEval = evaluator.evaluate(elapsedSeconds: .infinity, profile: .smoothRamp, maxVolume: 1.0, enabled: true)
        #expect(isApproximately(infEval.volumeFactor, 1.00))
        #expect(infEval.progress == 1.0)
        #expect(infEval.isComplete == true)
    }

    @Test("Environment ceiling scaling and 0.10 hardware floor compensation via synthesizer gain")
    func testEnvironmentCeilingScalingAndHardwareFloorCompensation() {
        // .quietLibrary (0.45) at t = 0 under .stepped
        let libraryStart = SirenEscalationEvaluator.evaluate(
            elapsedSeconds: 0.0,
            profile: .stepped,
            maxVolume: Float(EnvironmentPreset.quietLibrary.volume ?? 0.45),
            enabled: true
        )
        #expect(isApproximately(libraryStart.targetVolume, 0.135))
        #expect(isApproximately(libraryStart.hardwareVolume, 0.135))
        #expect(isApproximately(libraryStart.synthesizerGain, 1.0))

        // Low custom ceiling (0.20): 0.30 * 0.20 = 0.06, compensated by 0.10 hardware * 0.60 synth gain
        let lowStart = SirenEscalationEvaluator.evaluate(
            elapsedSeconds: 0.0,
            profile: .stepped,
            maxVolume: 0.20,
            enabled: true
        )
        #expect(isApproximately(lowStart.targetVolume, 0.06))
        #expect(isApproximately(lowStart.hardwareVolume, 0.10))
        #expect(isApproximately(lowStart.synthesizerGain, 0.60))
        #expect(isApproximately(lowStart.hardwareVolume * lowStart.synthesizerGain, lowStart.targetVolume))

        let lowEnd = SirenEscalationEvaluator.evaluate(
            elapsedSeconds: 8.0,
            profile: .stepped,
            maxVolume: 0.20,
            enabled: true
        )
        #expect(isApproximately(lowEnd.targetVolume, 0.20))
        #expect(isApproximately(lowEnd.hardwareVolume, 0.20))
        #expect(isApproximately(lowEnd.synthesizerGain, 1.0))
        #expect(lowEnd.isComplete == true)
    }

    @Test("PupilSettings persists escalation curve settings and falls back safely on invalid raw profile")
    @MainActor
    func testPupilSettingsPersistenceAndInvalidProfileFallback() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(settings.sirenEscalationCurveEnabled == false)
        #expect(settings.sirenEscalationProfile == .smoothRamp)

        settings.sirenEscalationCurveEnabled = true
        settings.sirenEscalationProfile = .stepped

        let reloaded = PupilSettings(defaults: defaults)
        #expect(reloaded.sirenEscalationCurveEnabled == true)
        #expect(reloaded.sirenEscalationProfile == .stepped)

        defaults.set("invalid_profile_value", forKey: "pupil.sirenEscalationProfile")
        let fallbackReloaded = PupilSettings(defaults: defaults)
        #expect(fallbackReloaded.sirenEscalationProfile == .smoothRamp)
    }

    @Test("SystemAudioVolumeManager preserves snapshot, updates override volume, restores, and drops stale steps")
    func testSystemAudioVolumeManagerSnapshotPreservationAndStaleStepCancellation() {
        let headphonesID: AudioDeviceID = 42
        let builtInSpeakerID: AudioDeviceID = 7

        let backend = MockEscalationAudioBackend(
            defaultDevice: headphonesID,
            builtInDevice: builtInSpeakerID,
            mutedByDevice: [headphonesID: true, builtInSpeakerID: true],
            volumeByDevice: [headphonesID: 0.25, builtInSpeakerID: 0.30]
        )
        let audioController = SystemAudioController(backend: backend)
        let sirenController = MockSirenPlaybackController()
        let queue = DispatchQueue(label: "com.pupil.tests.audio-volume-manager")
        let manager = SystemAudioVolumeManager(
            audioController: audioController,
            sirenSynthesizer: sirenController,
            workerQueue: queue
        )

        let evalStart = SirenEscalationEvaluator.evaluate(
            elapsedSeconds: 0.0,
            profile: .stepped,
            maxVolume: 0.80,
            enabled: true
        )
        manager.beginAlarmAudio(
            sessionID: 1,
            baseFrequencyHz: 880.0,
            overrideSpeakers: true,
            initialEvaluation: evalStart
        )
        queue.sync {}

        let expectedSnapshot = SystemAudioSnapshot(deviceID: headphonesID, wasMuted: true, volume: 0.25)
        #expect(audioController.currentSnapshot == expectedSnapshot)
        #expect(backend.defaultOutputDeviceID() == builtInSpeakerID)
        #expect(backend.isMuted(deviceID: builtInSpeakerID) == false)
        #expect(isApproximately(backend.virtualMainVolume(deviceID: builtInSpeakerID) ?? 0, 0.24))
        #expect(sirenController.isActive == true)
        #expect(sirenController.startCalls.count == 1)
        #expect(sirenController.startCalls[0].overrideSpeakers == false)
        #expect(isApproximately(sirenController.startCalls[0].outputGain, 1.0))

        let evalMid = SirenEscalationEvaluator.evaluate(
            elapsedSeconds: 4.0,
            profile: .stepped,
            maxVolume: 0.80,
            enabled: true
        )
        manager.applyEscalationStep(sessionID: 1, overrideSpeakers: true, evaluation: evalMid)
        queue.sync {}

        #expect(audioController.currentSnapshot == expectedSnapshot)
        #expect(isApproximately(backend.virtualMainVolume(deviceID: builtInSpeakerID) ?? 0, 0.48))

        manager.endAlarmAudio(sessionID: 1)
        queue.sync {}

        #expect(sirenController.isActive == false)
        #expect(sirenController.stopCallCount == 1)
        #expect(audioController.hasActiveSnapshot == false)
        #expect(backend.defaultOutputDeviceID() == headphonesID)
        #expect(backend.isMuted(deviceID: headphonesID) == true)
        #expect(isApproximately(backend.virtualMainVolume(deviceID: headphonesID) ?? 0, 0.25))

        let volumeCallsBeforeStale = backend.setVolumeCalls.count
        let evalFull = SirenEscalationEvaluator.evaluate(
            elapsedSeconds: 8.0,
            profile: .stepped,
            maxVolume: 0.80,
            enabled: true
        )
        manager.applyEscalationStep(sessionID: 1, overrideSpeakers: true, evaluation: evalFull)
        queue.sync {}

        #expect(backend.setVolumeCalls.count == volumeCallsBeforeStale)
        #expect(backend.defaultOutputDeviceID() == headphonesID)
        #expect(isApproximately(backend.virtualMainVolume(deviceID: headphonesID) ?? 0, 0.25))
    }

    @Test("SystemAudioVolumeManager uses synthesizer gain only when speaker override is disabled")
    func testSystemAudioVolumeManagerSynthesizerOnlyWhenOverrideDisabled() throws {
        let headphonesID: AudioDeviceID = 42
        let builtInSpeakerID: AudioDeviceID = 7

        let backend = MockEscalationAudioBackend(
            defaultDevice: headphonesID,
            builtInDevice: builtInSpeakerID,
            mutedByDevice: [headphonesID: true, builtInSpeakerID: true],
            volumeByDevice: [headphonesID: 0.25, builtInSpeakerID: 0.30]
        )
        let audioController = SystemAudioController(backend: backend)
        let sirenController = MockSirenPlaybackController()
        let queue = DispatchQueue(label: "com.pupil.tests.audio-synth-only")
        let manager = SystemAudioVolumeManager(
            audioController: audioController,
            sirenSynthesizer: sirenController,
            workerQueue: queue
        )

        let eval1 = SirenEscalationEvaluator.evaluate(elapsedSeconds: 0.0, profile: .stepped, maxVolume: 0.80, enabled: true)
        let eval2 = SirenEscalationEvaluator.evaluate(elapsedSeconds: 4.0, profile: .stepped, maxVolume: 0.80, enabled: true)
        let eval3 = SirenEscalationEvaluator.evaluate(elapsedSeconds: 8.0, profile: .stepped, maxVolume: 0.80, enabled: true)

        manager.beginAlarmAudio(sessionID: 10, baseFrequencyHz: 880.0, overrideSpeakers: false, initialEvaluation: eval1)
        manager.applyEscalationStep(sessionID: 10, overrideSpeakers: false, evaluation: eval2)
        manager.applyEscalationStep(sessionID: 10, overrideSpeakers: false, evaluation: eval3)
        queue.sync {}

        manager.endAlarmAudio(sessionID: 10)
        queue.sync {}

        #expect(backend.setDefaultCalls.isEmpty)
        #expect(backend.setMutedCalls.isEmpty)
        #expect(backend.setVolumeCalls.isEmpty)
        #expect(backend.defaultOutputDeviceID() == headphonesID)
        #expect(backend.isMuted(deviceID: headphonesID) == true)
        #expect(isApproximately(backend.virtualMainVolume(deviceID: headphonesID) ?? 0, 0.25))
        #expect(audioController.hasActiveSnapshot == false)

        try #require(sirenController.startCalls.count == 1)
        #expect(isApproximately(sirenController.startCalls[0].outputGain, 0.30))
        try #require(sirenController.outputGainCalls.count == 2)
        #expect(isApproximately(sirenController.outputGainCalls[0], 0.60))
        #expect(isApproximately(sirenController.outputGainCalls[1], 1.00))
        #expect(sirenController.stopCallCount == 1)
    }

    @Test("SecurityCoordinator drives escalation curve with clock, preserves position across wake, and cleans up on disarm")
    @MainActor
    func testSecurityCoordinatorClockDrivenEscalationWakeAndDisarm() throws {
        try KeychainManager.enrollPin("1234")
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.gazeDetectionEnabled = false
        settings.sirenEscalationCurveEnabled = true
        settings.sirenEscalationProfile = .stepped
        settings.sirenOverrideVolume = 0.80

        let mockAudioManager = MockSystemAudioVolumeManager()
        let lockMonitor = LockMonitor()
        let coordinator = SecurityCoordinator(
            settings: settings,
            lockMonitor: lockMonitor,
            audioVolumeManager: mockAudioManager
        )

        var currentTime: TimeInterval = 1000.0
        coordinator.clock = { currentTime }

        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        // Trigger alarm at t = 1000.0 -> 0.30 * 0.80 = 0.24
        coordinator.enterAlarm(source: .chargerUnplugged)
        #expect(coordinator.state == .alarm)
        #expect(isApproximately(coordinator.currentSirenVolumeFactor, 0.30))
        #expect(mockAudioManager.beginCalls.count == 1)
        #expect(isApproximately(mockAudioManager.beginCalls[0].initialEvaluation.targetVolume, 0.24))

        // Advance clock to t = 1004.0 -> 0.60 * 0.80 = 0.48
        currentTime = 1004.0
        coordinator.tickSirenEscalationIfNeeded()
        #expect(isApproximately(coordinator.currentSirenVolumeFactor, 0.60))
        #expect(mockAudioManager.stepCalls.count == 1)
        #expect(isApproximately(mockAudioManager.stepCalls[0].evaluation.targetVolume, 0.48))

        // Simulate system wake at t = 1006.0 -> resumes at 0.48 (neither resetting to 0.24 nor jumping to 0.80)
        currentTime = 1006.0
        lockMonitor.onLockEvent?(.wake)
        #expect(mockAudioManager.beginCalls.count == 2)
        #expect(isApproximately(coordinator.currentSirenVolumeFactor, 0.60))
        #expect(isApproximately(mockAudioManager.beginCalls[1].initialEvaluation.targetVolume, 0.48))
        #expect(mockAudioManager.beginCalls[1].sessionID != mockAudioManager.beginCalls[0].sessionID)

        // Advance clock to t = 1008.0 -> 1.00 * 0.80 = 0.80 (complete)
        currentTime = 1008.0
        coordinator.tickSirenEscalationIfNeeded()
        #expect(isApproximately(coordinator.currentSirenVolumeFactor, 1.00))
        #expect(mockAudioManager.stepCalls.count == 2)
        #expect(isApproximately(mockAudioManager.stepCalls[1].evaluation.targetVolume, 0.80))
        #expect(mockAudioManager.stepCalls[1].evaluation.isComplete == true)
        #expect(mockAudioManager.stepCalls[1].sessionID == mockAudioManager.beginCalls[1].sessionID)

        // Disarm -> invokes endAlarmAudio and resets volume factor to 1.0
        let disarmed = coordinator.disarmWithPin("1234")
        #expect(disarmed == true)
        #expect(coordinator.state == .disarmed)
        #expect(mockAudioManager.endedSessionIDs == [mockAudioManager.beginCalls[1].sessionID])
        #expect(isApproximately(coordinator.currentSirenVolumeFactor, 1.0))
    }
}
