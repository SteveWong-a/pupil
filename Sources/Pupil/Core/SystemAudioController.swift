//
//  SystemAudioController.swift
//  Pupil
//
//  Temporarily overrides the macOS default audio output device to built-in speakers,
//  unmutes, and sets volume for the theft siren, then restores the exact prior state.
//

import AudioToolbox
import CoreAudio
import Foundation

public struct SystemAudioSnapshot: Equatable, Sendable {
    public let deviceID: AudioDeviceID
    public let wasMuted: Bool?
    public let volume: Float?

    public init(deviceID: AudioDeviceID, wasMuted: Bool?, volume: Float?) {
        self.deviceID = deviceID
        self.wasMuted = wasMuted
        self.volume = volume
    }
}

public protocol AudioHardwareBackend: Sendable {
    func defaultOutputDeviceID() -> AudioDeviceID?
    func setDefaultOutputDeviceID(_ deviceID: AudioDeviceID) -> Bool
    func builtInSpeakerDeviceID() -> AudioDeviceID?
    func isMuted(deviceID: AudioDeviceID) -> Bool?
    func setMuted(_ muted: Bool, deviceID: AudioDeviceID) -> Bool
    func virtualMainVolume(deviceID: AudioDeviceID) -> Float?
    func setVirtualMainVolume(_ volume: Float, deviceID: AudioDeviceID) -> Bool
}

public final class CoreAudioHardwareBackend: AudioHardwareBackend, @unchecked Sendable {
    public init() {}

    public func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }
        return deviceID
    }

    @discardableResult
    public func setDefaultOutputDeviceID(_ deviceID: AudioDeviceID) -> Bool {
        var targetID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &targetID
        )
        return status == noErr
    }

    public func builtInSpeakerDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return nil
        }

        return deviceIDs.first { deviceID in
            isBuiltInTransport(deviceID: deviceID) && hasOutputChannels(deviceID: deviceID)
        }
    }

    public func isMuted(deviceID: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else { return nil }
        return muted != 0
    }

    @discardableResult
    public func setMuted(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue else {
            return false
        }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }

    public func virtualMainVolume(deviceID: AudioDeviceID) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else { return nil }
        return volume
    }

    @discardableResult
    public func setVirtualMainVolume(_ volume: Float, deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue else {
            return false
        }
        var value: Float32 = volume
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }

    private func isBuiltInTransport(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType)
        return status == noErr && transportType == kAudioDeviceTransportTypeBuiltIn
    }

    private func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return false
        }
        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        let bufferList = rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
            return false
        }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }
}

public final class SystemAudioController: @unchecked Sendable {
    public static let shared = SystemAudioController()

    private let lock = NSLock()
    private let backend: any AudioHardwareBackend
    private var snapshot: SystemAudioSnapshot?
    private var activeOverrideDeviceID: AudioDeviceID?

    public init(backend: any AudioHardwareBackend = CoreAudioHardwareBackend()) {
        self.backend = backend
    }

    public var hasActiveSnapshot: Bool {
        lock.lock()
        defer { lock.unlock() }
        return snapshot != nil
    }

    public var currentSnapshot: SystemAudioSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    public func forceBuiltInSpeakers(volume: Float) {
        let clampedVolume = min(max(volume, 0.1), 1.0)

        lock.lock()
        defer { lock.unlock() }

        let currentDefault = backend.defaultOutputDeviceID()
        if snapshot == nil, let currentDefault {
            let priorMute = backend.isMuted(deviceID: currentDefault)
            let priorVolume = backend.virtualMainVolume(deviceID: currentDefault)
            snapshot = SystemAudioSnapshot(
                deviceID: currentDefault,
                wasMuted: priorMute,
                volume: priorVolume
            )
        }

        let targetDeviceID = backend.builtInSpeakerDeviceID() ?? currentDefault
        guard let targetDeviceID else { return }
        activeOverrideDeviceID = targetDeviceID

        if currentDefault != targetDeviceID {
            _ = backend.setDefaultOutputDeviceID(targetDeviceID)
        }
        _ = backend.setMuted(false, deviceID: targetDeviceID)
        _ = backend.setVirtualMainVolume(clampedVolume, deviceID: targetDeviceID)
    }

    public func updateOverrideVolume(_ volume: Float) {
        let clampedVolume = min(max(volume, 0.1), 1.0)

        lock.lock()
        if snapshot == nil {
            lock.unlock()
            forceBuiltInSpeakers(volume: clampedVolume)
            return
        }
        let deviceID = activeOverrideDeviceID ?? backend.builtInSpeakerDeviceID() ?? backend.defaultOutputDeviceID()
        if let deviceID, activeOverrideDeviceID == nil {
            activeOverrideDeviceID = deviceID
        }
        defer { lock.unlock() }

        guard let deviceID else { return }
        _ = backend.setMuted(false, deviceID: deviceID)
        _ = backend.setVirtualMainVolume(clampedVolume, deviceID: deviceID)
    }

    public func restoreIfNeeded() {
        lock.lock()
        guard let saved = snapshot else {
            activeOverrideDeviceID = nil
            lock.unlock()
            return
        }
        snapshot = nil
        activeOverrideDeviceID = nil
        lock.unlock()

        if backend.defaultOutputDeviceID() != saved.deviceID {
            _ = backend.setDefaultOutputDeviceID(saved.deviceID)
        }
        if let wasMuted = saved.wasMuted {
            _ = backend.setMuted(wasMuted, deviceID: saved.deviceID)
        }
        if let priorVolume = saved.volume {
            _ = backend.setVirtualMainVolume(priorVolume, deviceID: saved.deviceID)
        }
    }
}
