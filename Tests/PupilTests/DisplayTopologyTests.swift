//
//  DisplayTopologyTests.swift
//  PupilTests
//
//  Unit and integration tests for pure Sendable DisplayTopologyEvaluator,
//  PupilSettings displayUnplugTriggerEnabled persistence, PowerAndLidMonitor,
//  and SecurityCoordinator hot-unplug sentry integration.
//

import CoreGraphics
import Foundation
import Testing
@testable import Pupil

@Suite("Display Topology & External Display Hot-Unplug Sentry Tests", .serialized)
struct DisplayTopologyTests {

    @MainActor
    private func makeIsolatedSettings() -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.displaytopology.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    // MARK: - 1. DisplayTopologyEvaluator Disconnect Detection

    @Test("DisplayTopologyEvaluator detects external display disconnect and reports removedCount")
    func testExternalDisplayDisconnectDetection() {
        var evaluator = DisplayTopologyEvaluator()
        #expect(!evaluator.hasBaseline)
        #expect(evaluator.baselineExternalIDs.isEmpty)

        // Baseline: built-in display 1, external displays 2 and 3
        let baseline = DisplayTopologySnapshot(
            externalDisplayIDs: [2, 3],
            builtInDisplayIDs: [1]
        )
        evaluator.latchBaseline(baseline)
        #expect(evaluator.hasBaseline)
        #expect(evaluator.baselineExternalIDs == [2, 3])

        // Identical topology returns .unchanged
        let identical = DisplayTopologySnapshot(
            externalDisplayIDs: [2, 3],
            builtInDisplayIDs: [1]
        )
        #expect(evaluator.evaluate(identical) == .unchanged)

        // Disconnect external display 3 (external count 2 -> 1)
        let oneRemoved = DisplayTopologySnapshot(
            externalDisplayIDs: [2],
            builtInDisplayIDs: [1]
        )
        let event1 = evaluator.evaluate(oneRemoved)
        #expect(event1 == .externalDisplayDisconnected(removedCount: 1))
        #expect(evaluator.baselineExternalIDs == [2])

        // Disconnect remaining external display 2 (external count 1 -> 0)
        let allRemoved = DisplayTopologySnapshot(
            externalDisplayIDs: [],
            builtInDisplayIDs: [1]
        )
        let event2 = evaluator.evaluate(allRemoved)
        #expect(event2 == .externalDisplayDisconnected(removedCount: 1))
        #expect(evaluator.baselineExternalIDs.isEmpty)

        // Further evaluations while empty remain unchanged
        #expect(evaluator.evaluate(allRemoved) == .unchanged)
    }

    @Test("DisplayTopologyEvaluator handles multiple simultaneous external display disconnects")
    func testMultipleExternalDisplaysDisconnectedSimultaneously() {
        var evaluator = DisplayTopologyEvaluator()
        let baseline = DisplayTopologySnapshot(
            externalDisplayIDs: [10, 20, 30],
            builtInDisplayIDs: [1]
        )
        evaluator.latchBaseline(baseline)

        // Disconnect 2 displays at once (external count 3 -> 1)
        let remaining = DisplayTopologySnapshot(
            externalDisplayIDs: [10],
            builtInDisplayIDs: [1]
        )
        let event = evaluator.evaluate(remaining)
        #expect(event == .externalDisplayDisconnected(removedCount: 2))
        #expect(evaluator.baselineExternalIDs == [10])
    }

    // MARK: - 2. Built-In Display Sleep/Wake & Attaching New Displays

    @Test("DisplayTopologyEvaluator completely ignores built-in display sleep, wake, or clamshell transitions")
    func testBuiltInDisplaySleepWakeIgnored() {
        var evaluator = DisplayTopologyEvaluator()
        let baseline = DisplayTopologySnapshot(
            externalDisplayIDs: [2],
            builtInDisplayIDs: [1]
        )
        evaluator.latchBaseline(baseline)

        // Built-in display sleeps / turns off (clamshell closed) while external display remains
        let builtInSleeping = DisplayTopologySnapshot(
            externalDisplayIDs: [2],
            builtInDisplayIDs: []
        )
        #expect(evaluator.evaluate(builtInSleeping) == .unchanged)
        #expect(evaluator.baselineExternalIDs == [2])

        // Built-in display wakes back up
        let builtInWaking = DisplayTopologySnapshot(
            externalDisplayIDs: [2],
            builtInDisplayIDs: [1]
        )
        #expect(evaluator.evaluate(builtInWaking) == .unchanged)
        #expect(evaluator.baselineExternalIDs == [2])
    }

