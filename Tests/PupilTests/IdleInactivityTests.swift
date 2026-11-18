//
//  IdleInactivityTests.swift
//  Pupil
//
//  Tests covering pure IdleInactivityEvaluator logic, streak suppression,
//  PupilSettings persistence and slider stepping, and SecurityCoordinator HID idle polling.
//

import Foundation
import Testing
@testable import Pupil

@Suite("Idle Inactivity Auto-Arm Sentinel Tests")
struct IdleInactivityTests {

    // MARK: - 1. Pure Evaluator Threshold & Feature Gate Tests

    @Test("IdleInactivityEvaluator returns false when feature is disabled")
    func featureDisabledReturnsFalse() {
        var evaluator = IdleInactivityEvaluator()

        let shouldArm = evaluator.evaluate(
            idleSeconds: 3600.0,
            thresholdMinutes: 10,
            state: .disarmed,
            featureEnabled: false
        )

        #expect(shouldArm == false)
        #expect(evaluator.isSuppressedForCurrentStreak == false)
    }

    @Test("IdleInactivityEvaluator threshold comparisons")
    func thresholdBoundaryEvaluation() {
        var evaluator = IdleInactivityEvaluator()

        // 10 minutes = 600.0 seconds
        // Just below threshold
        #expect(
            evaluator.evaluate(
                idleSeconds: 599.9,
                thresholdMinutes: 10,
                state: .disarmed,
                featureEnabled: true
            ) == false
        )
        #expect(evaluator.isSuppressedForCurrentStreak == false)

