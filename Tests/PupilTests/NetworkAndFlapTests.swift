//
//  NetworkAndFlapTests.swift
//  PupilTests
//
//  Unit and integration tests for NetworkPathSentinel, NetworkTransitionEvaluator,
//  ChargerFlapDetector, PupilSettings.networkDropMonitorEnabled, and SecurityCoordinator.
//

import Foundation
import Testing
@testable import Pupil

@Suite("Network Sentinel and Charger Flap Tests", .serialized)
struct NetworkAndFlapTests {

    @MainActor
    private func makeIsolatedSettings() -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.networkflap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    // MARK: - 1. NetworkTransitionEvaluator Tests

    @Test("NetworkTransitionEvaluator: baseline ingestion returns nil")
    func evaluatorBaselineReturnsNil() {
        var evaluator = NetworkTransitionEvaluator()
        #expect(evaluator.lastSnapshot == nil)

        let baseline = NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi)
        let event = evaluator.ingest(baseline)
        #expect(event == nil)
        #expect(evaluator.lastSnapshot == baseline)
    }

    @Test("NetworkTransitionEvaluator: identical consecutive snapshots return nil")
    func evaluatorIdenticalSnapshotsReturnNil() {
        var evaluator = NetworkTransitionEvaluator()
        let wifi = NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi)
        _ = evaluator.ingest(wifi)

        // Ingesting identical Wi-Fi state emits no event
        #expect(evaluator.ingest(wifi) == nil)

        // Transition to offline emits connectivityLost
        let offline = NetworkSnapshot(isSatisfied: false, primaryInterface: .none)
        #expect(evaluator.ingest(offline) == .connectivityLost(previous: .wifi))

        // Subsequent identical offline snapshot emits no event
        #expect(evaluator.ingest(offline) == nil)
    }

    @Test("NetworkTransitionEvaluator: Wi-Fi and Ethernet transitions to offline emit connectivityLost")
    func evaluatorTransitionsToOffline() {
        // Wi-Fi -> Offline
        var wifiEvaluator = NetworkTransitionEvaluator()
        _ = wifiEvaluator.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi))
        let wifiDrop = wifiEvaluator.ingest(NetworkSnapshot(isSatisfied: false, primaryInterface: .none))
        #expect(wifiDrop == .connectivityLost(previous: .wifi))

        // Wired Ethernet -> Offline
        var ethernetEvaluator = NetworkTransitionEvaluator()
        _ = ethernetEvaluator.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .wiredEthernet))
        let ethernetDrop = ethernetEvaluator.ingest(NetworkSnapshot(isSatisfied: false, primaryInterface: .none))
        #expect(ethernetDrop == .connectivityLost(previous: .wiredEthernet))
    }

    @Test("NetworkTransitionEvaluator: offline to Wi-Fi and Ethernet recovery emit connectivityRestored")
    func evaluatorRecoveryFromOffline() {
        var evaluator = NetworkTransitionEvaluator()
        // Start offline
        _ = evaluator.ingest(NetworkSnapshot(isSatisfied: false, primaryInterface: .none))

        // Offline -> Wi-Fi
        let restoredWifi = evaluator.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi))
        #expect(restoredWifi == .connectivityRestored(current: .wifi))

        // Wi-Fi -> Offline
        _ = evaluator.ingest(NetworkSnapshot(isSatisfied: false, primaryInterface: .none))

        // Offline -> Wired Ethernet
        let restoredEthernet = evaluator.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .wiredEthernet))
        #expect(restoredEthernet == .connectivityRestored(current: .wiredEthernet))
    }

    @Test("NetworkTransitionEvaluator: interface downgrade to cellular or other emits interfaceChanged")
    func evaluatorInterfaceChanged() {
        // Wi-Fi -> Cellular
        var evaluator = NetworkTransitionEvaluator()
        _ = evaluator.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi))
        let toCellular = evaluator.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .cellular))
        #expect(toCellular == .interfaceChanged(from: .wifi, to: .cellular))

        // Wi-Fi -> Other
        var evaluator2 = NetworkTransitionEvaluator()
        _ = evaluator2.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi))
        let toOther = evaluator2.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .other))
        #expect(toOther == .interfaceChanged(from: .wifi, to: .other))

        // Wired Ethernet -> Other
        var evaluator3 = NetworkTransitionEvaluator()
        _ = evaluator3.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .wiredEthernet))
        let ethToOther = evaluator3.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .other))
        #expect(ethToOther == .interfaceChanged(from: .wiredEthernet, to: .other))

        // Wi-Fi -> Ethernet is not a downgrade away from Wi-Fi/Ethernet; returns nil
        var evaluator4 = NetworkTransitionEvaluator()
        _ = evaluator4.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi))
        let toEthernet = evaluator4.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .wiredEthernet))
        #expect(toEthernet == nil)
    }

    @Test("NetworkTransitionEvaluator: reset clears historical snapshot")
    func evaluatorResetClearsState() {
        var evaluator = NetworkTransitionEvaluator()
        _ = evaluator.ingest(NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi))
        #expect(evaluator.lastSnapshot != nil)

        evaluator.reset()
        #expect(evaluator.lastSnapshot == nil)

        // Ingesting offline after reset acts as initial baseline and returns nil
        let event = evaluator.ingest(NetworkSnapshot(isSatisfied: false, primaryInterface: .none))
        #expect(event == nil)
    }

    @Test("NetworkPathSentinel: snapshot ingestion dispatches onTransition and updates currentSnapshot")
    @MainActor
    func sentinelIngestionDispatches() {
        let sentinel = NetworkPathSentinel()
        var receivedEvents: [NetworkTransitionEvent] = []
        sentinel.onTransition = { receivedEvents.append($0) }

        let wifi = NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi)
        sentinel.ingestSnapshot(wifi)
        #expect(sentinel.currentSnapshot == wifi)
        #expect(receivedEvents.isEmpty)

        let offline = NetworkSnapshot(isSatisfied: false, primaryInterface: .none)
        sentinel.ingestSnapshot(offline)
        #expect(sentinel.currentSnapshot == offline)
        #expect(receivedEvents == [.connectivityLost(previous: .wifi)])

        let restored = NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi)
        sentinel.ingestSnapshot(restored)
        #expect(sentinel.currentSnapshot == restored)
        #expect(receivedEvents == [
            .connectivityLost(previous: .wifi),
            .connectivityRestored(current: .wifi)
        ])
    }

    // MARK: - 2. ChargerFlapDetector Sliding Window Tests

    @Test("ChargerFlapDetector: rapid transitions >= 3 within 6.0s trigger flapping")
    func chargerFlapTriggersAtThreshold() {
        var detector = ChargerFlapDetector(windowSeconds: 6.0, flapThreshold: 3)
        #expect(detector.transitionTimestamps.isEmpty)
        #expect(detector.isFlapping(at: 100.0) == false)

        // Transition 1 at t = 100.0
        let f1 = detector.recordTransition(at: 100.0)
        #expect(f1 == false)
        #expect(detector.isFlapping(at: 100.0) == false)
        #expect(detector.transitionTimestamps.count == 1)

        // Transition 2 at t = 101.5
        let f2 = detector.recordTransition(at: 101.5)
        #expect(f2 == false)
        #expect(detector.isFlapping(at: 101.5) == false)
        #expect(detector.transitionTimestamps.count == 2)

        // Transition 3 at t = 103.0 (3 in 3.0s <= 6.0s) -> Flapping triggered!
        let f3 = detector.recordTransition(at: 103.0)
        #expect(f3 == true)
        #expect(detector.isFlapping(at: 103.0) == true)
        #expect(detector.transitionTimestamps.count == 3)

        // Transition 4 at t = 104.0 -> remains flapping
        let f4 = detector.recordTransition(at: 104.0)
        #expect(f4 == true)
        #expect(detector.isFlapping(at: 104.0) == true)
        #expect(detector.transitionTimestamps.count == 4)
    }

    @Test("ChargerFlapDetector: spaced-out transitions do not trigger flapping")
    func chargerFlapSpacedOutTransitions() {
        var detector = ChargerFlapDetector(windowSeconds: 6.0, flapThreshold: 3)

        // Transitions spaced 7.0s apart (> 6.0s window)
        #expect(detector.recordTransition(at: 100.0) == false)
        #expect(detector.transitionTimestamps.count == 1)

        #expect(detector.recordTransition(at: 107.0) == false)
        #expect(detector.transitionTimestamps.count == 1) // 100.0 pruned

        #expect(detector.recordTransition(at: 114.0) == false)
        #expect(detector.transitionTimestamps.count == 1) // 107.0 pruned

        #expect(detector.recordTransition(at: 121.0) == false)
        #expect(detector.transitionTimestamps.count == 1) // 114.0 pruned
        #expect(detector.isFlapping(at: 121.0) == false)
    }

    @Test("ChargerFlapDetector: window expiration and reset clear flapping state")
    func chargerFlapExpirationAndReset() {
        var detector = ChargerFlapDetector(windowSeconds: 6.0, flapThreshold: 3)

        // Rapid flapping at 100.0, 101.0, 102.0
        detector.recordTransition(at: 100.0)
        detector.recordTransition(at: 101.0)
        detector.recordTransition(at: 102.0)
        #expect(detector.isFlapping(at: 102.0) == true)

        // After window expires (> 6s since t=102, e.g. at t = 109.0)
        #expect(detector.isFlapping(at: 109.0) == false)
        detector.prune(at: 109.0)
        #expect(detector.transitionTimestamps.isEmpty)

        // Flap again
        detector.recordTransition(at: 200.0)
        detector.recordTransition(at: 201.0)
        detector.recordTransition(at: 202.0)
        #expect(detector.isFlapping(at: 202.0) == true)

        // Reset clears state immediately
        detector.reset()
        #expect(detector.transitionTimestamps.isEmpty)
        #expect(detector.isFlapping(at: 202.0) == false)
    }

    @Test("PowerAndLidMonitor: charger flap recording and state reset integration")
    @MainActor
    func powerMonitorChargerFlapIntegration() {
        let monitor = PowerAndLidMonitor()
        monitor.resetChargerFlapState()
        #expect(monitor.isChargerFlapping == false)

        // Unplug at 100.0
        monitor.recordChargerTransition(isOnAC: false, at: 100.0)
        #expect(monitor.isOnACPower == false)
        #expect(monitor.isChargerFlapping == false)

        // Replug at 101.0
        monitor.recordChargerTransition(isOnAC: true, at: 101.0)
        #expect(monitor.isOnACPower == true)
        #expect(monitor.isChargerFlapping == false)

        // Unplug at 102.0 (3rd transition in 2s)
        monitor.recordChargerTransition(isOnAC: false, at: 102.0)
        #expect(monitor.isOnACPower == false)
        #expect(monitor.isChargerFlapping == true)

        // Reset clears flapping
        monitor.resetChargerFlapState()
        #expect(monitor.isChargerFlapping == false)
    }

    // MARK: - 3. PupilSettings Persistence Tests

    @Test("PupilSettings: networkDropMonitorEnabled defaults to true and persists")
    @MainActor
    func settingsPersistence() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Defaults to true
        #expect(settings.networkDropMonitorEnabled == true)

        // Setting to false persists
        settings.networkDropMonitorEnabled = false
        #expect(defaults.bool(forKey: "pupil.networkDropMonitorEnabled") == false)

        let reloadedFalse = PupilSettings(defaults: defaults)
        #expect(reloadedFalse.networkDropMonitorEnabled == false)

        // Re-enabling persists
        reloadedFalse.networkDropMonitorEnabled = true
        let reloadedTrue = PupilSettings(defaults: defaults)
        #expect(reloadedTrue.networkDropMonitorEnabled == true)
    }

    // MARK: - 4. SecurityCoordinator Integration Tests

    @Test("SecurityCoordinator: single charger reconnect reverts tamper to armed")
    @MainActor
    func coordinatorSingleReconnectReverts() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.exitDelaySeconds = 0
        settings.revertTamperOnPowerRestored = true
        settings.gazeDetectionEnabled = false
        settings.isSpatialMotionEnabled = false

        var dispatchedAlerts: [AlertMessage] = []
        let notifier = AlertNotifier(backoffSeconds: [], transport: { msg in
            dispatchedAlerts.append(msg)
            return .delivered
        })

        let coordinator = SecurityCoordinator(settings: settings, alertNotifier: notifier)
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        // Single unplug at t = 100.0 triggers tamper
        coordinator.powerMonitor.recordChargerTransition(isOnAC: false, at: 100.0)
        #expect(coordinator.state == .tamperPending)
        #expect(coordinator.activeTamperSource == .chargerUnplugged)

        // Replug at t = 101.0 (2 transitions total, flapping is false) -> Reverts to armed!
        coordinator.powerMonitor.recordChargerTransition(isOnAC: true, at: 101.0)
        #expect(coordinator.powerMonitor.isChargerFlapping == false)
        #expect(coordinator.state == .armed)
        #expect(coordinator.activeTamperSource == nil)
        #expect(coordinator.events.contains { $0.title == "Tamper Canceled" })

        _ = coordinator.disarmViaRemotePhone()
        #expect(coordinator.state == .disarmed)
    }

    @Test("SecurityCoordinator: rapid charger flapping prevents revertTamperToArmed bypass")
    @MainActor
    func coordinatorFlappingPreventsRevertBypass() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.exitDelaySeconds = 0
        settings.revertTamperOnPowerRestored = true
        settings.gazeDetectionEnabled = false
        settings.isSpatialMotionEnabled = false

        let notifier = AlertNotifier(backoffSeconds: [], transport: { _ in .delivered })
        let coordinator = SecurityCoordinator(settings: settings, alertNotifier: notifier)
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        // Transition 1: unplug at t = 100.0 -> tamper countdown starts
        coordinator.powerMonitor.recordChargerTransition(isOnAC: false, at: 100.0)
        #expect(coordinator.state == .tamperPending)

        // Transition 2: replug at t = 101.0 -> reverts to armed
        coordinator.powerMonitor.recordChargerTransition(isOnAC: true, at: 101.0)
        #expect(coordinator.state == .armed)

        // Transition 3: unplug again at t = 102.0 -> enters tamperPending (3 transitions in 2s, now flapping)
        coordinator.powerMonitor.recordChargerTransition(isOnAC: false, at: 102.0)
        #expect(coordinator.powerMonitor.isChargerFlapping == true)
        #expect(coordinator.state == .tamperPending)

        // Transition 4: replug at t = 103.0 while flapping!
        coordinator.powerMonitor.recordChargerTransition(isOnAC: true, at: 103.0)
        #expect(coordinator.powerMonitor.isChargerFlapping == true)

        // CRITICAL CHECK: State MUST NOT revert to armed! Tamper countdown remains active!
        #expect(coordinator.state == .tamperPending)
        #expect(coordinator.activeTamperSource == .chargerUnplugged)

        // Verify "Charger Flap Ignored" advisory event was logged
        let flapIgnoredEvent = coordinator.events.first { $0.title == "Charger Flap Ignored" }
        #expect(flapIgnoredEvent != nil)
        #expect(flapIgnoredEvent?.detail.contains("Rapid power cycling detected") == true)

        _ = coordinator.disarmViaRemotePhone()
        #expect(coordinator.state == .disarmed)
    }

    @Test("SecurityCoordinator: network transitions while armed log advisories and flush alert notifier")
    @MainActor
    func coordinatorNetworkTransitionsArmed() async throws {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.exitDelaySeconds = 0
        settings.networkDropMonitorEnabled = true
        settings.gazeDetectionEnabled = false
        settings.isSpatialMotionEnabled = false

        var dispatchedAlerts: [AlertMessage] = []
        let notifier = AlertNotifier(backoffSeconds: [], transport: { msg in
            dispatchedAlerts.append(msg)
            return .delivered
        })

        let coordinator = SecurityCoordinator(settings: settings, alertNotifier: notifier)
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        // 1. Ingest baseline Wi-Fi
        coordinator.networkSentinel.ingestSnapshot(NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi))
        await notifier.waitUntilIdle()
        #expect(dispatchedAlerts.isEmpty)

        // 2. Drop connection: Wi-Fi -> Offline
        coordinator.networkSentinel.ingestSnapshot(NetworkSnapshot(isSatisfied: false, primaryInterface: .none))
        await notifier.waitUntilIdle()
        #expect(coordinator.events.contains { $0.title == "Network Drop Detected" })
        let dropAlert = dispatchedAlerts.first { $0.tag == "pupil-network" && $0.title == "Pupil Network Drop Advisory" }
        #expect(dropAlert != nil)
        #expect(dropAlert?.severity == "high")
        #expect(dropAlert?.body.contains("Wi-Fi connection dropped") == true)

        // 3. Restore connection: Offline -> Wi-Fi
        coordinator.networkSentinel.ingestSnapshot(NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi))
        await notifier.waitUntilIdle()
        #expect(coordinator.events.contains { $0.title == "Network Restored" })
        let restoredEvent = coordinator.events.first { $0.title == "Network Restored" }
        #expect(restoredEvent?.detail.contains("Flushing queued alerts") == true)

        // 4. Interface downgrade: Wi-Fi -> Other
        coordinator.networkSentinel.ingestSnapshot(NetworkSnapshot(isSatisfied: true, primaryInterface: .other))
        await notifier.waitUntilIdle()
        #expect(coordinator.events.contains { $0.title == "Network Interface Changed" })
        let changeAlert = dispatchedAlerts.first { $0.tag == "pupil-network" && $0.title == "Pupil Network Change Advisory" }
        #expect(changeAlert != nil)
        #expect(changeAlert?.severity == "normal")
        #expect(changeAlert?.body.contains("Network switched from Wi-Fi to Other") == true)

        _ = coordinator.disarmViaRemotePhone()
        #expect(coordinator.state == .disarmed)
    }

    @Test("SecurityCoordinator: network drops do not trigger alerts when disabled or disarmed")
    @MainActor
    func coordinatorNetworkDropsSuppressedWhenDisabledOrDisarmed() async throws {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.exitDelaySeconds = 0
        settings.gazeDetectionEnabled = false
        settings.isSpatialMotionEnabled = false

        var dispatchedAlerts: [AlertMessage] = []
        let notifier = AlertNotifier(backoffSeconds: [], transport: { msg in
            dispatchedAlerts.append(msg)
            return .delivered
        })

        let coordinator = SecurityCoordinator(settings: settings, alertNotifier: notifier)

        // Case A: Disarmed -> network transitions must be ignored
        #expect(coordinator.state == .disarmed)
        coordinator.networkSentinel.ingestSnapshot(NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi))
        coordinator.networkSentinel.ingestSnapshot(NetworkSnapshot(isSatisfied: false, primaryInterface: .none))
        await notifier.waitUntilIdle()
        #expect(dispatchedAlerts.isEmpty)
        #expect(!coordinator.events.contains { $0.title == "Network Drop Detected" })

        // Case B: Armed, but networkDropMonitorEnabled is false -> ignored
        settings.networkDropMonitorEnabled = false
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        coordinator.networkSentinel.ingestSnapshot(NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi))
        coordinator.networkSentinel.ingestSnapshot(NetworkSnapshot(isSatisfied: false, primaryInterface: .none))
        await notifier.waitUntilIdle()
        #expect(dispatchedAlerts.isEmpty)
        #expect(!coordinator.events.contains { $0.title == "Network Drop Detected" })

        _ = coordinator.disarmViaRemotePhone()
        #expect(coordinator.state == .disarmed)
    }

    @Test("AlertNotifier: flushPendingNow restarts draining of pending queue")
    @MainActor
    func alertNotifierFlushPendingNow() async {
        var deliveredMessages: [AlertMessage] = []
        let notifier = AlertNotifier(
            backoffSeconds: [],
            transport: { msg in
                deliveredMessages.append(msg)
                return .delivered
            }
        )

        notifier.send(AlertMessage(title: "Test", body: "Body", tag: "test"))
        notifier.flushPendingNow()
        await notifier.waitUntilIdle()

        #expect(deliveredMessages.count == 1)
        #expect(deliveredMessages.first?.tag == "test")
    }
}
