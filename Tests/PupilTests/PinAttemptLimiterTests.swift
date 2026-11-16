//
//  PinAttemptLimiterTests.swift
//  PupilTests
//
//  Unit and integration tests for exponential PIN brute-force lockout,
//  threshold backoffs, timer resets, and SecurityCoordinator alarm escalation.
//

import AppKit
import Foundation
import Testing
@testable import Pupil

@Suite("PIN Attempt Limiter & Lockout Tests", .serialized)
struct PinAttemptLimiterTests {

    @MainActor
    private func makeIsolatedSettings() -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.lockout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    // MARK: - Unit Tests: PinAttemptLimiter State Machine

    @Test("Limiter thresholds: < 5 allowed, >= 5 15s lockout, >= 8 60s lockout, >= 10 300s + escalateToAlarm")
    func testThresholdsAndBackoffs() {
        var limiter = PinAttemptLimiter()
        let t0: TimeInterval = 1_000_000

        #expect(limiter.failedAttemptCount == 0)
        #expect(limiter.lockoutDeadline == nil)
        #expect(limiter.status(at: t0) == .allowed)
        #expect(limiter.status(at: t0).isLockedOut == false)
        #expect(limiter.status(at: t0).remainingSeconds == 0)

        // Attempts 1 through 4: allowed
        for i in 1...4 {
            let status = limiter.recordFailure(at: t0 + Double(i))
            #expect(status == .allowed)
            #expect(status.isLockedOut == false)
            #expect(status.remainingSeconds == 0)
            #expect(limiter.failedAttemptCount == i)
            #expect(limiter.status(at: t0 + Double(i)) == .allowed)
        }

        // Attempt 5: Tier 1 lockout (15s)
        let t5 = t0 + 10
        let status5 = limiter.recordFailure(at: t5)
        #expect(status5 == .lockedOut(remainingSeconds: 15))
        #expect(status5.isLockedOut == true)
        #expect(status5.remainingSeconds == 15)
        #expect(limiter.failedAttemptCount == 5)
        #expect(limiter.lockoutDeadline == t5 + 15)

        // While locked out at t5 + 5: remaining 10s, attempts do not increment failure counter
        let statusLocked = limiter.status(at: t5 + 5)
        #expect(statusLocked == .lockedOut(remainingSeconds: 10))
        #expect(statusLocked.isLockedOut == true)
        #expect(statusLocked.remainingSeconds == 10)

        let attemptDuringLockout = limiter.recordFailure(at: t5 + 5)
        #expect(attemptDuringLockout == .lockedOut(remainingSeconds: 10))
        #expect(limiter.failedAttemptCount == 5)

        // Lockout expires at t5 + 15
        #expect(limiter.status(at: t5 + 15) == .allowed)
        #expect(limiter.failedAttemptCount == 5)

        // Attempts 6 and 7: Tier 1 lockouts (15s each)
        let t6 = t5 + 16
        let status6 = limiter.recordFailure(at: t6)
        #expect(status6 == .lockedOut(remainingSeconds: 15))
        #expect(limiter.failedAttemptCount == 6)

        let t7 = t6 + 16
        let status7 = limiter.recordFailure(at: t7)
        #expect(status7 == .lockedOut(remainingSeconds: 15))
        #expect(limiter.failedAttemptCount == 7)

        // Attempt 8: Tier 2 lockout (60s)
        let t8 = t7 + 16
        let status8 = limiter.recordFailure(at: t8)
        #expect(status8 == .lockedOut(remainingSeconds: 60))
        #expect(status8.isLockedOut == true)
        #expect(status8.remainingSeconds == 60)
        #expect(limiter.failedAttemptCount == 8)
        #expect(limiter.lockoutDeadline == t8 + 60)

        // Status halfway through Tier 2: 30s remaining
        let statusTier2Mid = limiter.status(at: t8 + 30)
        #expect(statusTier2Mid == .lockedOut(remainingSeconds: 30))

        // Attempt 9: Tier 2 lockout (60s) after Tier 2 expires
        let t9 = t8 + 61
        let status9 = limiter.recordFailure(at: t9)
        #expect(status9 == .lockedOut(remainingSeconds: 60))
        #expect(limiter.failedAttemptCount == 9)

        // Attempt 10: Tier 3 alarm escalation (300s + escalateToAlarm)
        let t10 = t9 + 61
        let status10 = limiter.recordFailure(at: t10)
        #expect(status10 == .escalateToAlarm(remainingSeconds: 300))
        #expect(status10.isLockedOut == true)
        #expect(status10.remainingSeconds == 300)
        #expect(limiter.failedAttemptCount == 10)
        #expect(limiter.lockoutDeadline == t10 + 300)

        // Subsequent status reports active lockout
        let statusTier3Mid = limiter.status(at: t10 + 100)
        #expect(statusTier3Mid == .lockedOut(remainingSeconds: 200))
    }

