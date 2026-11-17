//
//  TrustedNetworkMonitor.swift
//  Pupil
//
//  Live system network identity observer (NWPathMonitor, CoreWLAN, CoreLocation,
//  SystemConfiguration, and BSD ARP sysctl) and @MainActor @Observable monitor.
//

import AppKit
import CoreLocation
import CoreWLAN
import Darwin
import Foundation
import Network
import Observation
import SystemConfiguration

public protocol TrustedNetworkIdentityProviding: Sendable {
    func currentLocationPermission() -> LocationPermissionState
    func requestLocationPermissionIfNeeded()
    func captureSnapshot(from path: NWPath?, at timestamp: TimeInterval) -> NetworkIdentitySnapshot
}

public struct SystemNetworkIdentityProvider: TrustedNetworkIdentityProviding, Sendable {
    public init() {}

    public func currentLocationPermission() -> LocationPermissionState {
        guard TrustedNetworkMonitor.isLiveSystemAccessEnabled else {
            return .unavailableInTest
        }
        guard CLLocationManager.locationServicesEnabled() else {
            return .servicesDisabled
        }
        switch CLLocationManager().authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorizedAlways, .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    public func requestLocationPermissionIfNeeded() {
        guard TrustedNetworkMonitor.canRequestLocationAuthorization else { return }
        guard currentLocationPermission() == .notDetermined else { return }
        CLLocationManager().requestWhenInUseAuthorization()
    }

    public func captureSnapshot(from path: NWPath?, at timestamp: TimeInterval) -> NetworkIdentitySnapshot {
        let permission = currentLocationPermission()
        let isLive = TrustedNetworkMonitor.isLiveSystemAccessEnabled

        let store = isLive ? SCDynamicStoreCreate(nil, "com.pupil.trusted-wifi" as CFString, nil, nil) : nil
        let globalIPv4 = store.flatMap { Self.readDictionary($0, key: "State:/Network/Global/IPv4") }
        let globalPrimaryIf = globalIPv4?["PrimaryInterface"] as? String

        let isSatisfied: Bool
        let primaryInterface: NetworkInterfaceKind
        if let path {
            let base = NetworkPathSentinel.makeSnapshot(from: path)
            isSatisfied = base.isSatisfied
            primaryInterface = base.primaryInterface
        } else if let globalPrimaryIf, isLive {
            isSatisfied = true
            if CWWiFiClient.shared().interface(withName: globalPrimaryIf) != nil {
                primaryInterface = .wifi
            } else {
                primaryInterface = .other
            }
        } else {
            isSatisfied = false
            primaryInterface = .none
        }

        let pathWiFiIf = path?.availableInterfaces.first(where: { $0.type == .wifi })?.name
        let candidateIfName = pathWiFiIf ?? globalPrimaryIf ?? (primaryInterface == .wifi ? "en0" : nil)

        guard isSatisfied, primaryInterface == .wifi else {
            return NetworkIdentitySnapshot(
                isSatisfied: isSatisfied,
                primaryInterface: primaryInterface,
                interfaceName: candidateIfName,
                locationPermission: permission,
                capturedAt: timestamp
            )
        }

        guard isLive else {
            return NetworkIdentitySnapshot(
                isSatisfied: true,
                primaryInterface: .wifi,
                interfaceName: candidateIfName,
                locationPermission: permission,
                capturedAt: timestamp
            )
        }

        let wifiInterface = CWWiFiClient.shared().interface(withName: candidateIfName)
            ?? CWWiFiClient.shared().interface()
        let resolvedIfName = wifiInterface?.interfaceName ?? candidateIfName ?? "en0"
        let localMAC = wifiInterface?.hardwareAddress()

        var rawSSID: String?
        var ssidHash: String?
        var bssidHash: String?
        if permission.canReadSSID {
            rawSSID = wifiInterface?.ssid()
            ssidHash = NetworkIdentifierHasher.hashSSID(rawSSID)
            bssidHash = NetworkIdentifierHasher.hashBSSID(wifiInterface?.bssid())
        }

        let routerIP = globalIPv4?["Router"] as? String
        let serviceID = globalIPv4?["PrimaryService"] as? String

        let gatewayMAC = routerIP.flatMap { Self.lookupARPMAC(forIPv4: $0) }
        let gatewayMACHash = NetworkIdentifierHasher.hashGatewayMAC(gatewayMAC)

        var subnetCIDR: String?
        if let store,
           let ifIPv4 = Self.readDictionary(store, key: "State:/Network/Interface/\(resolvedIfName)/IPv4"),
           let addresses = ifIPv4["Addresses"] as? [String],
           let masks = ifIPv4["SubnetMasks"] as? [String],
           let firstAddr = addresses.first,
           let firstMask = masks.first {
            subnetCIDR = NetworkIdentifierHasher.ipv4SubnetCIDR(address: firstAddr, netmask: firstMask)
        }

        var dhcpServerID: String?
        if let store,
           let serviceID,
           let dhcpDict = Self.readDictionary(store, key: "State:/Network/Service/\(serviceID)/DHCP"),
           let opt54 = dhcpDict["Option_54"] as? Data,
           opt54.count == 4 {
            let bytes = Array(opt54)
            dhcpServerID = "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
        }

        let interfaceHash = NetworkIdentifierHasher.hashInterfaceFingerprint(
            interfaceName: resolvedIfName,
            localHardwareMAC: localMAC,
            routerIP: routerIP,
            subnetCIDR: subnetCIDR,
            dhcpServerID: dhcpServerID
        )

        let suggestedDisplayName: String?
        if let rawSSID {
            let cleaned = rawSSID.trimmingCharacters(in: CharacterSet(["\0"]))
            if !cleaned.isEmpty {
                suggestedDisplayName = cleaned
            } else {
                suggestedDisplayName = Self.fallbackDisplayName(
                    interfaceName: resolvedIfName,
                    gatewayMACHash: gatewayMACHash,
                    interfaceHash: interfaceHash
                )
            }
        } else {
            suggestedDisplayName = Self.fallbackDisplayName(
                interfaceName: resolvedIfName,
                gatewayMACHash: gatewayMACHash,
                interfaceHash: interfaceHash
            )
        }

        return NetworkIdentitySnapshot(
            isSatisfied: true,
            primaryInterface: .wifi,
            interfaceName: resolvedIfName,
            ssidHash: ssidHash,
            bssidHash: bssidHash,
            gatewayMACHash: gatewayMACHash,
            interfaceHash: interfaceHash,
            suggestedDisplayName: suggestedDisplayName,
            locationPermission: permission,
            capturedAt: timestamp
        )
    }

    private static func fallbackDisplayName(
        interfaceName: String,
        gatewayMACHash: String?,
        interfaceHash: String?
    ) -> String? {
        if let gatewayMACHash {
            return "Wi-Fi (\(interfaceName) • Router \(gatewayMACHash.prefix(6)))"
        }
        if let interfaceHash {
            return "Wi-Fi (\(interfaceName) • Subnet \(interfaceHash.prefix(6)))"
        }
        return nil
    }

    private static func readDictionary(_ store: SCDynamicStore, key: String) -> [String: Any]? {
        SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    }

    /// Queries the BSD routing/ARP table via `sysctl` (`RTF_LLINFO`) for `targetIPv4` without
    /// spawning external subprocesses or requesting elevated privileges.
    private static func lookupARPMAC(forIPv4 targetIPv4: String) -> String? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var length: size_t = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else {
            return nil
        }

        let unit = MemoryLayout<UInt32>.size
        func alignedSocketLength(_ saLen: Int) -> Int {
            saLen > 0 ? ((saLen + unit - 1) & ~(unit - 1)) : unit
        }

        return buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<rt_msghdr>.size <= length {
                let rtm = raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
                let msgLen = Int(rtm.rtm_msglen)
                if msgLen <= 0 || offset + msgLen > length {
                    break
                }

                if (rtm.rtm_addrs & (RTA_DST | RTA_GATEWAY)) == (RTA_DST | RTA_GATEWAY) {
                    var cursor = offset + MemoryLayout<rt_msghdr>.size
                    var dstIP: String?
                    var gwMAC: String?

                    for idx in 0..<Int(RTAX_MAX) {
                        guard (rtm.rtm_addrs & (1 << idx)) != 0 else { continue }
                        guard cursor + MemoryLayout<sockaddr>.size <= offset + msgLen else { break }
                        let sa = raw.loadUnaligned(fromByteOffset: cursor, as: sockaddr.self)

                        if idx == Int(RTAX_DST),
                           sa.sa_family == UInt8(AF_INET),
                           cursor + MemoryLayout<sockaddr_in>.size <= offset + msgLen {
                            var sin = raw.loadUnaligned(fromByteOffset: cursor, as: sockaddr_in.self)
                            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                            inet_ntop(AF_INET, &sin.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                            let decodedIP = String(decoding: ipBuf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                            dstIP = decodedIP
                        } else if idx == Int(RTAX_GATEWAY),
                                  sa.sa_family == UInt8(AF_LINK),
                                  cursor + MemoryLayout<sockaddr_dl>.size <= offset + msgLen {
                            let sdl = raw.loadUnaligned(fromByteOffset: cursor, as: sockaddr_dl.self)
                            let alen = Int(sdl.sdl_alen)
                            let nlen = Int(sdl.sdl_nlen)
                            if alen == 6, let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) {
                                let macStart = cursor + dataOffset + nlen
                                if macStart + 6 <= offset + msgLen {
                                    let bytes = (0..<6).map { idx -> String in
                                        let hex = String(raw[macStart + idx], radix: 16, uppercase: false)
                                        return hex.count == 1 ? "0\(hex)" : hex
                                    }
                                    gwMAC = bytes.joined(separator: ":")
                                }
                            }
                        }

                        cursor += alignedSocketLength(Int(sa.sa_len))
                    }

                    if dstIP == targetIPv4, let gwMAC {
                        return gwMAC
                    }
                }

                offset += msgLen
            }
            return nil
        }
    }
}

