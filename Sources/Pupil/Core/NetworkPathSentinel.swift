//
//  NetworkPathSentinel.swift
//  Pupil
//
//  Real-time network interface and connectivity transition sentinel.
//  Detects sudden Wi-Fi drops, offline transitions, and interface downgrades.
//

import Foundation
import Network
import Observation

public enum NetworkInterfaceKind: String, Codable, Sendable, Equatable {
    case wifi = "Wi-Fi"
    case wiredEthernet = "Ethernet"
    case cellular = "Cellular"
    case other = "Other"
    case none = "Offline"
}

public struct NetworkSnapshot: Sendable, Equatable {
    public let isSatisfied: Bool
    public let primaryInterface: NetworkInterfaceKind

    public init(isSatisfied: Bool, primaryInterface: NetworkInterfaceKind) {
        self.isSatisfied = isSatisfied
        self.primaryInterface = primaryInterface
    }
}

public enum NetworkTransitionEvent: Sendable, Equatable {
    /// Network connectivity was lost completely (e.g., Wi-Fi/Ethernet -> Offline).
    case connectivityLost(previous: NetworkInterfaceKind)
    /// Primary interface downgraded/changed away from Wi-Fi or Ethernet (e.g., `wifi` -> `other`).
    case interfaceChanged(from: NetworkInterfaceKind, to: NetworkInterfaceKind)
    /// Connectivity was restored after being offline.
    case connectivityRestored(current: NetworkInterfaceKind)
}

public struct NetworkTransitionEvaluator: Sendable {
    public private(set) var lastSnapshot: NetworkSnapshot?

    public init(initialSnapshot: NetworkSnapshot? = nil) {
        self.lastSnapshot = initialSnapshot
    }

    public mutating func reset() {
        self.lastSnapshot = nil
    }

    /// Evaluates a new network snapshot against the previous snapshot and returns a transition event if notable.
    /// - Initial baseline ingestion returns `nil`.
    /// - If previously satisfied (`.wifi`, `.wiredEthernet`, `.cellular`, `.other`) and now `!next.isSatisfied` or `next.primaryInterface == .none`, returns `.connectivityLost(previous: prev.primaryInterface)`.
    /// - If previously `.wifi` or `.wiredEthernet` and now satisfied on `.other`, returns `.interfaceChanged(from: prev.primaryInterface, to: next.primaryInterface)`.
    /// - If previously `!prev.isSatisfied` (or `.none`) and now `next.isSatisfied && next.primaryInterface != .none`, returns `.connectivityRestored(current: next.primaryInterface)`.
    public mutating func ingest(_ next: NetworkSnapshot) -> NetworkTransitionEvent? {
        guard let prev = lastSnapshot else {
            lastSnapshot = next
            return nil
        }
        lastSnapshot = next

        let prevSatisfied = prev.isSatisfied && prev.primaryInterface != .none
        let nextSatisfied = next.isSatisfied && next.primaryInterface != .none

        // Connectivity lost: previously satisfied and now offline
        if prevSatisfied && !nextSatisfied {
            return .connectivityLost(previous: prev.primaryInterface)
        }

        // Connectivity restored: previously offline and now satisfied
        if !prevSatisfied && nextSatisfied {
            return .connectivityRestored(current: next.primaryInterface)
        }

        // Interface changed: previously .wifi or .wiredEthernet and now satisfied away from them (e.g. .other or .cellular)
        if prevSatisfied && nextSatisfied {
            if (prev.primaryInterface == .wifi || prev.primaryInterface == .wiredEthernet)
                && (next.primaryInterface != .wifi && next.primaryInterface != .wiredEthernet) {
                return .interfaceChanged(from: prev.primaryInterface, to: next.primaryInterface)
            }
        }

        return nil
    }
}

@MainActor
@Observable
public final class NetworkPathSentinel {
    public private(set) var currentSnapshot: NetworkSnapshot = NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi)
    public private(set) var isMonitoring: Bool = false

    public var onTransition: ((NetworkTransitionEvent) -> Void)?

    private var evaluator = NetworkTransitionEvaluator()
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.pupil.network.sentinel", qos: .utility)

    public init() {}

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        evaluator.reset()
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = Self.makeSnapshot(from: path)
            Task { @MainActor [weak self] in
                self?.ingestSnapshot(snapshot)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        pathMonitor?.cancel()
        pathMonitor = nil
        evaluator.reset()
    }

    /// Directly callable by unit tests or `NWPathMonitor` updates on `@MainActor`.
    public func ingestSnapshot(_ snapshot: NetworkSnapshot) {
        currentSnapshot = snapshot
        if let event = evaluator.ingest(snapshot) {
            onTransition?(event)
        }
    }

    nonisolated public static func makeSnapshot(from path: NWPath) -> NetworkSnapshot {
        let satisfied = (path.status == .satisfied)
        guard satisfied else {
            return NetworkSnapshot(isSatisfied: false, primaryInterface: .none)
        }
        if path.usesInterfaceType(.wifi) {
            return NetworkSnapshot(isSatisfied: true, primaryInterface: .wifi)
        } else if path.usesInterfaceType(.wiredEthernet) {
            return NetworkSnapshot(isSatisfied: true, primaryInterface: .wiredEthernet)
        } else if path.usesInterfaceType(.cellular) {
            return NetworkSnapshot(isSatisfied: true, primaryInterface: .cellular)
        } else {
            return NetworkSnapshot(isSatisfied: true, primaryInterface: .other)
        }
    }
}