    @Test("Limiter expiration and recordSuccess resets all counters and deadlines")
    func testResetOnSuccess() {
        var limiter = PinAttemptLimiter()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        for i in 0..<5 {
            limiter.recordFailure(at: now.addingTimeInterval(Double(i)))
        }
        #expect(limiter.failedAttemptCount == 5)
        #expect(limiter.lockoutDeadline != nil)
        #expect(limiter.status(at: now.addingTimeInterval(5)).isLockedOut == true)

        // Successful authentication clears state
        limiter.recordSuccess()
        #expect(limiter.failedAttemptCount == 0)
        #expect(limiter.lockoutDeadline == nil)
        #expect(limiter.status(at: now.addingTimeInterval(5)) == .allowed)

        // Subsequent failure starts counter anew at 1 (not locked out)
        let statusAfterReset = limiter.recordFailure(at: now.addingTimeInterval(10))
        #expect(statusAfterReset == .allowed)
        #expect(limiter.failedAttemptCount == 1)
    }

    @Test("TamperSource confidence for pinBruteForce is strong")
    func testTamperSourceConfidence() {
        let source = TamperSource.pinBruteForce
        #expect(source.rawValue == "Repeated Failed PIN Attempts")
        #expect(source.confidence == .strong)
    }

    // MARK: - Integration Tests: SecurityCoordinator

    @Test("SecurityCoordinator rejects attempts while locked out and updates countdown")
    @MainActor
    func testCoordinatorRejectsDuringLockout() throws {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try KeychainManager.enrollPin("2468")
        let coordinator = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("2468") }

