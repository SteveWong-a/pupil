//
//  SecurityCoordinator.swift
//  Pupil
//
//  Deterministic security state machine and hardware/vision event coordinator.
//  States: DISARMED -> ARMING -> ARMED -> TAMPER_PENDING -> ALARM
//

import AppKit
import Foundation
import Observation

public enum SecurityState: String, Codable, Sendable, CaseIterable {
    case disarmed = "DISARMED"
    case arming = "ARMING"
    case armed = "ARMED"
    case tamperPending = "TAMPER_PENDING"
    case alarm = "ALARM"

    public var label: String {
        switch self {
        case .disarmed: return "Disarmed"
        case .arming: return "Arming…"
        case .armed: return "Armed"
        case .tamperPending: return "Tamper Countdown"
        case .alarm: return "Alarm Latched"
        }
    }

    public var symbolName: String {
        switch self {
        case .disarmed: return "eye"
        case .arming: return "timer"
        case .armed: return "eye.slash.fill"
        case .tamperPending: return "exclamationmark.triangle.fill"
        case .alarm: return "light.beacon.max.fill"
        }
    }
}

public enum TamperSource: String, Codable, Sendable {
    case chargerUnplugged = "AC Charger Unplugged"
    case lidClosed = "Clamshell Lid Closed"
    case screenLocked = "Screen Locked"
    case wakeWhileArmed = "System Woke While Armed"
    case cameraMotionDetected = "Spatial Lift / Motion Detected"
    case manualTest = "Simulated Tamper Test"

    public static let spatialLiftDetected: TamperSource = .cameraMotionDetected
}

public struct SecurityEventRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let title: String
    public let detail: String
    public let stateAtEvent: SecurityState
    public let isSimulated: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        title: String,
        detail: String,
        stateAtEvent: SecurityState,
        isSimulated: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.stateAtEvent = stateAtEvent
        self.isSimulated = isSimulated
    }
}

@MainActor
@Observable
public final class SecurityCoordinator {
    public private(set) var state: SecurityState = .disarmed
    public private(set) var countdownSecondsRemaining: Int = 0
    public private(set) var activeTamperSource: TamperSource?
    public private(set) var activeTamperTime: Date?
    public private(set) var activeAlarmTime: Date?
    public private(set) var isTouchIDActive: Bool = false

