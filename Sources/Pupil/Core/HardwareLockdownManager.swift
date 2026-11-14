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
            app.presentationOptions = [
                .disableProcessSwitching,
                .disableForceQuit,
                .disableSessionTermination,
                .disableHideApplication,
                .hideDock,
                .hideMenuBar
            ]
        }
        isLockdownActive = true
    }

    public func release() {
        if let app = NSApp {
            app.presentationOptions = []
        }
        isLockdownActive = false
    }
}
