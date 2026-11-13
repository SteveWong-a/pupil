import AppKit
import Foundation
import Testing
@testable import Pupil

@Suite("Mac Sentry Features Tests", .serialized)
struct MacSentryFeaturesTests {
    @MainActor
    private func makeIsolatedSettings() -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.macsentry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    @Test("Feature 1: Auto-arm on screen lock defaults false, persists, and arms when disarmed")
    @MainActor
    func testAutoArmOnScreenLock() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(settings.autoArmOnScreenLock == false)
        settings.exitDelaySeconds = 10

        let coordinator = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("1234") }

        // Disabled: screenLocked while disarmed does nothing
        coordinator.lockMonitor.onLockEvent?(.screenLocked)
        #expect(coordinator.state == .disarmed)

        // Enabled: screenLocked while disarmed starts arming without immediately triggering tamper
        settings.autoArmOnScreenLock = true
        let reloaded = PupilSettings(defaults: defaults)
        #expect(reloaded.autoArmOnScreenLock == true)

        coordinator.lockMonitor.onLockEvent?(.screenLocked)
        #expect(coordinator.state == .arming)
        #expect(coordinator.activeTamperSource == nil)

        // Cancel and test immediate arming (exitDelaySeconds == 0) does not double-trigger screenLock tamper
        coordinator.cancelArmingDuringExitDelay()
        #expect(coordinator.state == .disarmed)
        settings.exitDelaySeconds = 0
        coordinator.lockMonitor.onLockEvent?(.screenLocked)
        #expect(coordinator.state == .armed)
        #expect(coordinator.activeTamperSource == nil)

        // Subsequent screenLocked while armed still triggers tamper when .screenLock trigger is enabled
        coordinator.lockMonitor.onLockEvent?(.screenLocked)
        #expect(coordinator.state == .tamperPending)
        #expect(coordinator.activeTamperSource == .screenLocked)
    }

    @Test("Feature 2: Global shortcut (Ctrl+Opt+Cmd+L) matching and arm/disarm toggle")
    @MainActor
    func testGlobalArmShortcut() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(settings.globalArmShortcutEnabled == false)
        settings.exitDelaySeconds = 10

        #expect(GlobalHotkeyMonitor.matchesArmDisarmShortcut(
            keyCode: GlobalHotkeyMonitor.armDisarmKeyCode,
            modifierFlags: [.control, .option, .command]
        ) == true)
        #expect(GlobalHotkeyMonitor.matchesArmDisarmShortcut(
            keyCode: GlobalHotkeyMonitor.armDisarmKeyCode,
            modifierFlags: [.control, .command]
        ) == false)
        #expect(GlobalHotkeyMonitor.matchesArmDisarmShortcut(
            keyCode: GlobalHotkeyMonitor.armDisarmKeyCode,
            modifierFlags: [.control, .option, .command, .shift]
        ) == false)
        #expect(GlobalHotkeyMonitor.matchesArmDisarmShortcut(
            keyCode: 0,
            modifierFlags: [.control, .option, .command]
        ) == false)

        let coordinator = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("1234") }

        // Disabled: shortcut is ignored
        let ignored = GlobalHotkeyMonitor.handleKeyEvent(
            keyCode: GlobalHotkeyMonitor.armDisarmKeyCode,
            modifierFlags: [.control, .option, .command],
            coordinator: coordinator
        )
        #expect(ignored == false)
        #expect(coordinator.state == .disarmed)

        // Enable and verify persistence
        settings.globalArmShortcutEnabled = true
        let reloaded = PupilSettings(defaults: defaults)
        #expect(reloaded.globalArmShortcutEnabled == true)

        // Disarmed -> Arming
        let armedHandled = GlobalHotkeyMonitor.handleKeyEvent(
            keyCode: GlobalHotkeyMonitor.armDisarmKeyCode,
            modifierFlags: [.control, .option, .command],
            coordinator: coordinator
        )
        #expect(armedHandled == true)
        #expect(coordinator.state == .arming)

        // Arming -> Cancel back to Disarmed
        let cancelHandled = GlobalHotkeyMonitor.handleKeyEvent(
            keyCode: GlobalHotkeyMonitor.armDisarmKeyCode,
            modifierFlags: [.control, .option, .command],
            coordinator: coordinator
        )
        #expect(cancelHandled == true)
        #expect(coordinator.state == .disarmed)

        // Armed -> Requests interactive unlock challenge
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)
        #expect(coordinator.isInteractiveUnlockRequested == false)

        let unlockHandled = GlobalHotkeyMonitor.handleKeyEvent(
            keyCode: GlobalHotkeyMonitor.armDisarmKeyCode,
            modifierFlags: [.control, .option, .command],
            coordinator: coordinator
        )
        #expect(unlockHandled == true)
        #expect(coordinator.isInteractiveUnlockRequested == true)
    }

    @Test("Feature 4: Peripheral disconnect trigger metadata, monitor detection, and tamper escalation")
    @MainActor
    func testPeripheralDisconnectTrigger() {
        #expect(HardwareTrigger.allCases.contains(.peripheralDisconnect))
        #expect(HardwareTrigger.peripheralDisconnect.title == "Peripheral Unplug")
        #expect(HardwareTrigger.peripheralDisconnect.iconName == "cable.connector.slash")
        #expect(TamperSource.peripheralDisconnected.confidence == .strong)

        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(settings.hardwareTriggers.contains(.peripheralDisconnect))

        let monitor = PowerAndLidMonitor()
        var emittedEvents: [PowerHardwareEvent] = []
        monitor.onHardwareEvent = { event in
            emittedEvents.append(event)
        }

        // Establish baseline with 2 displays, 3 USB devices
        monitor.evaluatePeripheralCounts(displayCount: 2, usbCount: 3)
        emittedEvents.removeAll()

        // Plugging in an extra USB device does not emit disconnect
        monitor.evaluatePeripheralCounts(displayCount: 2, usbCount: 4)
        #expect(emittedEvents.isEmpty)

        // Unplugging a USB device emits .peripheralDisconnected
        monitor.evaluatePeripheralCounts(displayCount: 2, usbCount: 3)
        #expect(emittedEvents == [.peripheralDisconnected])

        // Unplugging an external display emits .peripheralDisconnected
        emittedEvents.removeAll()
        monitor.evaluatePeripheralCounts(displayCount: 1, usbCount: 3)
        #expect(emittedEvents == [.peripheralDisconnected])

        // Coordinator integration
        let coordinator = SecurityCoordinator(
            settings: settings,
            powerMonitor: monitor,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        )
        defer { coordinator.disarmWithPin("1234") }

        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        // Trigger disabled -> ignored
        settings.hardwareTriggers.remove(.peripheralDisconnect)
        coordinator.powerMonitor.onHardwareEvent?(.peripheralDisconnected)
        #expect(coordinator.state == .armed)

        // Trigger enabled -> starts tamper countdown
        settings.hardwareTriggers.insert(.peripheralDisconnect)
        coordinator.powerMonitor.onHardwareEvent?(.peripheralDisconnected)
        #expect(coordinator.state == .tamperPending)
        #expect(coordinator.activeTamperSource == .peripheralDisconnected)
    }
}
