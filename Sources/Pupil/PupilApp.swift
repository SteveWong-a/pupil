//
//  PupilApp.swift
//  Pupil
//
//  Main entry point, NSApplicationDelegate, and NSStatusItem menu bar integration,
//  modeled directly after Glance's glanceApp.swift.
//

import AppKit
import SwiftUI

@main
struct PupilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        settingsWindow
    }

    private var settingsWindow: some Scene {
        let open = openWindow
        let delegate = appDelegate
        return Window("Pupil Settings", id: "settings") {
            SettingsWindowView(coordinator: appDelegate.coordinator)
                .onAppear {
                    delegate.bindOpenWindowAction { open(id: "settings") }
                }
        }
        .defaultSize(SettingsMetrics.windowSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    public let coordinator = SecurityCoordinator()
    private var notchOverlayController: NotchOverlayController?
    private var screenShieldController: ScreenShieldController?
    private var globalHotkeyMonitor: GlobalHotkeyMonitor?

    private var statusItem: NSStatusItem?
    private var trayPopover: NSPopover?
    private var trayMenu: NSMenu?
    private var statusHeaderItem: NSMenuItem?
    private var toggleArmItem: NSMenuItem?
    private var powerInfoItem: NSMenuItem?
    private var openSettingsWindowAction: (() -> Void)?

    public func bindOpenWindowAction(_ action: @escaping () -> Void) {
        openSettingsWindowAction = action
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItemIfNeeded()

        let overlay = NotchOverlayController(coordinator: coordinator)
        self.notchOverlayController = overlay

        let shield = ScreenShieldController(coordinator: coordinator)
        self.screenShieldController = shield

        let hotkeyMonitor = GlobalHotkeyMonitor(coordinator: coordinator)
        hotkeyMonitor.start()
        self.globalHotkeyMonitor = hotkeyMonitor

        coordinator.onStateChanged = { [weak self] _ in
            self?.refreshStatusItemIconAndMenu()
            self?.notchOverlayController?.syncWithCoordinator()
            self?.screenShieldController?.syncWithCoordinator()
        }
        coordinator.onNotchUpdateNeeded = { [weak self] in
            self?.refreshStatusItemIconAndMenu()
            self?.notchOverlayController?.syncWithCoordinator()
            self?.screenShieldController?.syncWithCoordinator()
        }

        PupilSettings.shared.bindMenuBarVisibility { [weak self] visible in
            self?.setMenuBarVisibility(visible)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.pupil.test.previewShield"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.coordinator.previewScreenShield(durationSeconds: 4.5)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.pupil.test.simulateGaze"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.coordinator.simulateGazeWarning()
            }
        }

        // Only reveal settings window on launch if explicitly requested via command line flag
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.revealSettingsWindow()
            }
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        revealSettingsWindow()
        return true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Prevent force-quitting via Cmd+Q while armed unless the user disarms first
        if coordinator.isMonitoring {
            if coordinator.state == .arming {
                coordinator.cancelArmingDuringExitDelay()
                return .terminateNow
            }
            revealSettingsWindow()
            screenShieldController?.syncWithCoordinator()
            NSSound.beep()
            return .terminateCancel
        }
        return .terminateNow
    }

    private func setMenuBarVisibility(_ isVisible: Bool) {
        if isVisible {
            installStatusItemIfNeeded()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "com.pupil.security.menubar"
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "Pupil — Disarmed", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        self.statusHeaderItem = header

        let powerRow = NSMenuItem(title: "Power: Checking…", action: nil, keyEquivalent: "")
        powerRow.isEnabled = false
        menu.addItem(powerRow)
        self.powerInfoItem = powerRow

        menu.addItem(.separator())

        let armItem = NSMenuItem(title: "Arm Pupil", action: #selector(toggleArmState), keyEquivalent: "a")
        armItem.target = self
        menu.addItem(armItem)
        self.toggleArmItem = armItem

        let previewEyeItem = NSMenuItem(
            title: "Preview Notch Gaze Deterrent",
            action: #selector(triggerNotchPreview),
            keyEquivalent: "e"
        )
        previewEyeItem.target = self
        previewEyeItem.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)
        menu.addItem(previewEyeItem)

        let previewShieldItem = NSMenuItem(
            title: "Preview Screen Shield Blur",
            action: #selector(triggerShieldPreview),
            keyEquivalent: "b"
        )
        previewShieldItem.target = self
        previewShieldItem.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
        menu.addItem(previewShieldItem)

        let simTamperItem = NSMenuItem(
            title: "Simulate Tamper Countdown",
            action: #selector(triggerSimulatedTamper),
            keyEquivalent: "t"
        )
        simTamperItem.target = self
        simTamperItem.image = NSImage(systemSymbolName: "bolt.trianglebadge.exclamationmark.fill", accessibilityDescription: nil)
        menu.addItem(simTamperItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Pupil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        menu.addItem(quitItem)

        self.trayMenu = menu
        self.statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                coordinator: coordinator,
                onOpenSettings: { [weak self] in self?.revealSettingsWindow() },
                onQuit: { NSApp.terminate(nil) },
                onClosePopover: { [weak self] in self?.trayPopover?.performClose(nil) }
            )
        )
        self.trayPopover = popover

        refreshStatusItemIconAndMenu()
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            trayPopover?.performClose(nil)
            if let menu = trayMenu, let item = statusItem {
                item.menu = menu
                item.button?.performClick(nil)
                item.menu = nil
            }
            return
        }

        guard let popover = trayPopover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            refreshStatusItemIconAndMenu()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        refreshStatusItemIconAndMenu()
    }

    private func refreshStatusItemIconAndMenu() {
        if let button = statusItem?.button {
            let icon = MenuBarIconFactory.makeStatusIcon(
                state: coordinator.state,
                isGazeActive: coordinator.isGazeWarningActive
            )
            button.image = icon
            button.imagePosition = .imageLeft

            if coordinator.state == .arming || coordinator.state == .tamperPending {
                statusItem?.length = NSStatusItem.variableLength
                button.title = " \(coordinator.countdownSecondsRemaining)s"
            } else {
                statusItem?.length = NSStatusItem.squareLength
                button.title = ""
            }
        }

        statusHeaderItem?.title = "Pupil — \(coordinator.state.label)"
        let acStatus = coordinator.powerMonitor.isOnACPower ? "AC Charger Connected" : "On Battery"
        let gazeStatus = coordinator.settings.gazeDetectionEnabled ? "Vision Iris On" : "Vision Off"
        powerInfoItem?.title = "\(acStatus) · \(gazeStatus)"

        switch coordinator.state {
        case .disarmed:
            toggleArmItem?.title = "Arm Pupil (\(coordinator.settings.exitDelaySeconds)s delay)"
            toggleArmItem?.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)
        case .arming:
            toggleArmItem?.title = "Cancel Arming (\(coordinator.countdownSecondsRemaining)s)"
            toggleArmItem?.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        case .armed, .tamperPending, .alarm:
            toggleArmItem?.title = "Disarm Pupil…"
            toggleArmItem?.image = NSImage(systemSymbolName: "lock.open.fill", accessibilityDescription: nil)
        }
    }

    @objc private func toggleArmState() {
        switch coordinator.state {
        case .disarmed:
            coordinator.startArming()
        case .arming:
            coordinator.cancelArmingDuringExitDelay()
        case .armed, .tamperPending, .alarm:
            Task {
                let unlocked = await coordinator.disarmWithTouchID()
                if !unlocked {
                    revealSettingsWindow()
                }
            }
        }
    }

    @objc private func triggerNotchPreview() {
        coordinator.simulateGazeWarning()
    }

    @objc private func triggerShieldPreview() {
        coordinator.previewScreenShield()
    }

    @objc private func triggerSimulatedTamper() {
        if coordinator.state == .disarmed {
            coordinator.startArming(immediate: true)
        }
        coordinator.triggerTamper(source: .manualTest, immediateAlarm: false, simulated: true)
    }

    @objc private func openSettingsWindow() {
        revealSettingsWindow()
    }

    public func revealSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openSettingsWindowAction?()
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain && !(window is ScreenShieldWindow) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow.canBecomeMain else { return }
        let stillOpen = NSApp.windows.contains { $0 !== closingWindow && $0.canBecomeMain && $0.isVisible }
        if !stillOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
