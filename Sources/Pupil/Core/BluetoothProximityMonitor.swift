//
//  BluetoothProximityMonitor.swift
//  Pupil
//
//  Bluetooth Low Energy proximity monitor with rolling RSSI smoothing and hysteresis
//  for walk-away auto-arming and optional return auto-disarming.
//

import CoreBluetooth
import Foundation
import Observation

public struct DiscoveredDevice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var rssi: Int
    public var lastSeen: Date

    public init(id: UUID, name: String, rssi: Int, lastSeen: Date = Date()) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.lastSeen = lastSeen
    }
}

public enum ProximityEvent: Equatable, Sendable {
    case walkAway
    case returned
}

/// Pure, hardware-independent RSSI smoothing and hysteresis evaluator.
public struct ProximityHysteresisEvaluator: Sendable {
    public let walkAwayRSSIThreshold: Double
    public let returnRSSIThreshold: Double
    public let unseenTimeoutSeconds: TimeInterval
    public let returnDwellSeconds: TimeInterval
    public let smoothingWindowSize: Int

    public private(set) var recentSamples: [Double] = []
    public private(set) var smoothedRSSI: Double?
    public private(set) var isAway: Bool = false
    public private(set) var lastSeen: Date?
    private var returnCandidateStart: Date?

    public init(
        walkAwayRSSIThreshold: Double = -82.0,
        returnRSSIThreshold: Double = -65.0,
        unseenTimeoutSeconds: TimeInterval = 6.0,
        returnDwellSeconds: TimeInterval = 2.0,
        smoothingWindowSize: Int = 4
    ) {
        self.walkAwayRSSIThreshold = walkAwayRSSIThreshold
        self.returnRSSIThreshold = returnRSSIThreshold
        self.unseenTimeoutSeconds = unseenTimeoutSeconds
        self.returnDwellSeconds = returnDwellSeconds
        self.smoothingWindowSize = max(1, smoothingWindowSize)
    }

    public mutating func reset() {
        recentSamples.removeAll()
        smoothedRSSI = nil
        isAway = false
        lastSeen = nil
        returnCandidateStart = nil
    }

    /// Ingests an RSSI reading (in dBm) at `date` and returns a transition event if hysteresis thresholds are crossed.
    @discardableResult
    public mutating func ingest(rssi: Int, at date: Date = Date()) -> ProximityEvent? {
        // CoreBluetooth reports 127 when RSSI is unavailable.
        guard rssi < 127, rssi > -128 else { return nil }

        lastSeen = date
        recentSamples.append(Double(rssi))
        if recentSamples.count > smoothingWindowSize {
            recentSamples.removeFirst(recentSamples.count - smoothingWindowSize)
        }
        let smoothed = recentSamples.reduce(0, +) / Double(recentSamples.count)
        smoothedRSSI = smoothed

        if !isAway {
            if smoothed < walkAwayRSSIThreshold {
                isAway = true
                returnCandidateStart = nil
                return .walkAway
            }
            return nil
        } else {
            if smoothed > returnRSSIThreshold {
                if let start = returnCandidateStart {
                    if date.timeIntervalSince(start) > returnDwellSeconds {
                        isAway = false
                        returnCandidateStart = nil
                        return .returned
                    }
                } else {
                    returnCandidateStart = date
                }
            } else {
                returnCandidateStart = nil
            }
            return nil
        }
    }

    /// Evaluates whether the tracked device has been unseen for longer than `unseenTimeoutSeconds`.
    @discardableResult
    public mutating func evaluateTimeout(at date: Date = Date()) -> ProximityEvent? {
        guard !isAway, let lastSeen else { return nil }
        if date.timeIntervalSince(lastSeen) > unseenTimeoutSeconds {
            isAway = true
            returnCandidateStart = nil
            return .walkAway
        }
        return nil
    }
}

@MainActor
@Observable
public final class BluetoothProximityMonitor: NSObject, CBCentralManagerDelegate {
    public private(set) var discoveredDevices: [DiscoveredDevice] = []
    public private(set) var isScanning: Bool = false
    public private(set) var bluetoothState: CBManagerState = .unknown
    public private(set) var trackedDeviceRSSI: Double?
    public private(set) var isTrackedDeviceAway: Bool = false

    public var targetDeviceUUID: UUID?
    public var onWalkAway: (() -> Void)?
    public var onReturn: (() -> Void)?

    private var centralManager: CBCentralManager?
    private var evaluator = ProximityHysteresisEvaluator()
    private var timeoutTimer: Timer?
    private var shouldScanWhenPoweredOn = false

    public override init() {
        super.init()
    }

    public func startScanning() {
        ensureCentralManager()
        shouldScanWhenPoweredOn = true
        beginScanIfPoweredOn()
    }

    public func stopScanning() {
        shouldScanWhenPoweredOn = false
        centralManager?.stopScan()
        isScanning = false
        stopTimeoutTimer()
    }

    public func startMonitoring(deviceUUID: UUID) {
        if targetDeviceUUID != deviceUUID {
            targetDeviceUUID = deviceUUID
            resetEvaluator()
        }
        startScanning()
        startTimeoutTimer()
    }

    public func stopMonitoring() {
        targetDeviceUUID = nil
        resetEvaluator()
        stopScanning()
    }

    public func resetEvaluator() {
        evaluator.reset()
        trackedDeviceRSSI = nil
        isTrackedDeviceAway = false
    }

    private func ensureCentralManager() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    private func beginScanIfPoweredOn() {
        guard let central = centralManager, central.state == .poweredOn, shouldScanWhenPoweredOn else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    private func startTimeoutTimer() {
        stopTimeoutTimer()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkUnseenTimeout()
            }
        }
    }

    private func stopTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    private func checkUnseenTimeout() {
        guard targetDeviceUUID != nil else { return }
        if let event = evaluator.evaluateTimeout(at: Date()), event == .walkAway {
            isTrackedDeviceAway = evaluator.isAway
            onWalkAway?()
        }
    }

    private func handleStateUpdate(_ state: CBManagerState) {
        bluetoothState = state
        if state == .poweredOn {
            beginScanIfPoweredOn()
        } else {
            isScanning = false
        }
    }

    private func handleDiscoveredPeripheral(id: UUID, name: String, rssi: Int, at date: Date) {
        guard rssi < 127, rssi > -128 else { return }

        if let idx = discoveredDevices.firstIndex(where: { $0.id == id }) {
            discoveredDevices[idx].rssi = rssi
            discoveredDevices[idx].lastSeen = date
            if !name.isEmpty && discoveredDevices[idx].name == "Unnamed Device" {
                discoveredDevices[idx].name = name
            }
        } else {
            let displayName = name.isEmpty ? "Unnamed Device" : name
            discoveredDevices.append(DiscoveredDevice(id: id, name: displayName, rssi: rssi, lastSeen: date))
        }
        discoveredDevices.sort { $0.rssi > $1.rssi }

        if let target = targetDeviceUUID, target == id {
            let event = evaluator.ingest(rssi: rssi, at: date)
            trackedDeviceRSSI = evaluator.smoothedRSSI
            isTrackedDeviceAway = evaluator.isAway
            switch event {
            case .walkAway:
                onWalkAway?()
            case .returned:
                onReturn?()
            case .none:
                break
            }
        }
    }

    // MARK: - CBCentralManagerDelegate

    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor [weak self] in
            self?.handleStateUpdate(state)
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advName ?? ""
        let rssiValue = RSSI.intValue
        let now = Date()
        Task { @MainActor [weak self] in
            self?.handleDiscoveredPeripheral(id: id, name: name, rssi: rssiValue, at: now)
        }
    }
}