@MainActor
@Observable
public final class TrustedNetworkMonitor: NSObject, CLLocationManagerDelegate, CWEventDelegate {
    public private(set) var latestSnapshot: NetworkIdentitySnapshot?
    public private(set) var currentPosture: TrustedNetworkPosture = .disabled
    public private(set) var locationPermission: LocationPermissionState = .notDetermined
    public private(set) var isMonitoring: Bool = false

    public var onEvaluationResult: ((TrustedNetworkEvaluationOutput) -> Void)?
    public var onSnapshotUpdated: ((NetworkIdentitySnapshot) -> Void)?

    public let identityProvider: any TrustedNetworkIdentityProviding
    private let clock: () -> TimeInterval

    @ObservationIgnored private nonisolated(unsafe) var pathMonitor: NWPathMonitor?
    @ObservationIgnored private let pathQueue = DispatchQueue(label: "com.pupil.trusted-wifi.path", qos: .utility)
    @ObservationIgnored private var latestPath: NWPath?
    @ObservationIgnored private var locationManager: CLLocationManager?
    @ObservationIgnored private var debounceTimer: Timer?
    @ObservationIgnored private nonisolated(unsafe) var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var isCoreWLANRegistered = false

    /// Evaluates true only outside XCTest / Swift Testing runners so unit tests never trigger TCC prompts.
    nonisolated public static var isLiveSystemAccessEnabled: Bool {
        let proc = ProcessInfo.processInfo
        if NSClassFromString("XCTestCase") != nil { return false }
        if proc.environment["XCTestConfigurationFilePath"] != nil { return false }
        if proc.processName.contains("swift-testing") || proc.processName.contains("xctest") { return false }
        return true
    }

