//
//  USBKeyMonitor.swift
//  Pupil
//
//  Event-driven native IOKit USB hotplug monitor (IOUSBHostDevice) with
//  deterministic test-injection hooks and zero polling.
//

import Foundation
import IOKit
import Observation

@MainActor
public protocol USBDeviceMonitoring: AnyObject {
    var isMonitoring: Bool { get }
    var connectedDevicesProvider: () -> [USBDeviceDescriptor] { get set }
    var onUSBEvent: ((USBDeviceEvent) -> Void)? { get set }
    func startMonitoring()
    func stopMonitoring()
}

private let usbMatchedCallback: IOServiceMatchingCallback = { refCon, iterator in
    guard let refCon else { return }
    let session = Unmanaged<USBIOKitSession>.fromOpaque(refCon).takeUnretainedValue()
    session.handleNotification(iterator: iterator, isConnected: true)
}

private let usbTerminatedCallback: IOServiceMatchingCallback = { refCon, iterator in
    guard let refCon else { return }
    let session = Unmanaged<USBIOKitSession>.fromOpaque(refCon).takeUnretainedValue()
    session.handleNotification(iterator: iterator, isConnected: false)
}

private final class USBIOKitSession: @unchecked Sendable {
    private weak var monitor: USBKeyMonitor?
    private let queue = DispatchQueue(label: "com.pupil.usb.monitor", qos: .userInitiated)
    private let lock = NSLock()
    private var isInvalidated = false
    private var notificationPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var retainedRefCon: UnsafeMutableRawPointer?

    init(monitor: USBKeyMonitor) {
        self.monitor = monitor
    }

    func start() -> Bool {
        lock.lock()
        guard !isInvalidated, notificationPort == nil else {
            lock.unlock()
            return notificationPort != nil
        }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            lock.unlock()
            return false
        }
        IONotificationPortSetDispatchQueue(port, queue)

        let refCon = Unmanaged.passRetained(self).toOpaque()
        var localMatched: io_iterator_t = 0
        var localTerminated: io_iterator_t = 0

        let matchedResult: kern_return_t
        if let matchedDict = IOServiceMatching("IOUSBHostDevice") {
            matchedResult = IOServiceAddMatchingNotification(
                port,
                kIOMatchedNotification,
                matchedDict,
                usbMatchedCallback,
                refCon,
                &localMatched
            )
        } else {
            matchedResult = KERN_FAILURE
        }

        let terminatedResult: kern_return_t
        if let terminatedDict = IOServiceMatching("IOUSBHostDevice") {
            terminatedResult = IOServiceAddMatchingNotification(
                port,
                kIOTerminatedNotification,
                terminatedDict,
                usbTerminatedCallback,
                refCon,
                &localTerminated
            )
        } else {
            terminatedResult = KERN_FAILURE
        }

        guard matchedResult == KERN_SUCCESS && terminatedResult == KERN_SUCCESS else {
            if localMatched != 0 { IOObjectRelease(localMatched) }
            if localTerminated != 0 { IOObjectRelease(localTerminated) }
            IONotificationPortDestroy(port)
            lock.unlock()
            Unmanaged<USBIOKitSession>.fromOpaque(refCon).release()
            return false
        }

        self.notificationPort = port
        self.matchedIterator = localMatched
        self.terminatedIterator = localTerminated
        self.retainedRefCon = refCon
        lock.unlock()

        // Mandatory initial drain on both iterators to arm kernel notifications
        // without emitting spurious events for already-connected hardware.
        if localMatched != 0 {
            _ = USBKeyMonitor.drainDescriptors(from: localMatched)
        }
        if localTerminated != 0 {
            _ = USBKeyMonitor.drainDescriptors(from: localTerminated)
        }
        return true
    }

    func stop() {
        lock.lock()
        guard !isInvalidated else {
            lock.unlock()
            return
        }
        isInvalidated = true
        let port = notificationPort
        let matched = matchedIterator
        let terminated = terminatedIterator
        let refCon = retainedRefCon

        notificationPort = nil
        matchedIterator = 0
        terminatedIterator = 0
        retainedRefCon = nil
        lock.unlock()

        if matched != 0 {
            IOObjectRelease(matched)
        }
        if terminated != 0 {
            IOObjectRelease(terminated)
        }
        if let port {
            IONotificationPortDestroy(port)
        }
        if let refCon {
            let sessionToRelease = Unmanaged<USBIOKitSession>.fromOpaque(refCon).takeUnretainedValue()
            queue.async {
                Unmanaged.passUnretained(sessionToRelease).release()
            }
        }
    }

    func handleNotification(iterator: io_iterator_t, isConnected: Bool) {
        let descriptors = USBKeyMonitor.drainDescriptors(from: iterator)
        guard !descriptors.isEmpty else { return }

        lock.lock()
        let invalidated = isInvalidated
        lock.unlock()
        guard !invalidated else { return }

        let events = descriptors.map { descriptor in
            isConnected ? USBDeviceEvent.connected(descriptor) : USBDeviceEvent.disconnected(descriptor)
        }

        Task { @MainActor [weak monitor, self] in
            guard let monitor,
                  monitor.isMonitoring,
                  monitor.iokitSession === self else {
                return
            }
            for event in events {
                monitor.emitEvent(event)
            }
        }
    }
}