    @Test("DisplayTopologyEvaluator expands baseline on external display attachment and ignores as tamper")
    func testAttachingNewExternalDisplayExpandsBaseline() {
        var evaluator = DisplayTopologyEvaluator()
        let initial = DisplayTopologySnapshot(
            externalDisplayIDs: [2],
            builtInDisplayIDs: [1]
        )
        evaluator.latchBaseline(initial)

        // Attach an additional external monitor (external 1 -> 2)
        let attached = DisplayTopologySnapshot(
            externalDisplayIDs: [2, 3],
            builtInDisplayIDs: [1]
        )
        let attachEvent = evaluator.evaluate(attached)
        #expect(attachEvent == .externalDisplayAttached(addedCount: 1))
        #expect(evaluator.baselineExternalIDs == [2, 3])

        // Subsequent removal of newly attached display triggers disconnect event
        let disconnected = DisplayTopologySnapshot(
            externalDisplayIDs: [2],
            builtInDisplayIDs: [1]
        )
        let disconnectEvent = evaluator.evaluate(disconnected)
        #expect(disconnectEvent == .externalDisplayDisconnected(removedCount: 1))
        #expect(evaluator.baselineExternalIDs == [2])
    }

    @Test("DisplayTopologyEvaluator auto-latches on first evaluate when baseline was not pre-set and resets cleanly")
    func testAutoLatchAndReset() {
        var evaluator = DisplayTopologyEvaluator()
        #expect(!evaluator.hasBaseline)

        let snapshot = DisplayTopologySnapshot(
            externalDisplayIDs: [5, 6],
            builtInDisplayIDs: [1]
        )
        #expect(evaluator.evaluate(snapshot) == .unchanged)
        #expect(evaluator.hasBaseline)
        #expect(evaluator.baselineExternalIDs == [5, 6])

        evaluator.reset()
        #expect(!evaluator.hasBaseline)
        #expect(evaluator.baselineExternalIDs.isEmpty)
    }

    @Test("DisplayTopologySnapshot partitions display IDs using predicate")
    func testDisplayTopologySnapshotPartitioning() {
        let allIDs: [CGDirectDisplayID] = [1, 2, 3, 4]
        let snapshot = DisplayTopologySnapshot(allDisplayIDs: allIDs) { id in
            id == 1 // Only ID 1 is built-in
        }

        #expect(snapshot.builtInDisplayIDs == [1])
        #expect(snapshot.externalDisplayIDs == [2, 3, 4])
    }

    // MARK: - 3. PupilSettings Persistence

    @Test("PupilSettings displayUnplugTriggerEnabled defaults to true and persists across instances")
    @MainActor
    func testDisplayUnplugTriggerEnabledPersistence() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Default value is true
        #expect(settings.displayUnplugTriggerEnabled == true)

        // Toggle to false and verify persistence
        settings.displayUnplugTriggerEnabled = false
        let reloadedFalse = PupilSettings(defaults: defaults)
        #expect(reloadedFalse.displayUnplugTriggerEnabled == false)

