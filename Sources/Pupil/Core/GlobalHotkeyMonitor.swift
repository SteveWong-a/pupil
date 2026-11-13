//
//  GlobalHotkeyMonitor.swift
//  Pupil
//
//  Global and local NSEvent keyDown monitor for the ⌃⌥⌘L arm/disarm shortcut.
//

import AppKit
import Foundation

@MainActor
public final class GlobalHotkeyMonitor {
    /// Carbon virtual key code for ANSI 'L'.
    public static let armDisarmKeyCode: UInt16 = 37
    public static let requiredModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

    private weak var coordinator: SecurityCoordinator?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init(coordinator: SecurityCoordinator) {
        self.coordinator = coordinator
    }

    public func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            Task { @MainActor [weak self] in
                guard let self, let coordinator = self.coordinator else { return }
                _ = Self.handleKeyEvent(keyCode: keyCode, modifierFlags: flags, coordinator: coordinator)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let coordinator = self.coordinator else { return event }
            if Self.handleKeyEvent(keyCode: event.keyCode, modifierFlags: event.modifierFlags, coordinator: coordinator) {
                return nil
            }
            return event
        }
    }

    public func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    public static func matchesArmDisarmShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard keyCode == armDisarmKeyCode else { return false }
        let relevant = modifierFlags.intersection([.control, .option, .command, .shift])
        return relevant == requiredModifiers
    }

    @discardableResult
    public static func handleKeyEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        coordinator: SecurityCoordinator
    ) -> Bool {
        guard coordinator.settings.globalArmShortcutEnabled else { return false }
        guard matchesArmDisarmShortcut(keyCode: keyCode, modifierFlags: modifierFlags) else { return false }
        performToggle(on: coordinator)
        return true
    }

    public static func performToggle(on coordinator: SecurityCoordinator) {
        switch coordinator.state {
        case .disarmed:
            coordinator.startArming()
        case .arming:
            coordinator.cancelArmingDuringExitDelay()
        case .armed, .tamperPending, .alarm:
            coordinator.requestInteractiveUnlock()
        }
    }
}