    nonisolated public static var canRequestLocationAuthorization: Bool {
        isLiveSystemAccessEnabled
            && Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil
    }

    public init(
        identityProvider: any TrustedNetworkIdentityProviding = SystemNetworkIdentityProvider(),
        clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.identityProvider = identityProvider
        self.clock = clock
        super.init()
        self.locationPermission = identityProvider.currentLocationPermission()
    }

    public func startMonitoring() {
        guard !isMonitoring else {
            refreshCurrentNetwork()
            return
        }
        isMonitoring = true
        locationPermission = identityProvider.currentLocationPermission()

        if Self.isLiveSystemAccessEnabled && identityProvider is SystemNetworkIdentityProvider {
            let pathMon = NWPathMonitor()
            pathMonitor = pathMon
            pathMon.pathUpdateHandler = { [weak self] path in
                Task { @MainActor [weak self] in
                    guard let self, self.isMonitoring else { return }
                    self.latestPath = path
                    self.refreshCurrentNetwork(path: path)
                }
            }
            pathMon.start(queue: pathQueue)

            let manager = CLLocationManager()
            manager.delegate = self
            locationManager = manager

            let wifiClient = CWWiFiClient.shared()
            wifiClient.delegate = self
            do {
                try wifiClient.startMonitoringEvent(with: .ssidDidChange)
                try wifiClient.startMonitoringEvent(with: .bssidDidChange)
                try wifiClient.startMonitoringEvent(with: .linkDidChange)
                try wifiClient.startMonitoringEvent(with: .powerDidChange)
                isCoreWLANRegistered = true
            } catch {
                isCoreWLANRegistered = false
            }

            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshCurrentNetwork()
                }
            }
        }

        refreshCurrentNetwork()
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        debounceTimer?.invalidate()
        debounceTimer = nil

        pathMonitor?.cancel()
        pathMonitor = nil
        latestPath = nil

        if isCoreWLANRegistered {
            let wifiClient = CWWiFiClient.shared()
            try? wifiClient.stopMonitoringAllEvents()
            if wifiClient.delegate === self {
                wifiClient.delegate = nil
            }
            isCoreWLANRegistered = false
        }

        locationManager?.delegate = nil
        locationManager = nil

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    public func refreshCurrentNetwork(path: NWPath? = nil, at timestamp: TimeInterval? = nil) {
        locationPermission = identityProvider.currentLocationPermission()
        let snapshot = identityProvider.captureSnapshot(
            from: path ?? latestPath,
            at: timestamp ?? clock()
        )
        latestSnapshot = snapshot
        onSnapshotUpdated?(snapshot)
    }

    public func requestLocationPermission() {
        if Self.canRequestLocationAuthorization, let locationManager {
            locationManager.requestWhenInUseAuthorization()
        } else {
            identityProvider.requestLocationPermissionIfNeeded()
        }
        locationPermission = identityProvider.currentLocationPermission()
    }

    public func scheduleDebounceReevaluation(after delay: TimeInterval?) {
        debounceTimer?.invalidate()
        debounceTimer = nil

        guard isMonitoring, let delay, delay > 0 else { return }
        debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isMonitoring else { return }
                self.refreshCurrentNetwork()
            }
        }
    }

    public func applyPosture(_ posture: TrustedNetworkPosture) {
        currentPosture = posture
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.refreshCurrentNetwork()
        }
    }

    // MARK: - CWEventDelegate

    nonisolated public func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.refreshCurrentNetwork()
        }
    }

    nonisolated public func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.refreshCurrentNetwork()
        }
    }

    nonisolated public func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.refreshCurrentNetwork()
        }
    }

    nonisolated public func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.refreshCurrentNetwork()
        }
    }
}