        // Toggle back to true and verify persistence
        settings.displayUnplugTriggerEnabled = true
        let reloadedTrue = PupilSettings(defaults: defaults)
        #expect(reloadedTrue.displayUnplugTriggerEnabled == true)
    }

    // MARK: - 4. SecurityCoordinator Integration

    @Test("SecurityCoordinator latches baseline on arm and escalates to tamperPending when external display is unplugged")
    @MainActor
    func testSecurityCoordinatorEscalatesOnExternalDisplayUnplugged() throws {
        try KeychainManager.withIsolatedStore {
            try KeychainManager.enrollPin("1234")
            let (settings, defaults, suiteName) = makeIsolatedSettings()
            defer { defaults.removePersistentDomain(forName: suiteName) }

            settings.displayUnplugTriggerEnabled = true
            settings.gazeDetectionEnabled = false
            settings.exitDelaySeconds = 0

            let notifier = AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
            let coordinator = SecurityCoordinator(settings: settings, alertNotifier: notifier)
            defer { coordinator.disarmWithPin("1234") }

            // Arm coordinator immediately
            coordinator.startArming(immediate: true)
            #expect(coordinator.state == .armed)
            #expect(coordinator.armedDisplayTopologyEvaluator.hasBaseline)

            // Latch known armed baseline with external monitor [100] and built-in [1]
            coordinator.latchArmedDisplayTopologyBaseline(DisplayTopologySnapshot(
                externalDisplayIDs: [100],
                builtInDisplayIDs: [1]
            ))

            // Built-in sleep or display attach should NOT trigger tamper
            coordinator.handleDisplayTopologyChange(DisplayTopologySnapshot(
                externalDisplayIDs: [100, 200],
                builtInDisplayIDs: [1]
            ))
            #expect(coordinator.state == .armed)
            #expect(coordinator.activeTamperSource == nil)

            // Unplug external display 200
            coordinator.handleDisplayTopologyChange(DisplayTopologySnapshot(
                externalDisplayIDs: [100],
                builtInDisplayIDs: [1]
            ))
            #expect(coordinator.state == .tamperPending)
            #expect(coordinator.activeTamperSource == .peripheralDisconnected)

            // Disarm and verify evaluator baseline is reset
            coordinator.disarmWithPin("1234")
            #expect(coordinator.state == .disarmed)
            #expect(!coordinator.armedDisplayTopologyEvaluator.hasBaseline)
        }
    }

    @Test("SecurityCoordinator ignores external display unplug when displayUnplugTriggerEnabled is false")
    @MainActor
    func testSecurityCoordinatorIgnoresUnplugWhenTriggerDisabled() throws {
        try KeychainManager.withIsolatedStore {
            try KeychainManager.enrollPin("1234")
            let (settings, defaults, suiteName) = makeIsolatedSettings()
            defer { defaults.removePersistentDomain(forName: suiteName) }

            settings.displayUnplugTriggerEnabled = false
            settings.gazeDetectionEnabled = false
            settings.exitDelaySeconds = 0

            let notifier = AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
            let coordinator = SecurityCoordinator(settings: settings, alertNotifier: notifier)
            defer { coordinator.disarmWithPin("1234") }

            coordinator.startArming(immediate: true)
            #expect(coordinator.state == .armed)

            coordinator.latchArmedDisplayTopologyBaseline(DisplayTopologySnapshot(
                externalDisplayIDs: [100],
                builtInDisplayIDs: [1]
            ))

            // Unplug external display while setting is disabled
            coordinator.handleDisplayTopologyChange(DisplayTopologySnapshot(
                externalDisplayIDs: [],
                builtInDisplayIDs: [1]
            ))

            #expect(coordinator.state == .armed)
            #expect(coordinator.activeTamperSource == nil)
        }
    }

    @Test("SecurityCoordinator ignores external display unplug when peripheralDisconnect hardware trigger is excluded")
    @MainActor
    func testSecurityCoordinatorIgnoresUnplugWhenHardwareTriggerExcluded() throws {
        try KeychainManager.withIsolatedStore {
            try KeychainManager.enrollPin("1234")
            let (settings, defaults, suiteName) = makeIsolatedSettings()
            defer { defaults.removePersistentDomain(forName: suiteName) }

            settings.displayUnplugTriggerEnabled = true
            settings.hardwareTriggers.remove(.peripheralDisconnect)
            settings.gazeDetectionEnabled = false
            settings.exitDelaySeconds = 0

            let notifier = AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
            let coordinator = SecurityCoordinator(settings: settings, alertNotifier: notifier)
            defer { coordinator.disarmWithPin("1234") }

            coordinator.startArming(immediate: true)
            #expect(coordinator.state == .armed)

            coordinator.latchArmedDisplayTopologyBaseline(DisplayTopologySnapshot(
                externalDisplayIDs: [100],
                builtInDisplayIDs: [1]
            ))

            // Unplug external display with peripheralDisconnect trigger unchecked
            coordinator.handleDisplayTopologyChange(DisplayTopologySnapshot(
                externalDisplayIDs: [],
                builtInDisplayIDs: [1]
            ))

            #expect(coordinator.state == .armed)
            #expect(coordinator.activeTamperSource == nil)
        }
    }

    @Test("SecurityCoordinator ignores display topology changes while disarmed")
    @MainActor
    func testSecurityCoordinatorIgnoresChangesWhileDisarmed() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let notifier = AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        let coordinator = SecurityCoordinator(settings: settings, alertNotifier: notifier)

        #expect(coordinator.state == .disarmed)
        coordinator.handleDisplayTopologyChange(DisplayTopologySnapshot(
            externalDisplayIDs: [],
            builtInDisplayIDs: []
        ))
        coordinator.handleExternalDisplayUnplugged(removedCount: 2)

        #expect(coordinator.state == .disarmed)
        #expect(coordinator.activeTamperSource == nil)
    }

    // MARK: - 5. PowerAndLidMonitor Integration

    @Test("PowerAndLidMonitor evaluateDisplayTopology forwards disconnect event to onHardwareEvent")
    @MainActor
    func testPowerAndLidMonitorDisplayTopologyForwarding() {
        let monitor = PowerAndLidMonitor()
        var receivedEvents: [PowerHardwareEvent] = []
        monitor.onHardwareEvent = { event in
            receivedEvents.append(event)
        }

        // Latch baseline with external display 20
        let baseline = DisplayTopologySnapshot(
            externalDisplayIDs: [20],
            builtInDisplayIDs: [1]
        )
        monitor.evaluateDisplayTopology(baseline)

        // Disconnect external display 20
        let unplugged = DisplayTopologySnapshot(
            externalDisplayIDs: [],
            builtInDisplayIDs: [1]
        )
        monitor.evaluateDisplayTopology(unplugged)

        #expect(receivedEvents.contains(.externalDisplayUnplugged(removedCount: 1)))
        #expect(monitor.connectedExternalDisplayIDs.isEmpty)
    }
}
