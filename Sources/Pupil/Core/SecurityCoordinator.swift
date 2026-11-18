//
//  SecurityCoordinator.swift
//  Pupil
//
//  Deterministic security state machine and hardware/vision event coordinator.
//  States: DISARMED -> ARMING -> ARMED -> TAMPER_PENDING -> ALARM
//

import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import Observation
import UniformTypeIdentifiers

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
    case peripheralDisconnected = "Peripheral Unplugged"
    case wakeWhileArmed = "System Woke While Armed"
    case cameraMotionDetected = "Spatial Lift / Motion Detected"
    case pinBruteForce = "Repeated Failed PIN Attempts"
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
    public private(set) var attemptLimiter = PinAttemptLimiter()
    public private(set) var pinLockoutSecondsRemaining: Int = 0
    public var isPinLockedOut: Bool { pinLockoutSecondsRemaining > 0 }

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
    public let bluetoothMonitor: BluetoothProximityMonitor
    public let journalStore: TamperJournalStore
    public let networkSentinel: NetworkPathSentinel
    public let trustedNetworkMonitor: TrustedNetworkMonitor
    public internal(set) var trustedNetworkEvaluator = TrustedNetworkEvaluator()
    public private(set) var trustedNetworkPosture: TrustedNetworkPosture = .disabled
    public var isUntrustedNetworkEscalationActive: Bool {
        settings.trustedNetworkBaselineGazeSensitivity != nil
    }
    private var lastRecordedTrustedMatchEntryID: UUID?
    /// Injectable clock (epoch seconds) so corroboration windows are testable.
    public var clock: () -> TimeInterval = { Date().timeIntervalSince1970 }
    /// Injectable thermal state provider for deterministic testing.
    public var thermalStateProvider: () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }

    public private(set) var idleEvaluator = IdleInactivityEvaluator()
    private var idleInactivityTimer: Timer?
    private var lastSleepWakeOrLidTransitionTime: TimeInterval?
    /// Injectable HID idle seconds provider (defaults to CoreGraphics combined session HID idle time).
    public var hidIdleSecondsProvider: () -> Double = {
        SecurityCoordinator.readSystemHIDIdleSeconds()
    }

    public var onStateChanged: ((SecurityState) -> Void)?
    public var onNotchUpdateNeeded: (() -> Void)?

    public private(set) var activeRoomProfile: RoomCalibrationProfile?
    public internal(set) var armedDisplayTopologyEvaluator = DisplayTopologyEvaluator()
    private var roomProfiler = RoomNoiseProfiler()
    private var gazeAggregator = GazeTemporalAggregator()
    private var motionAggregator = MotionTemporalAggregator()
    private var tamperScorer = TamperScorer()
    private var lastMotionWarningTime: TimeInterval = 0
    private var lastSurroundingsAlertTime: TimeInterval = 0
    private var countdownTimer: Timer?
    private var alarmReminderTimer: Timer?
    private var alarmStartTime: TimeInterval?
    private var gazeWarningDismissWorkItem: DispatchWorkItem?
    private var liveCalibrationProfiler = RoomNoiseProfiler()
    private var liveCalibrationTimer: Timer?
    private var pinLockoutTimer: Timer?
    private var canPersistJournal = true

    nonisolated public static var isRunningUnderTests: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil || env["SWIFT_TESTING_ENABLED"] != nil {
            return true
        }
        let procName = ProcessInfo.processInfo.processName.lowercased()
        if procName.contains("xctest") || procName.contains("testing-helper") || procName.contains("tests") {
            return true
        }
        return !Bundle.main.bundlePath.hasSuffix(".app")
    }

    public convenience init() {
        self.init(
            settings: .shared,
            powerMonitor: PowerAndLidMonitor(),
            lockMonitor: LockMonitor(),
            cameraManager: CameraManager(),
            webPushManager: nil,
            alertNotifier: nil,
            bluetoothMonitor: nil,
            journalStore: nil
        )
    }

    public init(
        settings: PupilSettings = .shared,
        powerMonitor: PowerAndLidMonitor = PowerAndLidMonitor(),
        lockMonitor: LockMonitor = LockMonitor(),
        cameraManager: CameraManager = CameraManager(),
        webPushManager: WebPushManager? = nil,
        alertNotifier: AlertNotifier? = nil,
        bluetoothMonitor: BluetoothProximityMonitor? = nil,
        networkSentinel: NetworkPathSentinel? = nil,
        trustedNetworkMonitor: TrustedNetworkMonitor? = nil,
        journalStore: TamperJournalStore? = nil
    ) {
        let resolvedJournalStore: TamperJournalStore
        if let journalStore {
            resolvedJournalStore = journalStore
        } else if settings === PupilSettings.shared && !Self.isRunningUnderTests {
            resolvedJournalStore = .shared
        } else {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pupil-test-journal-\(UUID().uuidString).enc.json")
            resolvedJournalStore = TamperJournalStore(fileURL: tempURL, symmetricKey: SymmetricKey(size: .bits256))
        }
        self.journalStore = resolvedJournalStore
        self.settings = settings
        self.powerMonitor = powerMonitor
        self.lockMonitor = lockMonitor
        self.cameraManager = cameraManager
        self.bluetoothMonitor = bluetoothMonitor ?? BluetoothProximityMonitor()
        self.networkSentinel = networkSentinel ?? NetworkPathSentinel()
        self.trustedNetworkMonitor = trustedNetworkMonitor ?? TrustedNetworkMonitor()
        let pushManager = webPushManager ?? WebPushManager(settings: settings)
        self.webPushManager = pushManager
        self.alertNotifier = alertNotifier ?? AlertNotifier { message in
            await pushManager.deliverPush(message)
        }
        self.alertNotifier.onResult = { [weak self] message, result in
            self?.logAlertResult(message, result)
        }
        self.webPushManager.onRemoteDisarmRequested = { [weak self] in
            self?.disarmViaRemotePhone()
        }
        self.webPushManager.onRemoteSnapshotRequested = { [weak self] in
            self?.handleRemoteSnapshotRequest()
        }
        self.cameraManager.motionDetector.surroundingsWatchEnabled = settings.surroundingsWatchEnabled

        do {
            let persisted = try resolvedJournalStore.loadRecords()
            if !persisted.isEmpty {
                self.events = Array(persisted.prefix(TamperJournalStore.maxRecords))
            }
        } catch {
            handleJournalLoadFailure(error, journalStore: resolvedJournalStore)
        }

        // Ensure a default PIN ("1234") is enrolled on first launch if none exists so the user can test immediately,
        // and clearly surface PIN changes in Settings.
        if !hasEnrolledPin {
            try? KeychainManager.enrollPin("1234")
            self.hasEnrolledPin = true
        }

        bindSensors()
        syncBluetoothProximityMonitoring()
        syncIdleInactivityMonitoring()
        syncTrustedNetworkMonitoring()

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
                self.syncBluetoothProximityMonitoring()
                self.syncIdleInactivityMonitoring()
                self.syncTrustedNetworkMonitoring()
                if self.state == .armed {
                    if self.settings.lockOnInputWhenArmed {
                        self.startArmedInputMonitoring()
                    } else {
                        self.stopArmedInputMonitoring()
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncAdaptiveVisionFrameRate()
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
        powerMonitor.resetChargerFlapState()
        networkSentinel.startMonitoring()
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
        armedDisplayTopologyEvaluator.reset()
        if let topology = PowerAndLidMonitor.readActiveDisplayTopology() {
            armedDisplayTopologyEvaluator.latchBaseline(topology)
        }

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
        powerMonitor.resetChargerFlapState()
        networkSentinel.startMonitoring()
        motionAggregator.reset()
        tamperScorer.reset()
        cameraManager.resetMotionAnchor()
        hasMotionAnchor = false
        latestMotionDisplacementScore = 0
        continuousMotionSeconds = 0
        motionAnchorDepthMeters = nil
        armedDisplayTopologyEvaluator.reset()
        if let topology = PowerAndLidMonitor.readActiveDisplayTopology() {
            armedDisplayTopologyEvaluator.latchBaseline(topology)
        }
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
        webPushManager.startRemoteCommandListener()
        syncCameraLifecycle()
        onStateChanged?(state)
        onNotchUpdateNeeded?()
    }

    @discardableResult
    public func disarmWithPin(_ pin: String) -> Bool {
        let now = clock()
        let currentStatus = attemptLimiter.status(at: now)
        if currentStatus.isLockedOut {
            pinLockoutSecondsRemaining = currentStatus.remainingSeconds
            startPinLockoutTimerIfNeeded()
            logEvent("PIN Lockout Active", detail: "PIN entry blocked for \(currentStatus.remainingSeconds)s after repeated failed attempts.")
            if settings.hapticFeedbackEnabled && !Self.isRunningUnderTests {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            return false
        }

        guard KeychainManager.verifyPin(pin) else {
            let decision = attemptLimiter.recordFailure(at: now)
            pinLockoutSecondsRemaining = decision.remainingSeconds
            if decision.isLockedOut {
                startPinLockoutTimerIfNeeded()
            }
            switch decision {
            case .allowed:
                logEvent("Disarm Failed", detail: "Incorrect PIN entered during \(state.label).")
            case .lockedOut(let seconds):
                logEvent("PIN Lockout Triggered", detail: "\(attemptLimiter.failedAttemptCount) failed PIN attempts. Locked out for \(seconds)s.")
            case .escalateToAlarm(let seconds):
                logEvent("PIN Brute-Force Lockout", detail: "\(attemptLimiter.failedAttemptCount) failed PIN attempts. Locked out for \(seconds)s and escalating to alarm.")
                if state != .disarmed && state != .alarm {
                    enterAlarm(source: .pinBruteForce)
                }
            }
            if settings.hapticFeedbackEnabled && !Self.isRunningUnderTests {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            onNotchUpdateNeeded?()
            return false
        }

        trustedNetworkEvaluator.suppressCurrentUntrustedSession()
        performValidatedDisarm(method: "PIN")
        return true
    }

    public func resetPinLockout() {
        pinLockoutTimer?.invalidate()
        pinLockoutTimer = nil
        attemptLimiter.recordSuccess()
        pinLockoutSecondsRemaining = 0
    }

    public func refreshPinLockoutCountdown() {
        let current = attemptLimiter.status(at: clock())
        pinLockoutSecondsRemaining = current.remainingSeconds
        if !current.isLockedOut {
            pinLockoutTimer?.invalidate()
            pinLockoutTimer = nil
        }
    }

    private func startPinLockoutTimerIfNeeded() {
        guard pinLockoutTimer == nil else { return }
        pinLockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPinLockoutCountdown()
            }
        }
    }

    public func disarmWithTouchID() async -> Bool {
        guard settings.allowTouchIDDisarm else { return false }
        guard !isTouchIDActive else { return false }
        isTouchIDActive = true
        defer { isTouchIDActive = false }

        let ok = await KeychainManager.authenticateWithTouchID(reason: "Disarm Pupil laptop security")
        if ok {
            trustedNetworkEvaluator.suppressCurrentUntrustedSession()
            performValidatedDisarm(method: "Touch ID")
        }
        return ok
    }

    /// Allows canceling during the initial `ARMING` exit-delay without requiring a PIN.
    public func cancelArmingDuringExitDelay() {
        guard state == .arming else { return }
        stopArmedInputMonitoring()
        isInteractiveUnlockRequested = false
        idleEvaluator.suppressCurrentStreak()
        trustedNetworkEvaluator.suppressCurrentUntrustedSession()
        performValidatedDisarm(method: "Exit Delay Cancel")
    }

    @discardableResult
    public func disarmViaRemotePhone() -> Bool {
        guard state == .armed || state == .tamperPending || state == .alarm else { return false }
        trustedNetworkEvaluator.suppressCurrentUntrustedSession()
        performValidatedDisarm(method: "Remote Phone")
        logEvent("Disarmed Remotely via Phone", detail: "Authenticated remote disarm command received from paired phone.")
        return true
    }

    @discardableResult
    public func disarmFromTrustedProximity() -> Bool {
        guard settings.bluetoothProximityEnabled,
              settings.bluetoothAutoDisarmEnabled,
              state == .armed else { return false }
        trustedNetworkEvaluator.suppressCurrentUntrustedSession()
        performValidatedDisarm(method: "Bluetooth Proximity")
        let deviceName = settings.trustedBluetoothDeviceName.isEmpty ? "Trusted Device" : settings.trustedBluetoothDeviceName
        logEvent("Disarmed via Bluetooth Proximity", detail: "\(deviceName) returned within proximity.")
        return true
    }

    public func syncBluetoothProximityMonitoring() {
        if settings.bluetoothProximityEnabled,
           !settings.trustedBluetoothDeviceUUID.isEmpty,
           let uuid = UUID(uuidString: settings.trustedBluetoothDeviceUUID) {
            bluetoothMonitor.startMonitoring(deviceUUID: uuid)
        } else {
            bluetoothMonitor.stopMonitoring()
        }
    }

    nonisolated public static func readSystemHIDIdleSeconds() -> Double {
        let eventTypes: [CGEventType] = [
            .keyDown,
            .keyUp,
            .flagsChanged,
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .scrollWheel
        ]
        var minElapsed = Double.greatestFiniteMagnitude
        for type in eventTypes {
            let elapsed = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
            if elapsed >= 0 && elapsed < minElapsed {
                minElapsed = elapsed
            }
        }
        return minElapsed == .greatestFiniteMagnitude ? 0 : minElapsed
    }

    public func syncIdleInactivityMonitoring() {
        idleInactivityTimer?.invalidate()
        idleInactivityTimer = nil
        guard settings.idleAutoArmEnabled else {
            idleEvaluator.reset()
            return
        }
        idleInactivityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollIdleInactivity()
            }
        }
    }

    /// Resets the open-lid idle baseline whenever the MacBook lid closes/opens or macOS sleeps/wakes,
    /// ensuring wall-clock time spent asleep or closed never counts toward open-lid idle auto-arming.
    public func recordIdleSleepWakeTransition(at timestamp: TimeInterval? = nil) {
        lastSleepWakeOrLidTransitionTime = timestamp ?? clock()
        idleEvaluator.reset()
    }

    public func pollIdleInactivity(idleSeconds: Double? = nil) {
        let rawIdle = idleSeconds ?? hidIdleSecondsProvider()
        let currentIdle: Double
        if let transitionTime = lastSleepWakeOrLidTransitionTime {
            let elapsedSinceTransition = max(0, clock() - transitionTime)
            currentIdle = min(rawIdle, elapsedSinceTransition)
        } else {
            currentIdle = rawIdle
        }
        let shouldArm = idleEvaluator.evaluate(
            idleSeconds: currentIdle,
            thresholdMinutes: settings.idleAutoArmMinutes,
            state: state,
            featureEnabled: settings.idleAutoArmEnabled,
            isLidClosed: powerMonitor.isLidClosed,
            isSystemSleeping: lockMonitor.isSleeping
        )
        if shouldArm {
            logEvent(
                "Idle Auto-Arm",
                detail: "No keyboard or mouse activity for \(settings.idleAutoArmMinutes)m. Auto-arming."
            )
            startArming()
        }
    }

    public func syncTrustedNetworkMonitoring() {
        if settings.trustedNetworkAutoArmEnabled {
            if !trustedNetworkMonitor.isMonitoring {
                trustedNetworkMonitor.startMonitoring()
            } else if let snapshot = trustedNetworkMonitor.latestSnapshot {
                handleTrustedNetworkSnapshot(snapshot)
            }
        } else {
            trustedNetworkMonitor.stopMonitoring()
            lastRecordedTrustedMatchEntryID = nil
            if trustedNetworkPosture != .disabled || settings.trustedNetworkBaselineGazeSensitivity != nil {
                let fallbackSnapshot = trustedNetworkMonitor.latestSnapshot ?? NetworkIdentitySnapshot(
                    isSatisfied: false,
                    primaryInterface: .none,
                    interfaceName: nil,
                    locationPermission: trustedNetworkMonitor.locationPermission,
                    capturedAt: clock()
                )
                handleTrustedNetworkSnapshot(fallbackSnapshot)
            }
        }
    }

    public func handleTrustedNetworkSnapshot(
        _ snapshot: NetworkIdentitySnapshot,
        at timestamp: TimeInterval? = nil
    ) {
        let config = TrustedNetworkPolicyConfiguration(
            isEnabled: settings.trustedNetworkAutoArmEnabled,
            policyMode: settings.trustedNetworkPolicyMode,
            armOnOfflineDisconnect: settings.trustedNetworkArmOnOfflineDisconnect
        )

        let output = trustedNetworkEvaluator.evaluate(
            snapshot: snapshot,
            enrolledNetworks: settings.trustedNetworks,
            configuration: config,
            securityState: state,
            currentGazeSensitivity: settings.gazeSensitivity,
            savedBaselineSensitivity: settings.trustedNetworkBaselineGazeSensitivity,
            at: timestamp ?? clock()
        )

        trustedNetworkPosture = output.posture
        trustedNetworkMonitor.applyPosture(output.posture)

        if let baseline = output.newBaselineSensitivityToSave {
            settings.trustedNetworkBaselineGazeSensitivity = baseline
        }
        if let nextSensitivity = output.updatedGazeSensitivity {
            settings.gazeSensitivity = nextSensitivity
        }
        if output.shouldClearSavedBaseline {
            settings.trustedNetworkBaselineGazeSensitivity = nil
        }

        if case .trusted(let entryID, _, _) = output.posture {
            if lastRecordedTrustedMatchEntryID != entryID {
                lastRecordedTrustedMatchEntryID = entryID
                if let index = settings.trustedNetworks.firstIndex(where: { $0.id == entryID }) {
                    settings.trustedNetworks[index].lastMatchedAt = Date()
                }
            }
        } else {
            lastRecordedTrustedMatchEntryID = nil
        }

        trustedNetworkMonitor.scheduleDebounceReevaluation(after: output.pendingReevaluationDelay)

        if let event = output.event {
            switch event {
            case .enteredTrustedNetwork(_, let displayName, _, let restoredSensitivity):
                let suffix = restoredSensitivity.map { " Restored gaze sensitivity to \($0.title)." } ?? ""
                logEvent("Trusted Wi-Fi Connected", detail: "On trusted Wi-Fi (\(displayName)).\(suffix)")
            case .leftTrustedForUntrusted(let displayLabel, let source, let armed, let escalated):
                var actions: [String] = []
                if escalated { actions.append("Sensitivity set to Strict.") }
                if armed { actions.append("Auto-arming Pupil.") }
                let actionSummary = actions.isEmpty ? "" : " " + actions.joined(separator: " ")
                logEvent(
                    "Untrusted Wi-Fi Policy",
                    detail: "Connected to untrusted Wi-Fi via \(source.displayTitle) (\(displayLabel)).\(actionSummary)"
                )
            case .leftTrustedToOffline(let armed):
                if armed {
                    logEvent("Trusted Wi-Fi Left", detail: "Disconnected from trusted Wi-Fi. Auto-arming Pupil.")
                }
            case .enteredUnavailableIdentity(let permission):
                logEvent(
                    "Wi-Fi Identity Unavailable",
                    detail: "Cannot verify trusted Wi-Fi (\(permission.rawValue)). Failing closed."
                )
            }
        }

        trustedNetworkMonitor.onEvaluationResult?(output)

        if output.shouldAutoArm && state == .disarmed {
            startArming()
            if settings.relayEnabled {
                alertNotifier.send(AlertMessage(
                    title: "Pupil Network Boundary Auto-Arm",
                    body: "Left trusted Wi-Fi network. Auto-arming protection.",
                    severity: "normal",
                    tag: "pupil-network"
                ))
            }
        }
    }

    public func updatePin(newPin: String) throws {
        try KeychainManager.enrollPin(newPin)
        hasEnrolledPin = KeychainManager.hasEnrolledPin
        resetPinLockout()
        logEvent("PIN Updated", detail: "Security PIN updated in macOS Keychain.")
    }

    public func recoverPinWithDeviceOwnerAuth(newPin: String? = nil) async -> Bool {
        let verified = await KeychainManager.authenticateDeviceOwner(
            reason: "Verify Mac login password or Touch ID to unlock or reset your Pupil PIN"
        )
        guard verified else { return false }
        resetPinLockout()
        if let newPin, KeychainManager.isValidPinFormat(newPin) {
            try? KeychainManager.enrollPin(newPin)
            hasEnrolledPin = KeychainManager.hasEnrolledPin
            logEvent("PIN Reset via Mac Password", detail: "Security PIN reset after macOS owner verification.")
        }
        if state != .disarmed || isInteractiveUnlockRequested {
            trustedNetworkEvaluator.suppressCurrentUntrustedSession()
            performValidatedDisarm(method: "Mac Password")
        }
        return true
    }

    private func performValidatedDisarm(method: String) {
        idleEvaluator.suppressCurrentStreak()
        let wasAlarm = (state == .alarm)
        resetPinLockout()
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
        webPushManager.stopRemoteCommandListener()
        gazeDwellProgress = 0
        networkSentinel.stopMonitoring()
        powerMonitor.resetChargerFlapState()
        gazeAggregator.reset()
        motionAggregator.reset()
        tamperScorer.reset()
        armedDisplayTopologyEvaluator.reset()
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

        if settings.trustedNetworkAutoArmEnabled,
           let snapshot = trustedNetworkMonitor.latestSnapshot {
            handleTrustedNetworkSnapshot(snapshot)
        }

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

    public func requestInteractiveUnlock() {
        guard state == .armed || state == .tamperPending || state == .alarm else { return }
        if state == .armed && !isInteractiveUnlockRequested {
            isInteractiveUnlockRequested = true
            onStateChanged?(state)
            onNotchUpdateNeeded?()
            NotificationCenter.default.post(name: .screenShieldSync, object: nil)
        }
        NotificationCenter.default.post(name: .screenShieldOpenPrompt, object: nil)
        NotificationCenter.default.post(name: .screenShieldFocusPrimary, object: nil)
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
        dispatchMobileAlertWithOneShotSnapshotFallback(
            title: "Pupil Tamper Countdown (\(grace)s)",
            body: "\(source.rawValue) detected on your MacBook. Siren sounds in \(grace)s unless disarmed.",
            severity: "high",
            tag: "pupil-tamper"
        )

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

    public func latchArmedDisplayTopologyBaseline(_ snapshot: DisplayTopologySnapshot) {
        armedDisplayTopologyEvaluator.latchBaseline(snapshot)
    }

    public func handleDisplayTopologyChange(_ snapshot: DisplayTopologySnapshot) {
        guard state != .disarmed else { return }
        let event = armedDisplayTopologyEvaluator.evaluate(snapshot)
        if case .externalDisplayDisconnected(let removedCount) = event {
            handleExternalDisplayUnplugged(removedCount: removedCount)
        }
    }

    public func handleExternalDisplayUnplugged(removedCount: Int = 1) {
        guard state != .disarmed else { return }
        guard settings.displayUnplugTriggerEnabled && settings.hardwareTriggers.contains(.peripheralDisconnect) else {
            logEvent(
                "External Display Unplugged (Ignored)",
                detail: "\(removedCount) external display(s) disconnected while armed (trigger disabled)."
            )
            return
        }
        logEvent(
            "External Display Unplugged",
            detail: "\(removedCount) external display(s) disconnected while armed."
        )
        triggerTamper(source: .peripheralDisconnected, immediateAlarm: false)
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
        SirenSynthesizer.shared.start(
            baseFrequencyHz: Double(settings.sirenFrequencyHz),
            overrideSpeakers: settings.sirenSpeakerOverrideEnabled,
            targetVolume: Float(settings.sirenOverrideVolume)
        )

        logEvent(
            "ALARM LATCHED",
            detail: "Triggered by \(source.rawValue). Audible siren active until PIN or Touch ID disarm.",
            simulated: simulated
        )
        onStateChanged?(state)
        onNotchUpdateNeeded?()

        dispatchMobileAlertWithOneShotSnapshotFallback(
            title: "Pupil Siren Alarm Active",
            body: "\(source.rawValue) — Audible siren and sleep lock engaged on your MacBook!",
            severity: "critical",
            tag: "pupil-alarm"
        )
    }

    private func handleRemoteSnapshotRequest() {
        guard state == .armed || state == .tamperPending || state == .alarm else { return }
        logEvent("Remote Snapshot Requested", detail: "Capturing verification frame for mobile companion.")

        Task { [weak self] in
            guard let self else { return }
            guard let frame = await self.cameraManager.captureOneShotFrame(
                preferredDeviceID: self.settings.preferredCameraID,
                timeoutSeconds: 2.0
            ) else {
                return
            }
            self.syncCameraLifecycle()
            guard self.state == .armed || self.state == .tamperPending || self.state == .alarm,
                  let snapshotBase64 = self.encodeVerificationSnapshotBase64(frame) else {
                return
            }
            self.alertNotifier.send(AlertMessage(
                title: "Pupil Snapshot",
                body: "Requested verification frame (\(self.state.label)).",
                severity: "normal",
                tag: "pupil-snapshot",
                snapshotBase64: snapshotBase64
            ))
        }
    }

    private func dispatchMobileAlertWithOneShotSnapshotFallback(
        title: String,
        body: String,
        severity: String,
        tag: String
    ) {
        let immediateSnapshot = captureVerificationSnapshotBase64()
        alertNotifier.send(AlertMessage(
            title: title,
            body: body,
            severity: severity,
            tag: tag,
            snapshotBase64: immediateSnapshot
        ))

        guard immediateSnapshot == nil,
              settings.relayEnabled,
              settings.pairedPhoneSubscription != nil else {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            guard let frame = await self.cameraManager.captureOneShotFrame(
                preferredDeviceID: self.settings.preferredCameraID,
                timeoutSeconds: 2.0
            ) else {
                return
            }
            self.syncCameraLifecycle()
            guard self.state == .tamperPending || self.state == .alarm,
                  let fallbackSnapshot = self.encodeVerificationSnapshotBase64(frame) else {
                return
            }
            await self.webPushManager.postAlertSnapshotEnvelope(
                title: title,
                body: body,
                severity: severity,
                tag: tag,
                snapshotBase64: fallbackSnapshot
            )
        }
    }

    private func captureVerificationSnapshotBase64() -> String? {
        guard let cgImage = cameraManager.lastFrameImage else { return nil }
        return encodeVerificationSnapshotBase64(cgImage)
    }

    private func encodeVerificationSnapshotBase64(_ cgImage: CGImage) -> String? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let maxWidth = 480
        let targetWidth: Int
        let targetHeight: Int
        if width > maxWidth {
            targetWidth = maxWidth
            targetHeight = max(1, Int((Double(height) * Double(maxWidth) / Double(width)).rounded()))
        } else {
            targetWidth = width
            targetHeight = height
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let scaledImage = context.makeImage() else { return nil }

        let bitmap = NSBitmapImageRep(cgImage: scaledImage)
        guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) else {
            return nil
        }
        return jpegData.base64EncodedString()
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
        syncAdaptiveVisionFrameRate()

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
        guard settings.isSpatialMotionEnabled || settings.surroundingsWatchEnabled || isCameraPreviewRequested || isLiveCalibrating else { return }

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
            syncAdaptiveVisionFrameRate()
            return
        }

        if state == .disarmed && isCameraPreviewRequested {
            guard settings.isSpatialMotionEnabled else {
                hasMotionAnchor = false
                latestMotionDisplacementScore = 0
                syncAdaptiveVisionFrameRate()
                return
            }
            hasMotionAnchor = sample.isAnchorFrame || hasMotionAnchor
            let translationRatio = sample.isRegistrationReliable
                ? sample.translationMagnitude / max(0.001, settings.spatialMotionSensitivity.translationDeadband)
                : 0
            latestMotionDisplacementScore = min(1.0, translationRatio)
            syncAdaptiveVisionFrameRate()

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

        if settings.surroundingsWatchEnabled && sample.surroundingsActivityDetected {
            let now = clock()
            if now - lastSurroundingsAlertTime >= 10.0 {
                lastSurroundingsAlertTime = now
                logEvent(
                    "Surroundings Activity",
                    detail: "Peripheral movement detected around your Mac while armed."
                )
                alertNotifier.send(AlertMessage(
                    title: "Surroundings Activity",
                    body: "Peripheral movement detected around your Mac while armed.",
                    severity: "normal",
                    tag: "pupil-surroundings",
                    snapshotBase64: captureVerificationSnapshotBase64()
                ))
                onNotchUpdateNeeded?()
            }
        }

        guard settings.isSpatialMotionEnabled else { return }

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
        syncAdaptiveVisionFrameRate()

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
        if settings.hapticFeedbackEnabled && !Self.isRunningUnderTests {
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
        cameraManager.motionDetector.surroundingsWatchEnabled = settings.surroundingsWatchEnabled
        if !settings.gazeDetectionEnabled && isGazeWarningActive {
            dismissGazeWarning()
        }
        let cameraNeededForMonitoring = isMonitoring && (settings.gazeDetectionEnabled || settings.isSpatialMotionEnabled || settings.surroundingsWatchEnabled)
        let shouldRunCamera = isCameraPreviewRequested || cameraNeededForMonitoring
        if shouldRunCamera {
            cameraManager.startCapture(preferredDeviceID: settings.preferredCameraID)
        } else {
            cameraManager.stopCapture()
        }
        syncAdaptiveVisionFrameRate()
    }

    public func syncAdaptiveVisionFrameRate() {
        guard settings.adaptiveFrameRateEnabled else {
            cameraManager.updateAnalysisRate(fps: AdaptiveVisionGovernor.fullRateFPS)
            return
        }
        let activitySuspected = activeFaceCount > 0
            || gazeDwellProgress > 0
            || isGazeWarningActive
            || latestMotionDisplacementScore >= 0.35
            || state == .arming
            || state == .tamperPending
            || state == .alarm
            || isCameraPreviewRequested
            || isLiveCalibrating
        let targetFPS = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: powerMonitor.isOnACPower,
            batteryPercent: powerMonitor.batteryPercentage,
            thermalState: thermalStateProvider(),
            isActivitySuspected: activitySuspected
        )
        cameraManager.updateAnalysisRate(fps: targetFPS)
    }

    public func clearEventLog() {
        events.removeAll()
        try? journalStore.clear()
        canPersistJournal = true
    }

    public func exportIncidentReportMarkdown() -> String {
        TamperJournalStore.exportMarkdownReport(records: events)
    }

    @MainActor
    public func presentExportIncidentLogPanel() {
        let markdown = exportIncidentReportMarkdown()
        let panel = NSSavePanel()
        panel.title = "Export Security Activity Log"
        panel.nameFieldStringValue = "Pupil-Incident-Report.md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? Data(markdown.utf8).write(to: url, options: [.atomic])
        }
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
                self.syncAdaptiveVisionFrameRate()
            case .lidClosed:
                self.recordIdleSleepWakeTransition()
                if self.settings.hardwareTriggers.contains(.lidClose) {
                    // Physical clamshell closed: trigger immediate siren before macOS cuts audio
                    self.triggerTamper(source: .lidClosed, immediateAlarm: true)
                }
            case .systemWillSleep:
                self.recordIdleSleepWakeTransition()
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
                self.recordIdleSleepWakeTransition()
                if self.state == .armed && !self.powerMonitor.isLidClosed {
                    self.triggerTamper(source: .wakeWhileArmed, immediateAlarm: false)
                }
            case .chargerPluggedIn:
                if self.state == .tamperPending,
                   (self.activeTamperSource == .chargerUnplugged || self.activeTamperSource == .cameraMotionDetected),
                   self.settings.revertTamperOnPowerRestored {
                    if self.powerMonitor.isChargerFlapping {
                        self.logEvent(
                            "Charger Flap Ignored",
                            detail: "Rapid power cycling detected (≥3 transitions in 6s). Grace countdown remains active."
                        )
                    } else {
                        self.revertTamperToArmed(reason: "Power adapter reconnected.")
                    }
                }
                self.syncAdaptiveVisionFrameRate()
            case .lidOpened:
                self.recordIdleSleepWakeTransition()
                break
            case .peripheralDisconnected:
                if self.settings.hardwareTriggers.contains(.peripheralDisconnect) {
                    self.triggerTamper(source: .peripheralDisconnected, immediateAlarm: false)
                }
            case .externalDisplayUnplugged(let removedCount):
                self.handleExternalDisplayUnplugged(removedCount: removedCount)
            }
        }

        lockMonitor.onLockEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .screenLocked:
                if self.state == .disarmed {
                    if self.settings.autoArmOnScreenLock {
                        self.startArming()
                    }
                } else if self.settings.hardwareTriggers.contains(.screenLock) {
                    self.triggerTamper(source: .screenLocked, immediateAlarm: false)
                }
            case .willSleep:
                self.recordIdleSleepWakeTransition()
                if PowerAndLidMonitor.readClamshellClosedState() {
                    if self.settings.hardwareTriggers.contains(.lidClose) {
                        self.triggerTamper(source: .lidClosed, immediateAlarm: true)
                    }
                }
            case .wake:
                self.recordIdleSleepWakeTransition()
                if self.isMonitoring && self.state == .alarm {
                    SirenSynthesizer.shared.start(
                        baseFrequencyHz: Double(self.settings.sirenFrequencyHz),
                        overrideSpeakers: self.settings.sirenSpeakerOverrideEnabled,
                        targetVolume: Float(self.settings.sirenOverrideVolume)
                    )
                }
            case .screenUnlocked:
                self.recordIdleSleepWakeTransition()
                if self.settings.autoArmOnScreenLock {
                    if self.state == .arming {
                        self.cancelArmingDuringExitDelay()
                    } else if self.state == .armed || self.state == .tamperPending || self.state == .alarm {
                        self.trustedNetworkEvaluator.suppressCurrentUntrustedSession()
                        self.performValidatedDisarm(method: "macOS Screen Unlock")
                    }
                }
            }
        }

        cameraManager.onGazeSample = { [weak self] sample in
            self?.ingestGazeSample(sample)
        }

        cameraManager.onMotionSample = { [weak self] sample in
            self?.ingestMotionSample(sample)
        }

        bluetoothMonitor.onWalkAway = { [weak self] in
            guard let self else { return }
            guard self.settings.bluetoothProximityEnabled,
                  !self.settings.trustedBluetoothDeviceUUID.isEmpty,
                  self.state == .disarmed else { return }
            let deviceName = self.settings.trustedBluetoothDeviceName.isEmpty ? "Trusted device" : self.settings.trustedBluetoothDeviceName
            self.logEvent("Bluetooth Walk-Away", detail: "\(deviceName) moved out of range. Auto-arming.")
            self.startArming()
        }

        bluetoothMonitor.onReturn = { [weak self] in
            guard let self else { return }
            guard self.settings.bluetoothProximityEnabled,
                  self.settings.bluetoothAutoDisarmEnabled,
                  !self.settings.trustedBluetoothDeviceUUID.isEmpty,
                  self.state == .armed else { return }
            self.disarmFromTrustedProximity()
        }

        networkSentinel.onTransition = { [weak self] transition in
            guard let self else { return }
            guard self.isMonitoring, self.settings.networkDropMonitorEnabled else { return }
            switch transition {
            case .connectivityLost(let previous):
                self.logEvent(
                    "Network Drop Detected",
                    detail: "\(previous.rawValue) connection lost while \(self.state.label)."
                )
                self.alertNotifier.send(AlertMessage(
                    title: "Pupil Network Drop Advisory",
                    body: "\(previous.rawValue) connection dropped while MacBook is \(self.state.label).",
                    severity: "high",
                    tag: "pupil-network"
                ))
                self.alertNotifier.flushPendingNow()
            case .interfaceChanged(let from, let to):
                self.logEvent(
                    "Network Interface Changed",
                    detail: "Primary interface switched from \(from.rawValue) to \(to.rawValue) while \(self.state.label)."
                )
                self.alertNotifier.send(AlertMessage(
                    title: "Pupil Network Change Advisory",
                    body: "Network switched from \(from.rawValue) to \(to.rawValue) while \(self.state.label).",
                    severity: "normal",
                    tag: "pupil-network"
                ))
                self.alertNotifier.flushPendingNow()
            case .connectivityRestored(let current):
                self.logEvent(
                    "Network Restored",
                    detail: "\(current.rawValue) connection restored while \(self.state.label). Flushing queued alerts."
                )
                self.alertNotifier.flushPendingNow()
            }
        }

        trustedNetworkMonitor.onSnapshotUpdated = { [weak self] snapshot in
            self?.handleTrustedNetworkSnapshot(snapshot)
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

    private func handleJournalLoadFailure(_ error: Error, journalStore: TamperJournalStore) {
        let fileURL = journalStore.fileURL
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        var detail = "Existing tamper journal failed validation (\(error.localizedDescription))."

        if fileExists {
            let timestamp = Int(Date().timeIntervalSince1970)
            let quarantineName = "\(fileURL.lastPathComponent).quarantined-\(timestamp)-\(UUID().uuidString.prefix(8))"
            let quarantineURL = fileURL.deletingLastPathComponent().appendingPathComponent(quarantineName)
            do {
                try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
                detail += " Original file quarantined as \(quarantineName)."
            } catch let moveError {
                canPersistJournal = false
                detail += " Failed to quarantine original file (\(moveError.localizedDescription)); journal writes paused to preserve evidence."
            }
        }

        NSLog("[Pupil] Tamper journal load failure: %@", detail)
        let record = SecurityEventRecord(
            title: "Journal Validation Failed",
            detail: detail,
            stateAtEvent: state
        )
        events.insert(record, at: 0)
        if canPersistJournal {
            try? journalStore.saveRecords(events)
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
        if events.count > TamperJournalStore.maxRecords {
            events.removeLast(events.count - TamperJournalStore.maxRecords)
        }
        if canPersistJournal {
            try? journalStore.saveRecords(events)
        }
    }
}
