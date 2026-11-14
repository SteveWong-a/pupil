//
//  HardwareLockdownManager.swift
//  Pupil
//
//  Engages macOS kiosk-style presentation options while the tamper/unlock shield is active.
//

import AppKit

@MainActor
public final class HardwareLockdownManager {
    public static let shared = HardwareLockdownManager()

    public private(set) var isLockdownActive = false

    private init() {}

    public func engage() {
        if let app = NSApp {
            app.setActivationPolicy(.regular)
            app.presentationOptions = [
                .disableProcessSwitching,
                .disableForceQuit,
                .disableSessionTermination,
                .disableHideApplication,
                .hideDock,
                .hideMenuBar
            ]
            app.activate(ignoringOtherApps: true)
        }
        isLockdownActive = true
    }

    public func release() {
        if let app = NSApp {
            app.presentationOptions = []
            let hasOpenMainWindow = app.windows.contains { $0.canBecomeMain && $0.isVisible && !($0 is ScreenShieldWindow) }
            if !hasOpenMainWindow {
                app.setActivationPolicy(.accessory)
            }
        }
        isLockdownActive = false
    }
}
