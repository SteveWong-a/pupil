import CoreAudio
import Foundation
import Testing
@testable import Pupil

private final class MockAudioHardwareBackend: AudioHardwareBackend, @unchecked Sendable {
    private let lock = NSLock()
    var currentDefaultDevice: AudioDeviceID
    var builtInDevice: AudioDeviceID?
    var mutedByDevice: [AudioDeviceID: Bool]
    var volumeByDevice: [AudioDeviceID: Float]

    init(
        defaultDevice: AudioDeviceID,
        builtInDevice: AudioDeviceID?,
        mutedByDevice: [AudioDeviceID: Bool],
        volumeByDevice: [AudioDeviceID: Float]
    ) {
        self.currentDefaultDevice = defaultDevice
        self.builtInDevice = builtInDevice
        self.mutedByDevice = mutedByDevice
        self.volumeByDevice = volumeByDevice
    }

    func defaultOutputDeviceID() -> AudioDeviceID? {
        lock.lock()
        defer { lock.unlock() }
        return currentDefaultDevice
    }

    func setDefaultOutputDeviceID(_ deviceID: AudioDeviceID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        currentDefaultDevice = deviceID
        return true
    }

    func builtInSpeakerDeviceID() -> AudioDeviceID? {
        lock.lock()
        defer { lock.unlock() }
        return builtInDevice
    }

    func isMuted(deviceID: AudioDeviceID) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return mutedByDevice[deviceID]
    }

    func setMuted(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        mutedByDevice[deviceID] = muted
        return true
    }

    func virtualMainVolume(deviceID: AudioDeviceID) -> Float? {
        lock.lock()
        defer { lock.unlock() }
        return volumeByDevice[deviceID]
    }

    func setVirtualMainVolume(_ volume: Float, deviceID: AudioDeviceID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        volumeByDevice[deviceID] = volume
        return true
    }
}

@Suite("System Audio & Environment Preset Tests", .serialized)
struct SystemAudioAndEnvironmentTests {
    @MainActor
    private func makeIsolatedSettings() -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.audio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    @Test("EnvironmentPreset snapping and custom detection")
    @MainActor
    func testEnvironmentPresetSnappingAndCustomDetection() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Defaults
        #expect(settings.sirenSpeakerOverrideEnabled == true)
        #expect(settings.sirenOverrideVolume == 0.80)
        #expect(settings.activeEnvironmentPreset == .cafe)

        // Exact preset values
        settings.sirenOverrideVolume = 0.45
        #expect(settings.activeEnvironmentPreset == .quietLibrary)

        settings.sirenOverrideVolume = 0.80
        #expect(settings.activeEnvironmentPreset == .cafe)

        settings.sirenOverrideVolume = 1.00
        #expect(settings.activeEnvironmentPreset == .busyPark)

        // Within 0.02 tolerance snaps to preset
        settings.sirenOverrideVolume = 0.465
        #expect(settings.activeEnvironmentPreset == .quietLibrary)

        settings.sirenOverrideVolume = 0.785
        #expect(settings.activeEnvironmentPreset == .cafe)

        settings.sirenOverrideVolume = 0.985
        #expect(settings.activeEnvironmentPreset == .busyPark)

        // Outside tolerance resolves to .custom
        settings.sirenOverrideVolume = 0.62
        #expect(settings.activeEnvironmentPreset == .custom)

        settings.sirenOverrideVolume = 0.25
        #expect(settings.activeEnvironmentPreset == .custom)

        // Clamping bounds (0.10...1.00)
        settings.sirenOverrideVolume = 0.01
        #expect(settings.sirenOverrideVolume == 0.10)
        #expect(settings.activeEnvironmentPreset == .custom)

        settings.sirenOverrideVolume = 1.50
        #expect(settings.sirenOverrideVolume == 1.00)
        #expect(settings.activeEnvironmentPreset == .busyPark)

        // Persistence round-trip
        settings.sirenSpeakerOverrideEnabled = false
        settings.sirenOverrideVolume = 0.55
        let reloaded = PupilSettings(defaults: defaults)
        #expect(reloaded.sirenSpeakerOverrideEnabled == false)
        #expect(reloaded.sirenOverrideVolume == 0.55)
        #expect(reloaded.activeEnvironmentPreset == .custom)
    }

    @Test("SystemAudioController snapshot, override, clamping, and restore")
    func testSystemAudioControllerSnapshotAndRestore() {
        let headphonesID: AudioDeviceID = 42
        let builtInSpeakerID: AudioDeviceID = 7

        let backend = MockAudioHardwareBackend(
            defaultDevice: headphonesID,
            builtInDevice: builtInSpeakerID,
            mutedByDevice: [headphonesID: true, builtInSpeakerID: true],
            volumeByDevice: [headphonesID: 0.25, builtInSpeakerID: 0.30]
        )

        let controller = SystemAudioController(backend: backend)
        #expect(controller.hasActiveSnapshot == false)

        // Override switches to built-in speakers, unmutes, and sets volume
        controller.forceBuiltInSpeakers(volume: 0.85)
        #expect(controller.hasActiveSnapshot == true)
        #expect(controller.currentSnapshot == SystemAudioSnapshot(deviceID: headphonesID, wasMuted: true, volume: 0.25))
        #expect(backend.defaultOutputDeviceID() == builtInSpeakerID)
        #expect(backend.isMuted(deviceID: builtInSpeakerID) == false)
        #expect(backend.virtualMainVolume(deviceID: builtInSpeakerID) == 0.85)

        // Second override call must preserve original snapshot and clamp volume
        controller.forceBuiltInSpeakers(volume: 0.02)
        #expect(controller.currentSnapshot == SystemAudioSnapshot(deviceID: headphonesID, wasMuted: true, volume: 0.25))
        #expect(backend.virtualMainVolume(deviceID: builtInSpeakerID) == 0.10)

        controller.forceBuiltInSpeakers(volume: 1.50)
        #expect(backend.virtualMainVolume(deviceID: builtInSpeakerID) == 1.00)

        // Restore brings back exact prior device, mute state, and volume
        controller.restoreIfNeeded()
        #expect(controller.hasActiveSnapshot == false)
        #expect(controller.currentSnapshot == nil)
        #expect(backend.defaultOutputDeviceID() == headphonesID)
        #expect(backend.isMuted(deviceID: headphonesID) == true)
        #expect(backend.virtualMainVolume(deviceID: headphonesID) == 0.25)

        // Calling restoreIfNeeded() again is a safe no-op
        _ = backend.setVirtualMainVolume(0.50, deviceID: headphonesID)
        controller.restoreIfNeeded()
        #expect(backend.virtualMainVolume(deviceID: headphonesID) == 0.50)
    }
}
