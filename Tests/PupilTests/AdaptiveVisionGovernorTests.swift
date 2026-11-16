//
//  AdaptiveVisionGovernorTests.swift
//  PupilTests
//
//  Unit and integration tests for AdaptiveVisionGovernor, CameraManager throttling,
//  PupilSettings persistence, and SecurityCoordinator adaptive rate syncing.
//

import AppKit
import Foundation
import Testing
@testable import Pupil

@Suite("Adaptive Vision Governor Tests", .serialized)
struct AdaptiveVisionGovernorTests {
    @MainActor
    private func makeIsolatedSettings() -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.governor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    // MARK: - 1. Pure Deterministic Policy Matrix Tests

    @Test("Governor evaluateTargetFPS: AC power nominal idle yields 10 FPS")
    func testACPowerNominalIdle() {
        let fps = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: true,
            batteryPercent: 85,
            thermalState: .nominal,
            isActivitySuspected: false
        )
        #expect(fps == AdaptiveVisionGovernor.fullRateFPS)
        #expect(fps == 10.0)

        // Instance method forwarding
        let governor = AdaptiveVisionGovernor()
        #expect(governor.evaluate(isOnACPower: true, batteryPercent: 85, thermalState: .nominal, isActivitySuspected: false) == 10.0)
    }

    @Test("Governor evaluateTargetFPS: AC power with low battery still yields 10 FPS on AC")
    func testACPowerLowBatteryIdle() {
        let fps = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: true,
            batteryPercent: 15,
            thermalState: .nominal,
            isActivitySuspected: false
        )
        #expect(fps == 10.0)
    }

    @Test("Governor evaluateTargetFPS: Battery >= 30% nominal idle yields 10 FPS")
    func testBatteryAdequateNominalIdle() {
        let fps75 = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: false,
            batteryPercent: 75,
            thermalState: .nominal,
            isActivitySuspected: false
        )
        #expect(fps75 == 10.0)

        let fps30 = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: false,
            batteryPercent: 30,
            thermalState: .nominal,
            isActivitySuspected: false
        )
        #expect(fps30 == 10.0)
    }

    @Test("Governor evaluateTargetFPS: Battery < 30% nominal idle throttles to 5 FPS")
    func testBatteryLowNominalIdle() {
        let fps29 = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: false,
            batteryPercent: 29,
            thermalState: .nominal,
            isActivitySuspected: false
        )
        #expect(fps29 == AdaptiveVisionGovernor.ecoRateFPS)
        #expect(fps29 == 5.0)

        let fps5 = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: false,
            batteryPercent: 5,
            thermalState: .nominal,
            isActivitySuspected: false
        )
        #expect(fps5 == 5.0)

        let fps0 = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: false,
            batteryPercent: 0,
            thermalState: .nominal,
            isActivitySuspected: false
        )
        #expect(fps0 == 5.0)
    }

    @Test("Governor evaluateTargetFPS: Fair thermal state idle throttles to 5 FPS on AC and battery")
    func testFairThermalIdle() {
        let fpsAC = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: true,
            batteryPercent: 100,
            thermalState: .fair,
            isActivitySuspected: false
        )
        #expect(fpsAC == 5.0)

        let fpsBattery = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: false,
            batteryPercent: 80,
            thermalState: .fair,
            isActivitySuspected: false
        )
        #expect(fpsBattery == 5.0)
    }

    @Test("Governor evaluateTargetFPS: Serious and critical thermal state idle throttles to 2 FPS")
    func testSeriousAndCriticalThermalIdle() {
        let seriousAC = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: true,
            batteryPercent: 95,
            thermalState: .serious,
            isActivitySuspected: false
        )
        #expect(seriousAC == AdaptiveVisionGovernor.criticalThermalFPS)
        #expect(seriousAC == 2.0)

        let criticalAC = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: true,
            batteryPercent: 95,
            thermalState: .critical,
            isActivitySuspected: false
        )
        #expect(criticalAC == 2.0)

        let seriousBattery = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: false,
            batteryPercent: 60,
            thermalState: .serious,
            isActivitySuspected: false
        )
        #expect(seriousBattery == 2.0)

        let criticalBattery = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: false,
            batteryPercent: 10,
            thermalState: .critical,
            isActivitySuspected: false
        )
        #expect(criticalBattery == 2.0)
    }

    @Test("Governor evaluateTargetFPS: Activity suspected bursts to 10 FPS unconditionally")
    func testActivitySuspectedOverridesThrottling() {
        // Critical thermal + low battery + on battery:
        let burst1 = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: false,
            batteryPercent: 5,
            thermalState: .critical,
            isActivitySuspected: true
        )
        #expect(burst1 == 10.0)

        // Serious thermal + AC power:
        let burst2 = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: true,
            batteryPercent: 100,
            thermalState: .serious,
            isActivitySuspected: true
        )
        #expect(burst2 == 10.0)

        // Fair thermal:
        let burst3 = AdaptiveVisionGovernor.evaluateTargetFPS(
            isOnACPower: false,
            batteryPercent: 25,
            thermalState: .fair,
            isActivitySuspected: true
        )
        #expect(burst3 == 10.0)
    }

    // MARK: - 2. CameraManager Rate Throttling & Clamping Tests

    @Test("CameraManager updateAnalysisRate updates targetAnalysisFPS and clamps safely")
    @MainActor
    func testCameraManagerRateClamping() {
        let camera = CameraManager()
        #expect(camera.targetAnalysisFPS == 10.0)

        camera.updateAnalysisRate(fps: 5.0)
        #expect(camera.targetAnalysisFPS == 5.0)

        camera.updateAnalysisRate(fps: 2.0)
        #expect(camera.targetAnalysisFPS == 2.0)

        camera.updateAnalysisRate(fps: 15.0)
        #expect(camera.targetAnalysisFPS == 15.0)

        // Clamping lower bound [1.0, 30.0]
        camera.updateAnalysisRate(fps: 0.5)
        #expect(camera.targetAnalysisFPS == 1.0)

        camera.updateAnalysisRate(fps: -10.0)
        #expect(camera.targetAnalysisFPS == 1.0)

        // Clamping upper bound
        camera.updateAnalysisRate(fps: 60.0)
        #expect(camera.targetAnalysisFPS == 30.0)

        camera.updateAnalysisRate(fps: 120.0)
        #expect(camera.targetAnalysisFPS == 30.0)
    }

    // MARK: - 3. PupilSettings Persistence Tests

    @Test("PupilSettings adaptiveFrameRateEnabled defaults to true and persists across instances")
    @MainActor
    func testSettingsPersistence() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(settings.adaptiveFrameRateEnabled == true)

        settings.adaptiveFrameRateEnabled = false
        #expect(settings.adaptiveFrameRateEnabled == false)

        let reloaded = PupilSettings(defaults: defaults)
        #expect(reloaded.adaptiveFrameRateEnabled == false)

        reloaded.adaptiveFrameRateEnabled = true
        let reloadedAgain = PupilSettings(defaults: defaults)
        #expect(reloadedAgain.adaptiveFrameRateEnabled == true)
    }

    // MARK: - 4. SecurityCoordinator Integration Tests

    @Test("SecurityCoordinator syncAdaptiveVisionFrameRate: Thermal throttling when idle")
    @MainActor
    func testSecurityCoordinatorThermalThrottling() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let power = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100)
        let coordinator = SecurityCoordinator(
            settings: settings,
            powerMonitor: power,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("1234") }

        // Nominal idle on AC -> 10.0 FPS
        coordinator.thermalStateProvider = { .nominal }
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 10.0)

        // Serious thermal idle -> 2.0 FPS
        coordinator.thermalStateProvider = { .serious }
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 2.0)

        // Fair thermal idle -> 5.0 FPS
        coordinator.thermalStateProvider = { .fair }
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 5.0)

        // Critical thermal idle -> 2.0 FPS
        coordinator.thermalStateProvider = { .critical }
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 2.0)
    }

    @Test("SecurityCoordinator syncAdaptiveVisionFrameRate: Low battery throttling on battery power")
    @MainActor
    func testSecurityCoordinatorLowBatteryThrottling() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let power = PowerAndLidMonitor(isOnACPower: false, batteryPercentage: 20)
        let coordinator = SecurityCoordinator(
            settings: settings,
            powerMonitor: power,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("1234") }

        coordinator.thermalStateProvider = { .nominal }
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 5.0)

        // When battery is charged >= 30%, returns to 10.0 FPS
        power.updatePowerStateForTesting(isOnACPower: false, batteryPercentage: 80)
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 10.0)
    }

    @Test("SecurityCoordinator syncAdaptiveVisionFrameRate: Activity suspicion bursts to full 10 FPS")
    @MainActor
    func testSecurityCoordinatorActivityBurst() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let power = PowerAndLidMonitor(isOnACPower: false, batteryPercentage: 15)
        let coordinator = SecurityCoordinator(
            settings: settings,
            powerMonitor: power,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("1234") }

        // Start throttled due to low battery and critical thermal
        coordinator.thermalStateProvider = { .critical }
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 2.0)

        // Activity via GazeSample (active face detected)
        let sampleWithFace = GazeSample(
            timestamp: Date().timeIntervalSince1970,
            faceCount: 1,
            faceInsideROI: true,
            faceCentroid: CGPoint(x: 0.5, y: 0.5),
            towardScreenScore: 0.95,
            yawRadians: 0,
            pitchRadians: 0,
            irisHorizontalRatio: 0.5,
            trackingConfidence: 1.0
        )
        coordinator.ingestGazeSample(sampleWithFace)
        #expect(coordinator.activeFaceCount == 1)
        #expect(coordinator.cameraManager.targetAnalysisFPS == 10.0)

        // Activity clears: 0 faces
        let sampleNoFace = GazeSample(
            timestamp: Date().timeIntervalSince1970 + 1.0,
            faceCount: 0,
            faceInsideROI: false,
            faceCentroid: nil,
            towardScreenScore: 0,
            yawRadians: 0,
            pitchRadians: 0,
            irisHorizontalRatio: 0.5,
            trackingConfidence: 0
        )
        coordinator.ingestGazeSample(sampleNoFace)
        #expect(coordinator.activeFaceCount == 0)
        // With face gone and still critical thermal, returns to throttled 2.0 FPS
        #expect(coordinator.cameraManager.targetAnalysisFPS == 2.0)

        // Activity via armed/tamper state
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)
        coordinator.triggerTamper(source: .chargerUnplugged, immediateAlarm: false)
        #expect(coordinator.state == .tamperPending)
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 10.0)
    }

    @Test("SecurityCoordinator syncAdaptiveVisionFrameRate: Disabling adaptiveFrameRate locks to 10 FPS")
    @MainActor
    func testSecurityCoordinatorDisabledGovernorLocksToFullRate() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let power = PowerAndLidMonitor(isOnACPower: false, batteryPercentage: 10)
        let coordinator = SecurityCoordinator(
            settings: settings,
            powerMonitor: power,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("1234") }

        coordinator.thermalStateProvider = { .critical }
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 2.0)

        // Disable adaptive frame rate setting
        settings.adaptiveFrameRateEnabled = false
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 10.0)

        // Re-enable restores throttling
        settings.adaptiveFrameRateEnabled = true
        coordinator.syncAdaptiveVisionFrameRate()
        #expect(coordinator.cameraManager.targetAnalysisFPS == 2.0)
    }

    @Test("SecurityCoordinator responds to thermalStateDidChangeNotification")
    @MainActor
    func testThermalStateNotificationHandling() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("1234") }

        coordinator.thermalStateProvider = { .serious }
        NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        #expect(coordinator.cameraManager.targetAnalysisFPS == 2.0)
    }
}
