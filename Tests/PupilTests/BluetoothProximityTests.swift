import Foundation
import Testing
@testable import Pupil

@Suite("Bluetooth proximity hysteresis and coordinator integration")
struct BluetoothProximityTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Brief RSSI dip does not trigger walk-away")
    func briefDipDoesNotTrigger() {
        var evaluator = ProximityHysteresisEvaluator()

        #expect(evaluator.ingest(rssi: -55, at: t0) == nil)
        #expect(evaluator.ingest(rssi: -56, at: t0.addingTimeInterval(1)) == nil)
        #expect(evaluator.ingest(rssi: -54, at: t0.addingTimeInterval(2)) == nil)
        // Single brief dip below -82 dBm
        #expect(evaluator.ingest(rssi: -90, at: t0.addingTimeInterval(3)) == nil)
        #expect(evaluator.isAway == false)
        // Recovers immediately
        #expect(evaluator.ingest(rssi: -55, at: t0.addingTimeInterval(4)) == nil)
        #expect(evaluator.isAway == false)
    }

    @Test("Sustained weak RSSI triggers walk-away once")
    func sustainedWalkAwayTriggers() {
        var evaluator = ProximityHysteresisEvaluator()

        #expect(evaluator.ingest(rssi: -58, at: t0) == nil)
        #expect(evaluator.ingest(rssi: -84, at: t0.addingTimeInterval(1)) == nil)
        #expect(evaluator.ingest(rssi: -88, at: t0.addingTimeInterval(2)) == nil)

        var triggered = false
        for step in 3...8 {
            if evaluator.ingest(rssi: -90, at: t0.addingTimeInterval(Double(step))) == .walkAway {
                #expect(triggered == false) // Should only fire once on transition
                triggered = true
            }
        }
        #expect(triggered == true)
        #expect(evaluator.isAway == true)
    }

    @Test("Unseen for more than 6 seconds triggers walk-away")
    func unseenTimeoutTriggersWalkAway() {
        var evaluator = ProximityHysteresisEvaluator()

        #expect(evaluator.ingest(rssi: -60, at: t0) == nil)
        #expect(evaluator.evaluateTimeout(at: t0.addingTimeInterval(5.5)) == nil)
        #expect(evaluator.isAway == false)

        #expect(evaluator.evaluateTimeout(at: t0.addingTimeInterval(6.1)) == .walkAway)
        #expect(evaluator.isAway == true)
        // Should not re-fire
        #expect(evaluator.evaluateTimeout(at: t0.addingTimeInterval(10.0)) == nil)
    }

    @Test("Return requires smoothed RSSI > -65 dBm sustained for > 2.0 seconds")
    func returnHysteresis() {
        var evaluator = ProximityHysteresisEvaluator()

        // Walk away
        for step in 0...5 {
            _ = evaluator.ingest(rssi: -90, at: t0.addingTimeInterval(Double(step)))
        }
        #expect(evaluator.isAway == true)

        // Warm up smoothed RSSI above -65 dBm
        #expect(evaluator.ingest(rssi: -55, at: t0.addingTimeInterval(10)) == nil)
        #expect(evaluator.ingest(rssi: -55, at: t0.addingTimeInterval(11)) == nil)
        #expect(evaluator.ingest(rssi: -55, at: t0.addingTimeInterval(12)) == nil)
        // Smoothed RSSI is now > -65, candidate timer starts at t=13 (or earlier once > -65)
        let r1 = evaluator.ingest(rssi: -55, at: t0.addingTimeInterval(13))
        if r1 == nil {
            // Brief check at +1.5s should not return yet, or if it started at t=12 it's +1s
            // Drop back below -65 to reset return dwell timer
            #expect(evaluator.ingest(rssi: -95, at: t0.addingTimeInterval(13.5)) == nil)
            #expect(evaluator.ingest(rssi: -95, at: t0.addingTimeInterval(14.0)) == nil)
        }
        #expect(evaluator.isAway == true)

        // Now sustain strong signal > -65 dBm for > 2.0s
        var returned = false
        for step in 20...30 {
            if evaluator.ingest(rssi: -52, at: t0.addingTimeInterval(Double(step))) == .returned {
                returned = true
                break
            }
        }
        #expect(returned == true)
        #expect(evaluator.isAway == false)
    }

    @MainActor
    @Test("SecurityCoordinator wires Bluetooth walk-away auto-arm and optional return auto-disarm")
    func coordinatorIntegration() {
        let suiteName = "com.pupil.tests.bluetooth.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: defaults)
        settings.exitDelaySeconds = 0
        settings.bluetoothProximityEnabled = true
        settings.trustedBluetoothDeviceUUID = UUID().uuidString
        settings.trustedBluetoothDeviceName = "Test iPhone"
        settings.bluetoothAutoDisarmEnabled = false

        let coordinator = SecurityCoordinator(settings: settings)
        #expect(coordinator.state == .disarmed)

        // Walk-away triggers arming
        coordinator.bluetoothMonitor.onWalkAway?()
        #expect(coordinator.state == .armed)

        // Return does NOT disarm when bluetoothAutoDisarmEnabled is false
        coordinator.bluetoothMonitor.onReturn?()
        #expect(coordinator.state == .armed)

        // Enable auto-disarm and trigger return
        settings.bluetoothAutoDisarmEnabled = true
        coordinator.bluetoothMonitor.onReturn?()
        #expect(coordinator.state == .disarmed)
    }
}