@MainActor
@Observable
public final class USBKeyMonitor: USBDeviceMonitoring {
    public private(set) var isMonitoring: Bool = false
    public var connectedDevicesProvider: () -> [USBDeviceDescriptor] = {
        USBKeyMonitor.readConnectedUSBDevices()
    }
    public var onUSBEvent: ((USBDeviceEvent) -> Void)?

    fileprivate var iokitSession: USBIOKitSession?

    public init(startImmediately: Bool = false) {
        if startImmediately {
            startMonitoring()
        }
    }

    public func startMonitoring() {
        guard !isMonitoring else { return }
        let session = USBIOKitSession(monitor: self)
        if session.start() {
            iokitSession = session
            isMonitoring = true
        } else {
            // Ensure consistent state if IOKit matching port is unavailable in restricted sandboxes.
            iokitSession = nil
            isMonitoring = false
        }
    }

    public func stopMonitoring() {
        iokitSession?.stop()
        iokitSession = nil
        isMonitoring = false
    }

    /// Injects a synthetic USB attach/detach event directly on `@MainActor` for deterministic unit testing.
    public func ingestEventForTesting(_ event: USBDeviceEvent) {
        emitEvent(event)
    }

    fileprivate func emitEvent(_ event: USBDeviceEvent) {
        onUSBEvent?(event)
    }

    // MARK: - IOKit USB Registry Inspection

    nonisolated public static func readConnectedUSBDevices() -> [USBDeviceDescriptor] {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return [] }
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        return drainDescriptors(from: iterator)
    }

    nonisolated fileprivate static func drainDescriptors(from iterator: io_iterator_t) -> [USBDeviceDescriptor] {
        var devices: [USBDeviceDescriptor] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let descriptor = extractDescriptor(from: service) {
                devices.append(descriptor)
            }
        }
        return devices
    }

    nonisolated public static func extractDescriptor(from service: io_service_t) -> USBDeviceDescriptor? {
        var propertiesRef: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let properties = propertiesRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        guard let vendorNum = properties["idVendor"] as? NSNumber,
              let productNum = properties["idProduct"] as? NSNumber else {
            return nil
        }

        let vendorID = vendorNum.uint16Value
        let productID = productNum.uint16Value
        let serialNumber = (properties["kUSBSerialNumberString"] as? String)
            ?? (properties["USB Serial Number"] as? String)
        let productName = (properties["kUSBProductString"] as? String)
            ?? (properties["USB Product Name"] as? String)
        let vendorName = (properties["kUSBVendorString"] as? String)
            ?? (properties["USB Vendor Name"] as? String)
        let locationID = (properties["locationID"] as? NSNumber)?.uint32Value
        let deviceClass = (properties["bDeviceClass"] as? NSNumber)?.uint8Value
        let isBuiltIn = parseBuiltInFlag(properties["BuiltIn"] ?? properties["built-in"])

        var entryID: UInt64 = 0
        let registryEntryID: UInt64? = IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS
            ? entryID
            : nil

        return USBDeviceDescriptor(
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            productName: productName,
            vendorName: vendorName,
            locationID: locationID,
            deviceClass: deviceClass,
            isBuiltIn: isBuiltIn,
            registryEntryID: registryEntryID
        )
    }

    nonisolated private static func parseBuiltInFlag(_ raw: Any?) -> Bool {
        if let flag = raw as? Bool {
            return flag
        }
        if let number = raw as? NSNumber {
            return number.boolValue
        }
        if let data = raw as? Data, let first = data.first {
            return first != 0
        }
        return false
    }
}