    public var activeAlertTimestampFormatted: String? {
        guard let date = (state == .alarm ? activeAlarmTime : activeTamperTime) else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    public var activeAlertRelativeTime: String? {
        guard let date = (state == .alarm ? activeAlarmTime : activeTamperTime) else { return nil }
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))
        if elapsed < 5 { return "just now" }
        if elapsed < 60 { return "\(elapsed)s ago" }
        let mins = elapsed / 60
        if mins < 60 { return "\(mins)m ago" }
        let hours = mins / 60
        return "\(hours)h ago"
    }
    public private(set) var isGazeWarningActive: Bool = false
    public private(set) var gazeDwellProgress: Double = 0
    public private(set) var latestGazeScore: Float = 0
    public private(set) var eyeLookOffset: CGPoint = .zero
    public private(set) var activeFaceCount: Int = 0
    public private(set) var latestFaceBoundingBoxes: [CGRect] = []
    public private(set) var latestTextureEnergy: Float = 0
    public private(set) var isTextureAdequate: Bool = true
    public private(set) var hasMotionAnchor: Bool = false
    public private(set) var latestMotionDisplacementScore: Float = 0
    public private(set) var continuousMotionSeconds: Double = 0
    public private(set) var motionAnchorDepthMeters: Float?
    public private(set) var events: [SecurityEventRecord] = []
    public private(set) var hasEnrolledPin: Bool = KeychainManager.hasEnrolledPin
    public private(set) var isCameraPreviewRequested: Bool = false
    public private(set) var isShieldPreviewActive: Bool = false
    public private(set) var isInteractiveUnlockRequested: Bool = false
    public private(set) var isLiveCalibrating: Bool = false
    public private(set) var liveCalibrationSecondsRemaining: Int = 0
    public private(set) var liveCalibrationReport: RoomCalibrationProfile?
    public var isPreviewFocusOverlayEnabled: Bool = true

    private var armedGlobalInputMonitor: Any?
    private var armedLocalInputMonitor: Any?
    private var armedInputPollingTimer: Timer?
    private var armedSettleWorkItem: DispatchWorkItem?
    private var armedInputMonitoringActive = false
    private var armedMonitoringStartTime: TimeInterval = 0
    private var motionSettledStartTime: TimeInterval?
    private var previewRestingStartTime: TimeInterval?

    public let settings: PupilSettings
    public let powerMonitor: PowerAndLidMonitor
    public let lockMonitor: LockMonitor
    public let cameraManager: CameraManager
    public let webPushManager: WebPushManager
    public let alertNotifier: AlertNotifier
    /// Injectable clock (epoch seconds) so corroboration windows are testable.
    public var clock: () -> TimeInterval = { Date().timeIntervalSince1970 }

    public var onStateChanged: ((SecurityState) -> Void)?
    public var onNotchUpdateNeeded: (() -> Void)?

    public private(set) var activeRoomProfile: RoomCalibrationProfile?
    private var roomProfiler = RoomNoiseProfiler()
    private var gazeAggregator = GazeTemporalAggregator()
    private var motionAggregator = MotionTemporalAggregator()
    private var tamperScorer = TamperScorer()
    private var lastMotionWarningTime: TimeInterval = 0
    private var countdownTimer: Timer?
    private var alarmReminderTimer: Timer?
    private var alarmStartTime: TimeInterval?
    private var gazeWarningDismissWorkItem: DispatchWorkItem?
    private var liveCalibrationProfiler = RoomNoiseProfiler()
    private var liveCalibrationTimer: Timer?

    public init(
        settings: PupilSettings = .shared,
        powerMonitor: PowerAndLidMonitor = PowerAndLidMonitor(),
        lockMonitor: LockMonitor = LockMonitor(),
        cameraManager: CameraManager = CameraManager(),
        webPushManager: WebPushManager? = nil,
        alertNotifier: AlertNotifier? = nil
    ) {
        self.settings = settings
        self.powerMonitor = powerMonitor
        self.lockMonitor = lockMonitor
        self.cameraManager = cameraManager
        let pushManager = webPushManager ?? WebPushManager(settings: settings)
        self.webPushManager = pushManager
        self.alertNotifier = alertNotifier ?? AlertNotifier { message in
            await pushManager.deliverPush(message)
        }
        self.alertNotifier.onResult = { [weak self] message, result in
            self?.logAlertResult(message, result)
        }

        // Ensure a default PIN ("1234") is enrolled on first launch if none exists so the user can test immediately,
        // and clearly surface PIN changes in Settings.
        if !hasEnrolledPin {
            try? KeychainManager.enrollPin("1234")
            self.hasEnrolledPin = true
        }

        bindSensors()

        NotificationCenter.default.addObserver(
            forName: .screenShieldSync,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.settings.gazeDetectionEnabled && self.isGazeWarningActive {
                    self.dismissGazeWarning()
                }
                self.syncCameraLifecycle()
                if self.state == .armed {
                    if self.settings.lockOnInputWhenArmed {
                        self.startArmedInputMonitoring()
                    } else {
                        self.stopArmedInputMonitoring()
                    }
                }
            }
        }
    }

    public var isMonitoring: Bool {
        state != .disarmed
    }

    public var menuBarSymbolName: String {
        if state == .armed && isGazeWarningActive {
            return "eye.fill"
        }
        return state.symbolName
    }

    // MARK: - Arm & Disarm Lifecycle

    public func startArming(immediate: Bool = false) {
        guard state == .disarmed else { return }
        gazeAggregator.reset()
        motionAggregator.reset()
        tamperScorer.reset()
        cameraManager.resetMotionAnchor()
        hasMotionAnchor = false
        latestMotionDisplacementScore = 0
        continuousMotionSeconds = 0
        motionAnchorDepthMeters = nil
        isGazeWarningActive = false
        gazeDwellProgress = 0
        activeTamperSource = nil
        activeTamperTime = nil
        activeAlarmTime = nil

        if settings.holdSleepOnLidClose {
            powerMonitor.acquireSleepHoldAssertion()
        }

        roomProfiler.reset()
        activeRoomProfile = nil

        if immediate || settings.exitDelaySeconds <= 0 {
            completeArming()
            return
        }

        state = .arming
        countdownSecondsRemaining = settings.exitDelaySeconds
        logEvent("Arming Started", detail: "\(settings.exitDelaySeconds)s exit delay started.")
        powerMonitor.isFastPolling = true
        syncCameraLifecycle()
        onStateChanged?(state)
        onNotchUpdateNeeded?()

        startCountdownTimer(seconds: settings.exitDelaySeconds) { [weak self] in
            self?.completeArming()
        }
    }

    public func completeArming() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownSecondsRemaining = 0
        motionAggregator.reset()
        tamperScorer.reset()
        cameraManager.resetMotionAnchor()
        hasMotionAnchor = false
        latestMotionDisplacementScore = 0
        continuousMotionSeconds = 0
        motionAnchorDepthMeters = nil
        state = .armed
        cameraManager.shouldReanchorOnFaceAcquisition = false
        if let profile = roomProfiler.finalizeCalibration() {
            activeRoomProfile = profile
            logEvent(
                "Room Calibrated",
                detail: "Baseline noise floor \(String(format: "%.3f", profile.noiseFloorScore)) (\(profile.noiseLevelDescription)). Environment locked."
            )
        }
        isInteractiveUnlockRequested = false
        startArmedInputMonitoring()
        let acNote: String
        if powerMonitor.isOnACPower {
            acNote = "AC power connected (unplug armed)."
        } else if settings.isSpatialMotionEnabled {
            acNote = "Armed on battery (Spatial Lift Detection active)."
        } else {
            acNote = "Armed on battery."
        }
        logEvent("System Armed", detail: "Monitoring active. \(acNote)")
        syncCameraLifecycle()
        onStateChanged?(state)
        onNotchUpdateNeeded?()
    }

    @discardableResult
    public func disarmWithPin(_ pin: String) -> Bool {
        guard KeychainManager.verifyPin(pin) else {
            logEvent("Disarm Failed", detail: "Incorrect PIN entered during \(state.label).")
            if settings.hapticFeedbackEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            return false
        }
        performValidatedDisarm(method: "PIN")
        return true
    }

    public func disarmWithTouchID() async -> Bool {
        guard settings.allowTouchIDDisarm else { return false }
        guard !isTouchIDActive else { return false }
        isTouchIDActive = true
        defer { isTouchIDActive = false }

        let ok = await KeychainManager.authenticateWithTouchID(reason: "Disarm Pupil laptop security")
        if ok {
            performValidatedDisarm(method: "Touch ID")
        }
        return ok
    }

    /// Allows canceling during the initial `ARMING` exit-delay without requiring a PIN.
    public func cancelArmingDuringExitDelay() {
        guard state == .arming else { return }
        stopArmedInputMonitoring()
        isInteractiveUnlockRequested = false
        performValidatedDisarm(method: "Exit Delay Cancel")
    }

    public func updatePin(newPin: String) throws {
        try KeychainManager.enrollPin(newPin)
        hasEnrolledPin = KeychainManager.hasEnrolledPin
        logEvent("PIN Updated", detail: "Security PIN updated in macOS Keychain.")
    }

    public func recoverPinWithDeviceOwnerAuth(newPin: String? = nil) async -> Bool {
        let verified = await KeychainManager.authenticateDeviceOwner(
            reason: "Verify Mac login password or Touch ID to unlock or reset your Pupil PIN"
        )
        guard verified else { return false }
        if let newPin, KeychainManager.isValidPinFormat(newPin) {
            try? KeychainManager.enrollPin(newPin)
            hasEnrolledPin = KeychainManager.hasEnrolledPin
            logEvent("PIN Reset via Mac Password", detail: "Security PIN reset after macOS owner verification.")
        }
        if state != .disarmed || isInteractiveUnlockRequested {
            performValidatedDisarm(method: "Mac Password")
        }
        return true
    }

    private func performValidatedDisarm(method: String) {
        let wasAlarm = (state == .alarm)
        KeychainManager.cancelPendingAuthentication()
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownSecondsRemaining = 0
        alarmReminderTimer?.invalidate()
        alarmReminderTimer = nil
        alarmStartTime = nil
        SirenSynthesizer.shared.stop()
        powerMonitor.releaseSleepHoldAssertion()

        state = .disarmed
        activeTamperSource = nil
        activeTamperTime = nil
        activeAlarmTime = nil
        isGazeWarningActive = false
        isShieldPreviewActive = false
        isInteractiveUnlockRequested = false
        powerMonitor.isFastPolling = false
        stopArmedInputMonitoring()
        gazeDwellProgress = 0
        gazeAggregator.reset()
        motionAggregator.reset()
        tamperScorer.reset()
        cameraManager.shouldReanchorOnFaceAcquisition = true
        cameraManager.resetMotionAnchor()
        hasMotionAnchor = false
        latestMotionDisplacementScore = 0
        continuousMotionSeconds = 0
        motionAnchorDepthMeters = nil
        syncCameraLifecycle()

        logEvent("Disarmed", detail: "Session disarmed via \(method).")
        onStateChanged?(state)
        onNotchUpdateNeeded?()

        if wasAlarm {
            alertNotifier.send(AlertMessage(
                title: "Pupil Disarmed",
                body: "Alarm silenced and laptop disarmed via \(method).",
                severity: "high",
                tag: "pupil-alarm"
            ))
        }
    }

    // MARK: - Armed User Input Monitoring

    private func startArmedInputMonitoring() {
        stopArmedInputMonitoring()
        guard settings.lockOnInputWhenArmed else { return }

        // Settle grace period: give the user 2.0s after arming to release mouse/trackpad and step away.
        // Prevents the arming click or closing of windows from triggering instant input lockdown!
        armedInputMonitoringActive = false
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.state == .armed, !self.isInteractiveUnlockRequested else { return }
                self.activateArmedInputMonitors()
            }
        }
        armedSettleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func activateArmedInputMonitors() {
        guard state == .armed, !isInteractiveUnlockRequested else { return }
        armedInputMonitoringActive = true
        armedMonitoringStartTime = Date().timeIntervalSince1970

        armedGlobalInputMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.armedInputMonitoringActive else { return }
                self.handleArmedUserInput()
            }
        }

        armedLocalInputMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.armedInputMonitoringActive else { return }
                self.handleArmedUserInput()
            }
            return event
        }

        // Lightweight 10Hz CoreGraphics event source sentinel:
        // Catches any hardware key press or trackpad/mouse click system-wide across all apps and Spaces
        // Only triggers on events that occurred strictly AFTER armedMonitoringStartTime!
        let startTime = armedMonitoringStartTime
        armedInputPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .armed, self.armedInputMonitoringActive, !self.isInteractiveUnlockRequested else { return }
                let now = Date().timeIntervalSince1970

                let keyElapsed = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
                let leftElapsed = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
                let rightElapsed = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
                let otherElapsed = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .otherMouseDown)

                // Must have occurred strictly at or after startTime + 0.1s
                let isNewKey = (now - keyElapsed) >= (startTime + 0.1)
                let isNewLeft = (now - leftElapsed) >= (startTime + 0.1)
                let isNewRight = (now - rightElapsed) >= (startTime + 0.1)
                let isNewOther = (now - otherElapsed) >= (startTime + 0.1)

                if isNewKey || isNewLeft || isNewRight || isNewOther {
                    self.handleArmedUserInput()
                }
            }
        }
    }

    private func stopArmedInputMonitoring() {
        armedSettleWorkItem?.cancel()
        armedSettleWorkItem = nil
        armedInputMonitoringActive = false
        if let monitor = armedGlobalInputMonitor {
            NSEvent.removeMonitor(monitor)
            armedGlobalInputMonitor = nil
        }
        if let monitor = armedLocalInputMonitor {
            NSEvent.removeMonitor(monitor)
            armedLocalInputMonitor = nil
        }
        armedInputPollingTimer?.invalidate()
        armedInputPollingTimer = nil
    }

    public func handleArmedUserInput() {
        guard state == .armed, settings.lockOnInputWhenArmed else { return }
        guard !isInteractiveUnlockRequested else { return }
        isInteractiveUnlockRequested = true
        logEvent("Armed Input Detected", detail: "Keyboard or mouse interaction detected. Screen locked with PIN / Touch ID challenge.")
        onStateChanged?(state)
        onNotchUpdateNeeded?()
        NotificationCenter.default.post(name: .screenShieldSync, object: nil)
        NotificationCenter.default.post(name: .screenShieldOpenPrompt, object: nil)
        alertNotifier.send(AlertMessage(title: "Pupil Screen Locked", body: "Keyboard or trackpad activity detected while your MacBook is armed.", severity: "high", tag: "pupil-input-lock"))
    }

    // MARK: - Tamper & Alarm Escalation

    public func triggerTamper(source: TamperSource, immediateAlarm: Bool = false, simulated: Bool = false) {
        guard state != .disarmed else { return }
        if state == .arming {
            completeArming()
        }

        if state == .alarm {
            logEvent("Repeated Tamper Signal", detail: "\(source.rawValue) while alarm already latched.", simulated: simulated)
            return
        }

        let now = clock()
        tamperScorer.record(source, at: now)
        activeTamperSource = source
        activeTamperTime = Date()

        if immediateAlarm {
            enterAlarm(source: source, simulated: simulated)
            return
        }

        guard state == .armed else { return }
        state = .tamperPending
        countdownSecondsRemaining = settings.gracePeriodSeconds
        logEvent(
            "Tamper Detected: \(source.rawValue)",
            detail: "\(settings.gracePeriodSeconds)s grace countdown started before siren latches.",
            simulated: simulated
        )
        onStateChanged?(state)
        onNotchUpdateNeeded?()

        let grace = settings.gracePeriodSeconds
        alertNotifier.send(AlertMessage(title: "Pupil Tamper Countdown (\(grace)s)", body: "\(source.rawValue) detected on your MacBook. Siren sounds in \(grace)s unless disarmed.", severity: "high", tag: "pupil-tamper"))

        startCountdownTimer(seconds: settings.gracePeriodSeconds) { [weak self] in
            guard let self else { return }
            self.enterAlarm(source: source, simulated: simulated)
        }
    }

    /// Reverts an in-progress grace countdown back to armed monitoring without requiring a PIN
    /// (e.g. when an accidentally disconnected charger is plugged back in).
    public func revertTamperToArmed(reason: String) {
        guard state == .tamperPending else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownSecondsRemaining = 0
        activeTamperSource = nil
        activeTamperTime = nil
        state = .armed
        cameraManager.shouldReanchorOnFaceAcquisition = false
        motionAggregator.reset()
        tamperScorer.reset()
        cameraManager.resetMotionAnchor()
        hasMotionAnchor = false
        latestMotionDisplacementScore = 0
        motionSettledStartTime = nil

        logEvent("Tamper Canceled", detail: "\(reason) Reverted to armed monitoring.")
        onStateChanged?(state)
        onNotchUpdateNeeded?()
        NotificationCenter.default.post(name: .screenShieldSync, object: nil)

        alertNotifier.send(AlertMessage(
            title: "Pupil Armed (Tamper Canceled)",
            body: "\(reason) Grace countdown canceled and system restored to armed state.",
            severity: "high",
            tag: "pupil-tamper"
        ))
    }

    public func enterAlarm(source: TamperSource, simulated: Bool = false) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownSecondsRemaining = 0
        activeTamperSource = source
        activeAlarmTime = Date()
        state = .alarm

        alarmStartTime = clock()
        alarmReminderTimer?.invalidate()
        alarmReminderTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .alarm else { return }
                let elapsedMins = max(1, Int((self.clock() - (self.alarmStartTime ?? self.clock())) / 60))
                self.alertNotifier.send(AlertMessage(
                    title: "Pupil Theft Alarm Active (\(elapsedMins)m)",
                    body: "Audible siren and sleep lock still active on your MacBook. Disarm required.",
                    severity: "critical",
                    tag: "pupil-alarm"
                ))
            }
        }

        powerMonitor.acquireSleepHoldAssertion(reason: "Pupil Active Theft Siren")
        SirenSynthesizer.shared.start(baseFrequencyHz: Double(settings.sirenFrequencyHz))

        logEvent(
            "ALARM LATCHED",
            detail: "Triggered by \(source.rawValue). Audible siren active until PIN or Touch ID disarm.",
            simulated: simulated
        )
        onStateChanged?(state)
        onNotchUpdateNeeded?()

        alertNotifier.send(AlertMessage(title: "Pupil Siren Alarm Active", body: "\(source.rawValue) — Audible siren and sleep lock engaged on your MacBook!", severity: "critical", tag: "pupil-alarm"))
    }

    // MARK: - Gaze Processing & Simulation

    public func ingestGazeSample(_ sample: GazeSample) {
        guard settings.gazeDetectionEnabled || isCameraPreviewRequested else {
            latestFaceBoundingBoxes = []
            if isGazeWarningActive {
                dismissGazeWarning()
            }
            return
        }
        latestFaceBoundingBoxes = sample.faceBoundingBoxes
        let snapshot = gazeAggregator.ingest(
            sample,
            scoreThreshold: settings.gazeSensitivity.scoreThreshold,
            dwellThresholdSeconds: settings.dwellThresholdSeconds
        )
        latestGazeScore = snapshot.latestScore
        gazeDwellProgress = snapshot.dwellProgress
        eyeLookOffset = snapshot.eyeLookOffset
        activeFaceCount = snapshot.activeFaceCount

        guard state == .armed, settings.gazeDetectionEnabled else {
            if isGazeWarningActive {
                dismissGazeWarning()
            }
            return
        }

        if snapshot.isGazeWarningActive {
            if !isGazeWarningActive {
                activateGazeWarning(simulated: false)
            } else {
                scheduleGazeWarningDismissal(delaySeconds: 1.2)
            }
        } else if isGazeWarningActive && snapshot.elapsedDwellSeconds == 0 {
            scheduleGazeWarningDismissal(delaySeconds: 0.35)
        }
    }

    public func ingestMotionSample(_ sample: MotionSample) {
        guard settings.isSpatialMotionEnabled || isCameraPreviewRequested || isLiveCalibrating else { return }

        latestTextureEnergy = sample.textureEnergy
        isTextureAdequate = sample.isRegistrationReliable || sample.textureEnergy >= VisionMotionDetector.minimumTextureEnergy

        if isLiveCalibrating {
            liveCalibrationProfiler.ingest(sample)
        }

        if state == .arming {
            roomProfiler.ingest(sample)
            hasMotionAnchor = sample.isAnchorFrame || hasMotionAnchor
            let translationRatio = sample.isRegistrationReliable
                ? sample.translationMagnitude / max(0.001, settings.spatialMotionSensitivity.translationDeadband)
                : 0
            latestMotionDisplacementScore = min(1.0, translationRatio)
            return
        }

        if state == .disarmed && isCameraPreviewRequested {
            hasMotionAnchor = sample.isAnchorFrame || hasMotionAnchor
            let translationRatio = sample.isRegistrationReliable
                ? sample.translationMagnitude / max(0.001, settings.spatialMotionSensitivity.translationDeadband)
                : 0
            latestMotionDisplacementScore = min(1.0, translationRatio)

            // Auto-re-tare surroundings in preview mode: if laptop was moved to a new resting spot
            // and has been completely stationary for 2.5 seconds, auto-zero the baseline!
            let interFrameRatio = sample.interFrameTranslation / max(0.001, settings.spatialMotionSensitivity.interFrameDeadband)
            if translationRatio >= 0.50 && interFrameRatio < 0.40 {
                if previewRestingStartTime == nil {
                    previewRestingStartTime = sample.timestamp
                } else if let start = previewRestingStartTime, (sample.timestamp - start) >= 2.5 {
                    previewRestingStartTime = nil
                    cameraManager.resetMotionAnchor()
                }
            } else {
                previewRestingStartTime = nil
            }
            return
        }

        guard state == .armed || state == .tamperPending else { return }

        // If currently in tamper countdown from spatial motion, auto-revert once movement has ceased/settled
        if state == .tamperPending && activeTamperSource == .cameraMotionDetected {
            let interFrameRatio = sample.interFrameTranslation / max(0.001, settings.spatialMotionSensitivity.interFrameDeadband)
            let isStill = interFrameRatio < 0.60 && !sample.isFrameOccluded
            if isStill {
                if motionSettledStartTime == nil {
                    motionSettledStartTime = sample.timestamp
                } else if let start = motionSettledStartTime, (sample.timestamp - start) >= 1.2 {
                    // Movement has settled down continuously for 1.2s: auto-revert to armed state!
                    motionSettledStartTime = nil
                    revertTamperToArmed(reason: "Movement settled. Laptop stationary.")
                    return
                }
            } else {
                motionSettledStartTime = nil
            }
        } else {
            motionSettledStartTime = nil
        }

        let snapshot = motionAggregator.ingest(
            sample,
            sensitivity: settings.spatialMotionSensitivity
        )
        hasMotionAnchor = snapshot.hasCapturedAnchor
        latestMotionDisplacementScore = snapshot.effectiveDisplacementScore
        continuousMotionSeconds = max(snapshot.continuousDisplacementSeconds, snapshot.continuousOcclusionSeconds)
        motionAnchorDepthMeters = snapshot.anchorDepthMeters

        if snapshot.isTamperTriggered {
            handleWeakMotionSignal(snapshot)
        }
    }

    /// Camera motion and lens occlusion can be faked by lighting changes, so a lone hit only warns
    /// until it persists or another signal agrees.
    private func handleWeakMotionSignal(_ snapshot: MotionEscalationSnapshot) {
        let now = clock()
        let isOcclusion = snapshot.isSustainedOcclusionDetected && !snapshot.isSustainedLiftDetected
        let decision = tamperScorer.decideWeak(
            .cameraMotionDetected,
            persistenceSeconds: isOcclusion ? snapshot.continuousOcclusionSeconds : snapshot.continuousDisplacementSeconds,
            isOcclusion: isOcclusion,
            alreadyCountingDown: state == .tamperPending,
            at: now
        )
        tamperScorer.record(.cameraMotionDetected, at: now)

        switch decision {
        case .warn:
            guard now - lastMotionWarningTime >= TamperScorer.corroborationWindowSeconds else { return }
            lastMotionWarningTime = now
            logEvent(
                isOcclusion ? "Camera Blocked (unconfirmed)" : "Motion Detected (unconfirmed)",
                detail: "Waiting for persistence or a second signal before starting the countdown."
            )
            onNotchUpdateNeeded?()
        case .countdown:
            triggerTamper(source: .cameraMotionDetected)
        case .alarmNow:
            triggerTamper(source: .cameraMotionDetected, immediateAlarm: true)
        }
    }

    private func logAlertResult(_ message: AlertMessage, _ result: AlertResult) {
        switch result {
        case .delivered(let attempts):
            logEvent("Phone Alert Delivered", detail: "\(message.title)" + (attempts > 1 ? " (after \(attempts) attempts)." : "."))
        case .failed(let attempts, let reason):
            logEvent("Phone Alert Failed", detail: "\(message.title) — gave up after \(attempts) attempt(s): \(reason)")
        case .superseded:
            break
        }
    }

    public func simulateGazeWarning() {
        if state == .disarmed {
            startArming(immediate: true)
        }
        gazeDwellProgress = 1.0
        latestGazeScore = 0.92
        eyeLookOffset = CGPoint(x: 0.25, y: -0.1)
        activateGazeWarning(simulated: true)
    }

    public func previewScreenShield(durationSeconds: Double = 4.5) {
        if durationSeconds <= 0 {
            isShieldPreviewActive = false
            onStateChanged?(state)
            onNotchUpdateNeeded?()
            return
        }
        isShieldPreviewActive = true
        logEvent("Screen Shield Preview", detail: "Previewing full-screen privacy blur for \(String(format: "%.1fs", durationSeconds)).", simulated: true)
        onStateChanged?(state)
        onNotchUpdateNeeded?()

        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isShieldPreviewActive else { return }
                self.isShieldPreviewActive = false
                self.onStateChanged?(self.state)
                self.onNotchUpdateNeeded?()
            }
        }
    }

    private func activateGazeWarning(simulated: Bool) {
        if !simulated && !settings.gazeDetectionEnabled {
            return
        }
        isGazeWarningActive = true
        gazeWarningDismissWorkItem?.cancel()

        logEvent(
            "Gaze Warning",
            detail: "Sustained gaze toward screen detected (≥ \(String(format: "%.1fs", settings.dwellThresholdSeconds))). Deterrent activated.",
            simulated: simulated
        )
        if settings.hapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        onNotchUpdateNeeded?()
        NotificationCenter.default.post(name: .screenShieldSync, object: nil)

        scheduleGazeWarningDismissal(delaySeconds: 3.0)
    }

    public func dismissGazeWarning() {
        gazeWarningDismissWorkItem?.cancel()
        gazeWarningDismissWorkItem = nil
        guard isGazeWarningActive else { return }
        isGazeWarningActive = false
        gazeDwellProgress = 0
        gazeAggregator.reset()
        onNotchUpdateNeeded?()
        NotificationCenter.default.post(name: .screenShieldSync, object: nil)
    }

    private func scheduleGazeWarningDismissal(delaySeconds: Double) {
        gazeWarningDismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dismissGazeWarning()
            }
        }
        gazeWarningDismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: item)
    }

    // MARK: - Camera Lifecycle & Calibration Testing

    public func startLiveCalibrationTest(durationSeconds: Double = 3.0) {
        liveCalibrationTimer?.invalidate()
        liveCalibrationProfiler.reset()
        isLiveCalibrating = true
        liveCalibrationSecondsRemaining = max(1, Int(ceil(durationSeconds)))
        liveCalibrationReport = nil

        setCameraPreviewRequested(true)
        cameraManager.resetMotionAnchor()

        logEvent("Live Calibration Started", detail: "\(liveCalibrationSecondsRemaining)s spatial room noise profiling test in progress.", simulated: true)

        liveCalibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.liveCalibrationSecondsRemaining > 1 {
                    self.liveCalibrationSecondsRemaining -= 1
                } else {
                    self.completeLiveCalibrationTest()
                }
            }
        }
    }

    public func cancelLiveCalibrationTest() {
        liveCalibrationTimer?.invalidate()
        liveCalibrationTimer = nil
        isLiveCalibrating = false
        liveCalibrationSecondsRemaining = 0
    }

    public func completeLiveCalibrationTest() {
        liveCalibrationTimer?.invalidate()
        liveCalibrationTimer = nil
        isLiveCalibrating = false
        liveCalibrationSecondsRemaining = 0

        if let profile = liveCalibrationProfiler.finalizeCalibration() {
            liveCalibrationReport = profile
            activeRoomProfile = profile
            logEvent(
                "Calibration Test Complete",
                detail: "Profile: \(profile.noiseLevelDescription), Noise floor: \(String(format: "%.3f", profile.noiseFloorScore)), Texture: \(profile.textureHealthDescription)",
                simulated: true
            )
            onStateChanged?(state)
            onNotchUpdateNeeded?()
        }
    }

    public func applyLiveCalibrationAsBaseline() {
        guard let profile = liveCalibrationReport else { return }
        activeRoomProfile = profile
        logEvent(
            "Room Baseline Applied",
            detail: "Profile: \(profile.noiseLevelDescription), Noise floor: \(String(format: "%.3f", profile.noiseFloorScore)), Texture: \(profile.textureHealthDescription)"
        )
        onStateChanged?(state)
        onNotchUpdateNeeded?()
    }

    public func setCameraPreviewRequested(_ requested: Bool) {
        isCameraPreviewRequested = requested
        if !requested && !isMonitoring {
            gazeDwellProgress = 0
            latestGazeScore = 0
            activeFaceCount = 0
            latestFaceBoundingBoxes = []
            latestTextureEnergy = 0
            hasMotionAnchor = false
            latestMotionDisplacementScore = 0
            cancelLiveCalibrationTest()
            gazeAggregator.reset()
            cameraManager.resetMotionAnchor()
        } else if requested {
            hasMotionAnchor = false
            latestMotionDisplacementScore = 0
            cameraManager.shouldReanchorOnFaceAcquisition = true
            cameraManager.resetMotionAnchor()
        }
        syncCameraLifecycle()
    }

    /// Re-zeros the baseline against current room surroundings and resets displacement to 0%.
    public func resetSurroundingsBaseline() {
        cameraManager.resetMotionAnchor()
        hasMotionAnchor = false
        latestMotionDisplacementScore = 0
        motionSettledStartTime = nil
        previewRestingStartTime = nil
        logEvent("Surroundings Re-anchored", detail: "Spatial anchor zeroed to current room position.")
    }

    public func syncCameraLifecycle() {
        cameraManager.updateActiveROI(settings.activeCameraROI)
        if !settings.gazeDetectionEnabled && isGazeWarningActive {
            dismissGazeWarning()
        }
        let cameraNeededForMonitoring = isMonitoring && (settings.gazeDetectionEnabled || settings.isSpatialMotionEnabled)
        let shouldRunCamera = isCameraPreviewRequested || cameraNeededForMonitoring
        if shouldRunCamera {
            cameraManager.startCapture(preferredDeviceID: settings.preferredCameraID)
        } else {
            cameraManager.stopCapture()
        }
    }

    public func clearEventLog() {
        events.removeAll()
    }

    // MARK: - Private Sensor Bindings

    private func bindSensors() {
        powerMonitor.onHardwareEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .chargerUnplugged:
                if self.settings.hardwareTriggers.contains(.chargerUnplug) {
                    self.triggerTamper(source: .chargerUnplugged, immediateAlarm: false)
                }
            case .lidClosed:
                if self.settings.hardwareTriggers.contains(.lidClose) {
                    // Physical clamshell closed: trigger immediate siren before macOS cuts audio
                    self.triggerTamper(source: .lidClosed, immediateAlarm: true)
                }
            case .systemWillSleep:
                // System sleep: only treat as lid close if the physical clamshell is ACTUALLY closed
                if PowerAndLidMonitor.readClamshellClosedState() {
                    if self.settings.hardwareTriggers.contains(.lidClose) {
                        self.triggerTamper(source: .lidClosed, immediateAlarm: true)
                    }
                } else if self.isMonitoring {
                    // Laptop is still physically open; reassert awake hold so monitoring continues
                    self.powerMonitor.acquireSleepHoldAssertion(reason: "Pupil Armed Monitoring")
                }
            case .systemDidWake:
                if self.isMonitoring {
                    self.triggerTamper(source: .wakeWhileArmed, immediateAlarm: true)
                }
            case .chargerPluggedIn:
                if self.state == .tamperPending,
                   (self.activeTamperSource == .chargerUnplugged || self.activeTamperSource == .cameraMotionDetected),
                   self.settings.revertTamperOnPowerRestored {
                    self.revertTamperToArmed(reason: "Power adapter reconnected.")
                }
            case .lidOpened:
                break
            }
        }

        lockMonitor.onLockEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .screenLocked:
                if self.settings.hardwareTriggers.contains(.screenLock) {
                    self.triggerTamper(source: .screenLocked, immediateAlarm: false)
                }
            case .willSleep:
                if PowerAndLidMonitor.readClamshellClosedState() {
                    if self.settings.hardwareTriggers.contains(.lidClose) {
                        self.triggerTamper(source: .lidClosed, immediateAlarm: true)
                    }
                }
            case .wake:
                if self.isMonitoring && self.state == .alarm {
                    SirenSynthesizer.shared.start(baseFrequencyHz: Double(self.settings.sirenFrequencyHz))
                }
            case .screenUnlocked:
                break
            }
        }

        cameraManager.onGazeSample = { [weak self] sample in
            self?.ingestGazeSample(sample)
        }

        cameraManager.onMotionSample = { [weak self] sample in
            self?.ingestMotionSample(sample)
        }
    }

    private func startCountdownTimer(seconds: Int, onExpire: @escaping @MainActor () -> Void) {
        countdownTimer?.invalidate()
        countdownSecondsRemaining = seconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.countdownSecondsRemaining > 1 {
                    self.countdownSecondsRemaining -= 1
                    if self.state == .tamperPending && self.settings.countdownChimeEnabled {
                        SirenSynthesizer.shared.playCountdownTick()
                    }
                    self.onNotchUpdateNeeded?()
                } else {
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                    self.countdownSecondsRemaining = 0
                    onExpire()
                }
            }
        }
    }

    private func logEvent(_ title: String, detail: String, simulated: Bool = false) {
        let record = SecurityEventRecord(
            title: title,
            detail: detail,
            stateAtEvent: state,
            isSimulated: simulated
        )
        events.insert(record, at: 0)
        if events.count > 100 {
            events.removeLast(events.count - 100)
        }
    }
}