        var simTime: TimeInterval = 1_700_000_000
        coordinator.clock = { simTime }

        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)
        #expect(coordinator.isPinLockedOut == false)

        // 4 failed attempts: not locked out yet
        for _ in 1...4 {
            let res = coordinator.disarmWithPin("0000")
            #expect(res == false)
            #expect(coordinator.isPinLockedOut == false)
            #expect(coordinator.pinLockoutSecondsRemaining == 0)
        }
        #expect(coordinator.attemptLimiter.failedAttemptCount == 4)

        // 5th failed attempt: triggers 15s lockout
        let res5 = coordinator.disarmWithPin("0000")
        #expect(res5 == false)
        #expect(coordinator.isPinLockedOut == true)
        #expect(coordinator.pinLockoutSecondsRemaining == 15)
        #expect(coordinator.attemptLimiter.failedAttemptCount == 5)

        // Attempting with the CORRECT PIN while locked out must be rejected immediately
        simTime += 5
        let correctAttemptWhileLocked = coordinator.disarmWithPin("2468")
        #expect(correctAttemptWhileLocked == false)
        #expect(coordinator.state == .armed)
        #expect(coordinator.isPinLockedOut == true)
        #expect(coordinator.pinLockoutSecondsRemaining == 10)

        // Advance past lockout deadline and refresh
        simTime += 11
        coordinator.refreshPinLockoutCountdown()
        #expect(coordinator.isPinLockedOut == false)
        #expect(coordinator.pinLockoutSecondsRemaining == 0)

        // Now correct PIN disarms cleanly
        let disarmAfterLockout = coordinator.disarmWithPin("2468")
        #expect(disarmAfterLockout == true)
        #expect(coordinator.state == .disarmed)
        #expect(coordinator.attemptLimiter.failedAttemptCount == 0)
    }

    @Test("SecurityCoordinator escalates to alarm (.pinBruteForce) at 10 failures")
    @MainActor
    func testCoordinatorEscalatesToAlarmAtTenFailures() throws {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try KeychainManager.enrollPin("2468")
        let coordinator = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("2468") }

        var simTime: TimeInterval = 1_700_000_000
        coordinator.clock = { simTime }

        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        // Fail 4 times (allowed)
        for _ in 1...4 {
            #expect(coordinator.disarmWithPin("0000") == false)
        }

        // Fail 5th time -> 15s lockout
        #expect(coordinator.disarmWithPin("0000") == false)
        #expect(coordinator.pinLockoutSecondsRemaining == 15)

        // Advance past 1st lockout
        simTime += 16
        coordinator.refreshPinLockoutCountdown()

        // Fail 6th time -> 15s lockout
        #expect(coordinator.disarmWithPin("0000") == false)
        simTime += 16
        coordinator.refreshPinLockoutCountdown()

        // Fail 7th time -> 15s lockout
        #expect(coordinator.disarmWithPin("0000") == false)
        simTime += 16
        coordinator.refreshPinLockoutCountdown()

        // Fail 8th time -> 60s lockout (Tier 2)
        #expect(coordinator.disarmWithPin("0000") == false)
        #expect(coordinator.pinLockoutSecondsRemaining == 60)
        simTime += 61
        coordinator.refreshPinLockoutCountdown()

        // Fail 9th time -> 60s lockout
        #expect(coordinator.disarmWithPin("0000") == false)
        #expect(coordinator.pinLockoutSecondsRemaining == 60)
        simTime += 61
        coordinator.refreshPinLockoutCountdown()

        // Fail 10th time -> 300s lockout + immediate alarm escalation
        #expect(coordinator.disarmWithPin("0000") == false)
        #expect(coordinator.state == .alarm)
        #expect(coordinator.activeTamperSource == .pinBruteForce)
        #expect(coordinator.isPinLockedOut == true)
        #expect(coordinator.pinLockoutSecondsRemaining == 300)
        #expect(coordinator.attemptLimiter.failedAttemptCount == 10)

        // Advance past 300s lockout
        simTime += 301
        coordinator.refreshPinLockoutCountdown()
        #expect(coordinator.isPinLockedOut == false)

        // Valid PIN disarms the alarm and clears lockout
        let disarmed = coordinator.disarmWithPin("2468")
        #expect(disarmed == true)
        #expect(coordinator.state == .disarmed)
        #expect(coordinator.activeTamperSource == nil)
        #expect(coordinator.attemptLimiter.failedAttemptCount == 0)
        #expect(coordinator.pinLockoutSecondsRemaining == 0)
    }

    @Test("Valid Touch ID clears active PIN lockout and disarms coordinator")
    @MainActor
    func testTouchIDClearsLockout() async throws {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try KeychainManager.enrollPin("2468")
        let coordinator = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("2468") }

        let simTime: TimeInterval = 1_700_000_000
        coordinator.clock = { simTime }

        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        // Trigger 15s lockout with 5 wrong attempts
        for _ in 1...5 {
            _ = coordinator.disarmWithPin("0000")
        }
        #expect(coordinator.isPinLockedOut == true)
        #expect(coordinator.pinLockoutSecondsRemaining == 15)

        // Mock Touch ID success
        KeychainManager.mockTouchIDResult = true
        defer { KeychainManager.mockTouchIDResult = nil }

        let touchIDSuccess = await coordinator.disarmWithTouchID()
        #expect(touchIDSuccess == true)
        #expect(coordinator.state == .disarmed)
        #expect(coordinator.isPinLockedOut == false)
        #expect(coordinator.pinLockoutSecondsRemaining == 0)
        #expect(coordinator.attemptLimiter.failedAttemptCount == 0)
    }

    @Test("Device owner authentication PIN recovery clears lockout and resets PIN")
    @MainActor
    func testDeviceOwnerRecoveryClearsLockout() async throws {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try KeychainManager.enrollPin("2468")
        let coordinator = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("9876") }

        let simTime: TimeInterval = 1_700_000_000
        coordinator.clock = { simTime }

        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        // Trigger lockout
        for _ in 1...5 {
            _ = coordinator.disarmWithPin("0000")
        }
        #expect(coordinator.isPinLockedOut == true)
        #expect(coordinator.pinLockoutSecondsRemaining == 15)

        // Mock Device Owner (Mac password / biometrics) recovery
        KeychainManager.mockDeviceOwnerResult = true
        defer { KeychainManager.mockDeviceOwnerResult = nil }

        let recoverySuccess = await coordinator.recoverPinWithDeviceOwnerAuth(newPin: "9876")
        #expect(recoverySuccess == true)
        #expect(coordinator.isPinLockedOut == false)
        #expect(coordinator.pinLockoutSecondsRemaining == 0)
        #expect(coordinator.attemptLimiter.failedAttemptCount == 0)
        #expect(KeychainManager.verifyPin("9876") == true)
    }
}
