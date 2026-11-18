import AppKit
import Foundation
import Testing
@testable import Pupil

@Suite("Hardware Lockdown Tests", .serialized)
struct HardwareLockdownTests {
    @MainActor
    private func makeIsolatedSettings() -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.lockdown.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    @Test("HardwareLockdownManager engage and release update isLockdownActive safely")
    @MainActor
    func testEngageAndRelease() {
        let manager = HardwareLockdownManager.shared
        manager.release()
        #expect(manager.isLockdownActive == false)

        manager.engage()
        #expect(manager.isLockdownActive == true)
        if let app = NSApp {
            if SecurityCoordinator.isRunningUnderTests {
                #expect(app.presentationOptions == [])
            } else {
                #expect(app.presentationOptions.contains(.disableProcessSwitching))
                #expect(app.presentationOptions.contains(.disableForceQuit))
                #expect(app.presentationOptions.contains(.disableSessionTermination))
                #expect(app.presentationOptions.contains(.disableHideApplication))
                #expect(app.presentationOptions.contains(.hideDock))
                #expect(app.presentationOptions.contains(.hideMenuBar))
            }
        }

        manager.release()
        #expect(manager.isLockdownActive == false)
        if let app = NSApp {
            #expect(app.presentationOptions == [])
        }
    }

    @Test("hardwareLockdownEnabled defaults to true and persists across PupilSettings instances")
    @MainActor
    func testHardwareLockdownEnabledPersistence() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(settings.hardwareLockdownEnabled == true)

        settings.hardwareLockdownEnabled = false
        let reloadedFalse = PupilSettings(defaults: defaults)
        #expect(reloadedFalse.hardwareLockdownEnabled == false)

        reloadedFalse.hardwareLockdownEnabled = true
        let reloadedTrue = PupilSettings(defaults: defaults)
        #expect(reloadedTrue.hardwareLockdownEnabled == true)
    }
}