        // Exactly at threshold
        #expect(
            evaluator.evaluate(
                idleSeconds: 600.0,
                thresholdMinutes: 10,
                state: .disarmed,
                featureEnabled: true
            ) == true
        )
        #expect(evaluator.isSuppressedForCurrentStreak == true)

        // Evaluator handles thresholdMinutes < 1 (clamped to at least 1 minute = 60s)
        var clampedEvaluator = IdleInactivityEvaluator()
        #expect(
            clampedEvaluator.evaluate(
                idleSeconds: 59.0,
                thresholdMinutes: 0,
                state: .disarmed,
                featureEnabled: true
            ) == false
        )
        #expect(
            clampedEvaluator.evaluate(
                idleSeconds: 60.0,
                thresholdMinutes: 0,
                state: .disarmed,
                featureEnabled: true
            ) == true
        )
    }

    @Test("IdleInactivityEvaluator ignores non-disarmed states")
    func nonDisarmedStatesDoNotArm() {
        let nonDisarmedStates: [SecurityState] = [.arming, .armed, .tamperPending, .alarm]

        for state in nonDisarmedStates {
            var evaluator = IdleInactivityEvaluator()
            let shouldArm = evaluator.evaluate(
                idleSeconds: 900.0,
                thresholdMinutes: 10,
                state: state,
                featureEnabled: true
            )
            #expect(shouldArm == false)
            #expect(evaluator.isSuppressedForCurrentStreak == false)
        }
    }

    // MARK: - 2. Streak Suppression Tests

    @Test("Streak suppression prevents repeated arming until fresh user activity")
    func streakSuppressionLifecycle() {
        var evaluator = IdleInactivityEvaluator()

        // Initial trigger at threshold
        #expect(
            evaluator.evaluate(
                idleSeconds: 600.0,
                thresholdMinutes: 10,
                state: .disarmed,
                featureEnabled: true
            ) == true
        )
        #expect(evaluator.isSuppressedForCurrentStreak == true)

        // Subsequent poll during same idle streak (e.g. user cancelled exit delay, state back to disarmed)
        #expect(
            evaluator.evaluate(
                idleSeconds: 605.0,
                thresholdMinutes: 10,
                state: .disarmed,
                featureEnabled: true
            ) == false
        )
        #expect(
            evaluator.evaluate(
                idleSeconds: 1200.0,
                thresholdMinutes: 10,
                state: .disarmed,
                featureEnabled: true
            ) == false
        )

        // User moves mouse: idle time drops to 5.0s (< 600s).
        // Evaluator returns false AND clears suppression.
        #expect(
            evaluator.evaluate(
                idleSeconds: 5.0,
                thresholdMinutes: 10,
                state: .disarmed,
                featureEnabled: true
            ) == false
        )
        #expect(evaluator.isSuppressedForCurrentStreak == false)

        // Time elapses again to 600s -> arms again
        #expect(
            evaluator.evaluate(
                idleSeconds: 600.0,
                thresholdMinutes: 10,
                state: .disarmed,
                featureEnabled: true
            ) == true
        )
        #expect(evaluator.isSuppressedForCurrentStreak == true)
    }

    @Test("Explicit suppressCurrentStreak and reset")
    func explicitSuppressionAndReset() {
        var evaluator = IdleInactivityEvaluator()
        #expect(evaluator.isSuppressedForCurrentStreak == false)

        evaluator.suppressCurrentStreak()
        #expect(evaluator.isSuppressedForCurrentStreak == true)

        // With suppression active, threshold reached returns false
        #expect(
            evaluator.evaluate(
                idleSeconds: 700.0,
                thresholdMinutes: 10,
                state: .disarmed,
                featureEnabled: true
            ) == false
        )

        // Reset clears suppression
        evaluator.reset()
        #expect(evaluator.isSuppressedForCurrentStreak == false)

        #expect(
            evaluator.evaluate(
                idleSeconds: 700.0,
                thresholdMinutes: 10,
                state: .disarmed,
                featureEnabled: true
            ) == true
        )
    }

    // MARK: - 3. PupilSettings Persistence and Slider Stops

    @MainActor
    @Test("PupilSettings defaults, stops, and slider index mapping")
    func settingsDefaultsAndSliderIndex() {
        let suiteName = "com.pupil.tests.idle.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: defaults)

        // Verify defaults
        #expect(settings.idleAutoArmEnabled == false)
        #expect(settings.idleAutoArmMinutes == 10)
        #expect(PupilSettings.idleAutoArmStops == [5, 10, 15, 30])
        #expect(settings.idleAutoArmSliderIndex == 1.0) // Index of 10 in [5, 10, 15, 30]

        // Slider index 0 -> 5 minutes
        settings.idleAutoArmSliderIndex = 0.0
        #expect(settings.idleAutoArmMinutes == 5)
        #expect(settings.idleAutoArmSliderIndex == 0.0)

        // Slider index 2 -> 15 minutes
        settings.idleAutoArmSliderIndex = 2.0
        #expect(settings.idleAutoArmMinutes == 15)
        #expect(settings.idleAutoArmSliderIndex == 2.0)

        // Slider index 3 -> 30 minutes
        settings.idleAutoArmSliderIndex = 3.0
        #expect(settings.idleAutoArmMinutes == 30)
        #expect(settings.idleAutoArmSliderIndex == 3.0)

        // Clamping out-of-bounds indices
        settings.idleAutoArmSliderIndex = -10.0
        #expect(settings.idleAutoArmMinutes == 5)
        #expect(settings.idleAutoArmSliderIndex == 0.0)

        settings.idleAutoArmSliderIndex = 999.0
        #expect(settings.idleAutoArmMinutes == 30)
        #expect(settings.idleAutoArmSliderIndex == 3.0)

        // Setting idleAutoArmMinutes directly updates slider index
        settings.idleAutoArmMinutes = 10
        #expect(settings.idleAutoArmSliderIndex == 1.0)

        // Enable auto-arm and verify persistence in new PupilSettings instance
        settings.idleAutoArmEnabled = true
        settings.idleAutoArmMinutes = 15

        let reloadedSettings = PupilSettings(defaults: defaults)
        #expect(reloadedSettings.idleAutoArmEnabled == true)
        #expect(reloadedSettings.idleAutoArmMinutes == 15)
        #expect(reloadedSettings.idleAutoArmSliderIndex == 2.0)

        // Invalid stored minute falls back to default 10
        defaults.set(42, forKey: "pupil.idleAutoArmMinutes")
        let fallbackSettings = PupilSettings(defaults: defaults)
        #expect(fallbackSettings.idleAutoArmMinutes == 10)
    }

    // MARK: - 4. SecurityCoordinator Integration Tests

    @MainActor
    @Test("SecurityCoordinator HID idle polling arms system and suppresses re-arm until input")
    func coordinatorIdleAutoArmIntegration() {
        let suiteName = "com.pupil.tests.idle.coordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: defaults)
        settings.exitDelaySeconds = 10
        settings.idleAutoArmEnabled = true
        settings.idleAutoArmMinutes = 5 // 300 seconds

        let powerMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100, isLidClosed: false)
        let coordinator = SecurityCoordinator(settings: settings, powerMonitor: powerMonitor)
        defer {
            settings.idleAutoArmEnabled = false
            coordinator.syncIdleInactivityMonitoring()
        }

        #expect(coordinator.state == .disarmed)

        var simulatedIdleSeconds: Double = 120.0
        coordinator.hidIdleSecondsProvider = { simulatedIdleSeconds }

        // 1. Below threshold: does not arm
        coordinator.pollIdleInactivity()
        #expect(coordinator.state == .disarmed)

        // 2. Cross threshold (305s >= 300s): starts arming (exit delay)
        simulatedIdleSeconds = 305.0
        coordinator.pollIdleInactivity()
        #expect(coordinator.state == .arming)

        // 3. User cancels during exit delay: returns to disarmed
        coordinator.cancelArmingDuringExitDelay()
        #expect(coordinator.state == .disarmed)
        #expect(coordinator.idleEvaluator.isSuppressedForCurrentStreak == true)

        // 4. Continued idle streak without new input: does NOT re-arm
        simulatedIdleSeconds = 310.0
        coordinator.pollIdleInactivity()
        #expect(coordinator.state == .disarmed)

        simulatedIdleSeconds = 400.0
        coordinator.pollIdleInactivity()
        #expect(coordinator.state == .disarmed)

        // 5. User types or moves mouse: idle time resets below threshold
        simulatedIdleSeconds = 2.0
        coordinator.pollIdleInactivity()
        #expect(coordinator.state == .disarmed)
        #expect(coordinator.idleEvaluator.isSuppressedForCurrentStreak == false)

        // 6. User walks away again, reaching threshold -> arms again
        simulatedIdleSeconds = 300.0
        coordinator.pollIdleInactivity()
        #expect(coordinator.state == .arming)
    }

    @MainActor
    @Test("SecurityCoordinator manual disarm suppresses current idle streak")
    func coordinatorManualDisarmSuppressesStreak() {
        let suiteName = "com.pupil.tests.idle.manual.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: defaults)
        settings.exitDelaySeconds = 0 // Immediate arming
        settings.idleAutoArmEnabled = true
        settings.idleAutoArmMinutes = 5 // 300s

        let powerMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100, isLidClosed: false)
        let coordinator = SecurityCoordinator(settings: settings, powerMonitor: powerMonitor)
        defer {
            settings.idleAutoArmEnabled = false
            coordinator.syncIdleInactivityMonitoring()
        }

        var simulatedIdleSeconds: Double = 310.0
        coordinator.hidIdleSecondsProvider = { simulatedIdleSeconds }

        // Arms immediately to .armed
        coordinator.pollIdleInactivity()
        #expect(coordinator.state == .armed)

        // Disarm remotely or via phone
        _ = coordinator.disarmViaRemotePhone()
        #expect(coordinator.state == .disarmed)
        #expect(coordinator.idleEvaluator.isSuppressedForCurrentStreak == true)

        // While still idle, poll should not re-arm
        simulatedIdleSeconds = 320.0
        coordinator.pollIdleInactivity()
        #expect(coordinator.state == .disarmed)
    }

    @MainActor
    @Test("SecurityCoordinator does not poll or arm when idleAutoArmEnabled is false")
    func coordinatorDisabledDoesNothing() {
        let suiteName = "com.pupil.tests.idle.disabled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: defaults)
        settings.idleAutoArmEnabled = false
        settings.idleAutoArmMinutes = 5

        let powerMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100, isLidClosed: false)
        let coordinator = SecurityCoordinator(settings: settings, powerMonitor: powerMonitor)
        defer {
            coordinator.syncIdleInactivityMonitoring()
        }

        coordinator.hidIdleSecondsProvider = { 9999.0 }
        coordinator.pollIdleInactivity()
        #expect(coordinator.state == .disarmed)
        #expect(coordinator.idleEvaluator.isSuppressedForCurrentStreak == false)
    }

    @Test("System HID idle reader returns non-negative time without crashing")
    func systemHIDIdleReaderSanity() {
        let idle = SecurityCoordinator.readSystemHIDIdleSeconds()
        #expect(idle >= 0.0)
        #expect(idle.isFinite)
    }

    @MainActor
    @Test("Closing laptop lid or dark-wake sleep prevents idle auto-arm and resets idle baseline upon reopening")
    func closedLidAndWakeResetIdleBaseline() {
        let suiteName = "com.pupil.tests.idle.lidwake.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: defaults)
        settings.exitDelaySeconds = 0
        settings.autoArmOnScreenLock = false
        settings.idleAutoArmEnabled = true
        settings.idleAutoArmMinutes = 15 // 900s

        let powerMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100, isLidClosed: true)
        let coordinator = SecurityCoordinator(settings: settings, powerMonitor: powerMonitor)
        defer {
            settings.idleAutoArmEnabled = false
            coordinator.syncIdleInactivityMonitoring()
        }

        var now: TimeInterval = 1_000_000
        coordinator.clock = { now }
        // Simulate 2 hours (7200s) of macOS HID idle time accumulated while the laptop was closed overnight
        coordinator.hidIdleSecondsProvider = { 7200.0 }

        // 1. Dark wake while lid is closed: must NOT auto-arm
        coordinator.pollIdleInactivity()
        #expect(coordinator.state == .disarmed)

        // 2. User reopens lid at t = 1_000_000: transition resets open-lid idle baseline
        let awakePowerMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100, isLidClosed: false)
        let awakeCoordinator = SecurityCoordinator(settings: settings, powerMonitor: awakePowerMonitor)
        defer { awakeCoordinator.syncIdleInactivityMonitoring() }
        awakeCoordinator.clock = { now }
        awakeCoordinator.hidIdleSecondsProvider = { 7200.0 }
        awakeCoordinator.recordIdleSleepWakeTransition(at: now)

        // 3 seconds after reopening lid, raw HID idle is still 7200s (before user touches keyboard),
        // but elapsed time since wake is only 3s -> must NOT auto-arm!
        now += 3.0
        awakeCoordinator.pollIdleInactivity()
        #expect(awakeCoordinator.state == .disarmed)

        // 16 minutes (960s) of genuinely leaving the laptop open & untouched after waking -> auto-arms
        now += 960.0
        awakeCoordinator.pollIdleInactivity()
        #expect(awakeCoordinator.state == .armed)
    }

    @MainActor
    @Test("Waking while armed starts grace countdown rather than immediate siren and ignores closed-lid dark wakes")
    func wakeWhileArmedGrantsGraceCountdown() {
        let suiteName = "com.pupil.tests.idle.wakegrace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: defaults)
        settings.exitDelaySeconds = 0
        settings.gracePeriodSeconds = 15

        let closedMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100, isLidClosed: true)
        let closedCoordinator = SecurityCoordinator(settings: settings, powerMonitor: closedMonitor)
        closedCoordinator.startArming(immediate: true)
        #expect(closedCoordinator.state == .armed)

        // Dark wake while lid is still closed: should NOT trigger wakeWhileArmed alarm
        closedMonitor.onHardwareEvent?(.systemDidWake)
        #expect(closedCoordinator.state == .armed)

        // Wake when lid is open: starts grace countdown (.tamperPending), NOT immediate .alarm
        let openMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100, isLidClosed: false)
        let openCoordinator = SecurityCoordinator(settings: settings, powerMonitor: openMonitor)
        openCoordinator.startArming(immediate: true)
        #expect(openCoordinator.state == .armed)

        openMonitor.onHardwareEvent?(.systemDidWake)
        #expect(openCoordinator.state == .tamperPending)
        #expect(openCoordinator.activeTamperSource == .wakeWhileArmed)
    }
}
