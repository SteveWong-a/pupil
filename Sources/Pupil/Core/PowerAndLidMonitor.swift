//
//  PowerAndLidMonitor.swift
//  Pupil
//
//  Native macOS IOKit hardware sensor monitor for:
//  1. AC Charger vs. Battery power transitions (IOPSCopyPowerSourcesInfo)
//  2. Physical MacBook lid clamshell state (IOPMrootDomain -> AppleClamshellState)
//  3. System sleep/wake notifications & IOPMAssertion sleep hold during active alarms
//

import AppKit
import CoreFoundation
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import Observation

public enum PowerHardwareEvent: Sendable, Equatable {
    case chargerUnplugged
    case chargerPluggedIn
    case lidClosed
    case lidOpened
    case peripheralDisconnected
    case systemWillSleep
    case systemDidWake
}

@MainActor
@Observable
public final class PowerAndLidMonitor {
    public private(set) var isOnACPower: Bool = true
    public private(set) var isLidClosed: Bool = false
    public private(set) var isSleepAssertionActive: Bool = false
    public private(set) var connectedDisplayCount: Int = 0
    public private(set) var connectedUSBDeviceCount: Int = 0

    public var onHardwareEvent: ((PowerHardwareEvent) -> Void)?

    private var pollTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultObservers: [NSObjectProtocol] = []
    private var sleepAssertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var displaySleepAssertionID: IOPMAssertionID = IOPMAssertionID(0)

    public var isFastPolling: Bool = false {
        didSet {
            if oldValue != isFastPolling {
                startSensorTimer()
            }
        }
    }

    public init() {
        self.isOnACPower = Self.readACPowerState()
        self.isLidClosed = Self.readClamshellClosedState()
        self.connectedDisplayCount = NSScreen.screens.count
        self.connectedUSBDeviceCount = Self.readUSBDeviceCount()
        startMonitoring()
    }

    public func startMonitoring() {
        stopMonitoring()

        let wsCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pollHardwareSensors()
                    self?.onHardwareEvent?(.systemWillSleep)
                }
            }
        )
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pollHardwareSensors()
                    self?.onHardwareEvent?(.systemDidWake)
                }
            }
        )

        defaultObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pollHardwareSensors()
                }
            }
        )

        startSensorTimer()
    }

    private func startSensorTimer() {
        pollTimer?.invalidate()
        let interval: TimeInterval = isFastPolling ? 0.15 : 3.0
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollHardwareSensors()
            }
        }
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        let wsCenter = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            wsCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()
        for obs in defaultObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        defaultObservers.removeAll()
        releaseSleepHoldAssertion()
    }

    /// Holds an IOPMAssertion so macOS keeps audio, display, and sensors awake while armed or sounding the siren.
    public func acquireSleepHoldAssertion(reason: String = "Pupil Armed Security Monitoring") {
        guard !isSleepAssertionActive else { return }
        var sysID: IOPMAssertionID = IOPMAssertionID(0)
        let resSys = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &sysID
        )
        var dispID: IOPMAssertionID = IOPMAssertionID(0)
        let resDisp = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &dispID
        )
        if resSys == kIOReturnSuccess || resDisp == kIOReturnSuccess {
            sleepAssertionID = sysID
            displaySleepAssertionID = dispID
            isSleepAssertionActive = true
        }
    }

    public func releaseSleepHoldAssertion() {
        guard isSleepAssertionActive else { return }
        if sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = IOPMAssertionID(0)
        }
        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = IOPMAssertionID(0)
        }
        isSleepAssertionActive = false
    }

    private func pollHardwareSensors() {
        let currentAC = Self.readACPowerState()
        if currentAC != isOnACPower {
            isOnACPower = currentAC
            onHardwareEvent?(currentAC ? .chargerPluggedIn : .chargerUnplugged)
        }

        let currentClamshell = Self.readClamshellClosedState()
        if currentClamshell != isLidClosed {
            isLidClosed = currentClamshell
            onHardwareEvent?(currentClamshell ? .lidClosed : .lidOpened)
        }

        evaluatePeripheralCounts(
            displayCount: NSScreen.screens.count,
            usbCount: Self.readUSBDeviceCount()
        )
    }

    /// Evaluates whether a connected external display or USB peripheral was unplugged since the last observation.
    public func evaluatePeripheralCounts(displayCount: Int, usbCount: Int) {
        let disconnected = displayCount < connectedDisplayCount || usbCount < connectedUSBDeviceCount
        connectedDisplayCount = displayCount
        connectedUSBDeviceCount = usbCount
        if disconnected {
            onHardwareEvent?(.peripheralDisconnected)
        }
    }

    nonisolated public static func readUSBDeviceCount() -> Int {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return 0 }
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var count = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            count += 1
            IOObjectRelease(service)
        }
        return count
    }

    nonisolated public static func readACPowerState() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerTypeCF = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() else {
            return true
        }
        let typeString = powerTypeCF as String
        return typeString == (kIOPSACPowerValue as String)
    }

    nonisolated public static func readClamshellClosedState() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        guard let prop = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return false
        }

        if CFGetTypeID(prop) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((prop as! CFBoolean))
        }
        return false
    }
}
