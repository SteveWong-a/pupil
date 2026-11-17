//
//  TrustedNetworkEvaluator.swift
//  Pupil
//
//  Pure Sendable models, domain-separated SHA-256 network identifier hasher,
//  and deterministic TrustedNetworkEvaluator boundary policy state machine.
//

import CryptoKit
import Foundation

public enum TrustedNetworkPolicyMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case autoArmAndEscalate = "autoArmAndEscalate"
    case autoArmOnly = "autoArmOnly"
    case escalateToStrictOnly = "escalateToStrictOnly"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .autoArmAndEscalate: return "Arm and set sensitivity to Strict"
        case .autoArmOnly: return "Arm Pupil only"
        case .escalateToStrictOnly: return "Set sensitivity to Strict only"
        }
    }

    public var subtitle: String {
        switch self {
        case .autoArmAndEscalate:
            return "Starts arming Pupil and upgrades gaze detection to Strict when on untrusted Wi-Fi."
        case .autoArmOnly:
            return "Starts arming Pupil on untrusted Wi-Fi without changing gaze sensitivity."
        case .escalateToStrictOnly:
            return "Upgrades gaze detection to Strict on untrusted Wi-Fi without auto-arming."
        }
    }

    public var shouldAutoArm: Bool {
        self == .autoArmAndEscalate || self == .autoArmOnly
    }

    public var shouldEscalateSensitivity: Bool {
        self == .autoArmAndEscalate || self == .escalateToStrictOnly
    }
}

public enum NetworkFingerprintSource: String, Codable, Sendable, Equatable {
    case ssid = "ssid"
    case gatewayMAC = "gatewayMAC"
    case interfaceHash = "interfaceHash"
    case unavailable = "unavailable"

    public var displayTitle: String {
        switch self {
        case .ssid: return "Wi-Fi SSID"
        case .gatewayMAC: return "Router gateway MAC"
        case .interfaceHash: return "Interface & subnet fingerprint"
        case .unavailable: return "Unavailable"
        }
    }
}

public enum LocationPermissionState: String, Codable, Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case servicesDisabled
    case unavailableInTest

    public var canReadSSID: Bool {
        self == .authorized
    }
}

public enum NetworkIdentifierHasher: Sendable {
    /// Normalizes a MAC/BSSID string ("AA-bb-0C-dd-ee-ff" or "aa:bb:c:dd:ee:ff")
    /// to lowercase 2-digit colon-delimited hex ("aa:bb:0c:dd:ee:ff").
    /// Rejects all-zero ("00:00:00:00:00:00") and broadcast ("ff:ff:ff:ff:ff:ff") placeholders.
    public static func canonicalizeMAC(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }

        var formatted: [String] = []
        formatted.reserveCapacity(6)
        for part in parts {
            guard (1...2).contains(part.count), let byte = UInt8(part, radix: 16) else {
                return nil
            }
            let hex = String(byte, radix: 16, uppercase: false)
            formatted.append(hex.count == 1 ? "0\(hex)" : hex)
        }

        let normalized = formatted.joined(separator: ":")
        if normalized == "00:00:00:00:00:00" || normalized == "ff:ff:ff:ff:ff:ff" {
            return nil
        }
        return normalized
    }

    /// Computes domain-separated SHA-256 hex digest of an exact case-sensitive Wi-Fi SSID.
    /// Returns nil if `ssid` is nil or empty after trimming NUL bytes.
    public static func hashSSID(_ ssid: String?) -> String? {
        guard let ssid else { return nil }
        let cleaned = ssid.trimmingCharacters(in: CharacterSet(["\0"]))
        guard !cleaned.isEmpty else { return nil }
        return sha256Hex("pupil.wifi.ssid.v1|\(cleaned)")
    }

    /// Computes domain-separated SHA-256 hex digest of a canonicalized AP BSSID.
    public static func hashBSSID(_ bssid: String?) -> String? {
        guard let canonical = canonicalizeMAC(bssid) else { return nil }
        return sha256Hex("pupil.wifi.bssid.v1|\(canonical)")
    }

    /// Computes domain-separated SHA-256 hex digest of the default gateway's L2 MAC address.
    /// Fallback Tier 1 when CoreLocation permission prevents SSID/BSSID access.
    public static func hashGatewayMAC(_ gatewayMAC: String?) -> String? {
        guard let canonical = canonicalizeMAC(gatewayMAC) else { return nil }
        return sha256Hex("pupil.wifi.gw.v1|\(canonical)")
    }

    /// Computes IPv4 network prefix CIDR string (e.g. "192.168.1.0/24") from local IPv4 + mask.
    /// Avoids using host IP directly so DHCP lease renewals do not invalidate trust.
    public static func ipv4SubnetCIDR(address: String?, netmask: String?) -> String? {
        guard let addr = parseIPv4(address), let mask = parseIPv4(netmask), mask != 0 else {
            return nil
        }
        // Require contiguous netmask bits (e.g. 255.255.255.0)
        let inverted = ~mask
        guard (inverted & (inverted &+ 1)) == 0 else {
            return nil
        }
        let network = addr & mask
        let prefixLength = mask.nonzeroBitCount
        return "\(formatIPv4(network))/\(prefixLength)"
    }

    /// Computes domain-separated SHA-256 hex digest from Wi-Fi interface + L3/DHCP metadata.
    /// Fallback Tier 2 when both SSID and gateway ARP MAC are unavailable.
    /// FAIL-CLOSED: Returns `nil` unless at least one network-scoped field
    /// (`routerIP`, `subnetCIDR`, or `dhcpServerID`) is non-empty.
    public static func hashInterfaceFingerprint(
        interfaceName: String,
        localHardwareMAC: String?,
        routerIP: String?,
        subnetCIDR: String?,
        dhcpServerID: String?
    ) -> String? {
        let trimmedInterface = interfaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInterface.isEmpty else { return nil }

        let normalizedRouter = nonEmptyTrimmed(routerIP)
        let normalizedSubnet = nonEmptyTrimmed(subnetCIDR)
        let normalizedDHCP = nonEmptyTrimmed(dhcpServerID)

        guard normalizedRouter != nil || normalizedSubnet != nil || normalizedDHCP != nil else {
            return nil
        }

        let canonicalLocalMAC = canonicalizeMAC(localHardwareMAC)
        let payload = "pupil.wifi.if.v1|\(trimmedInterface)|\(canonicalLocalMAC ?? "")|\(normalizedSubnet ?? "")|\(normalizedRouter ?? "")|\(normalizedDHCP ?? "")"
        return sha256Hex(payload)
    }

    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { byte in
            let hex = String(byte, radix: 16, uppercase: false)
            return hex.count == 1 ? "0\(hex)" : hex
        }.joined()
    }

    private static func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseIPv4(_ raw: String?) -> UInt32? {
        guard let raw = nonEmptyTrimmed(raw) else { return nil }
        let octets = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in octets {
            guard let octet = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(octet)
        }
        return result
    }

    private static func formatIPv4(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}

/// Immutable observation of the current network environment passed into `TrustedNetworkEvaluator`.
public struct NetworkIdentitySnapshot: Sendable, Equatable {
    public let isSatisfied: Bool
    public let primaryInterface: NetworkInterfaceKind
    public let interfaceName: String?
    public let ssidHash: String?
    public let bssidHash: String?
    public let gatewayMACHash: String?
    public let interfaceHash: String?
    /// Human-readable display suggestion for Settings UI only (e.g. raw SSID when Location is authorized,
    /// or "Wi-Fi (en0 • Router ...)" when operating in fallback mode). Never used for matching.
    public let suggestedDisplayName: String?
    public let locationPermission: LocationPermissionState
    public let capturedAt: TimeInterval

    public init(
        isSatisfied: Bool,
        primaryInterface: NetworkInterfaceKind,
        interfaceName: String? = nil,
        ssidHash: String? = nil,
        bssidHash: String? = nil,
        gatewayMACHash: String? = nil,
        interfaceHash: String? = nil,
        suggestedDisplayName: String? = nil,
        locationPermission: LocationPermissionState = .notDetermined,
        capturedAt: TimeInterval = 0
    ) {
        self.isSatisfied = isSatisfied
        self.primaryInterface = primaryInterface
        self.interfaceName = interfaceName
        self.ssidHash = ssidHash
        self.bssidHash = bssidHash
        self.gatewayMACHash = gatewayMACHash
        self.interfaceHash = interfaceHash
        self.suggestedDisplayName = suggestedDisplayName
        self.locationPermission = locationPermission
        self.capturedAt = capturedAt
    }

    /// Primary active fingerprint source in priority order.
    public var activeFingerprintSource: NetworkFingerprintSource {
        if ssidHash != nil { return .ssid }
        if gatewayMACHash != nil { return .gatewayMAC }
        if interfaceHash != nil { return .interfaceHash }
        return .unavailable
    }

    /// Stable session key used by debounce and streak-suppression tracking.
    /// Prefer `ssidHash` so roaming across mesh APs on the same SSID stays in the same session.
    public var sessionFingerprintKey: String? {
        if let ssidHash { return "ssid:\(ssidHash)" }
        if let gatewayMACHash { return "gw:\(gatewayMACHash)" }
        if let interfaceHash { return "if:\(interfaceHash)" }
        return nil
    }
}

/// Persisted enrolled trusted Wi-Fi network entry stored in `PupilSettings.trustedNetworks`.
public struct TrustedNetworkEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var displayName: String
    public var ssidHash: String?
    public var bssidHash: String?
    public var gatewayMACHash: String?
    public var interfaceHash: String?
    public var enrolledSource: NetworkFingerprintSource
    public var requireBSSIDPinning: Bool
    public let enrolledAt: Date
    public var lastMatchedAt: Date?

    public init(
        id: UUID = UUID(),
        displayName: String,
        ssidHash: String? = nil,
        bssidHash: String? = nil,
        gatewayMACHash: String? = nil,
        interfaceHash: String? = nil,
        enrolledSource: NetworkFingerprintSource,
        requireBSSIDPinning: Bool = false,
        enrolledAt: Date = Date(),
        lastMatchedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.ssidHash = ssidHash
        self.bssidHash = bssidHash
        self.gatewayMACHash = gatewayMACHash
        self.interfaceHash = interfaceHash
        self.enrolledSource = enrolledSource
        self.requireBSSIDPinning = requireBSSIDPinning
        self.enrolledAt = enrolledAt
        self.lastMatchedAt = lastMatchedAt
    }

    public var hasUsableIdentifier: Bool {
        ssidHash != nil || gatewayMACHash != nil || interfaceHash != nil
    }
}

public struct TrustedNetworkPolicyConfiguration: Sendable, Equatable {
    public let isEnabled: Bool
    public let policyMode: TrustedNetworkPolicyMode
    public let armOnOfflineDisconnect: Bool
    public let untrustedDebounceSeconds: TimeInterval
    public let offlineDebounceSeconds: TimeInterval

    public init(
        isEnabled: Bool,
        policyMode: TrustedNetworkPolicyMode = .autoArmAndEscalate,
        armOnOfflineDisconnect: Bool = false,
        untrustedDebounceSeconds: TimeInterval = 2.5,
        offlineDebounceSeconds: TimeInterval = 8.0
    ) {
        self.isEnabled = isEnabled
        self.policyMode = policyMode
        self.armOnOfflineDisconnect = armOnOfflineDisconnect
        self.untrustedDebounceSeconds = max(0, untrustedDebounceSeconds)
        self.offlineDebounceSeconds = max(0, offlineDebounceSeconds)
    }
}

public enum TrustedNetworkPosture: Sendable, Equatable {
    case disabled
    case unconfigured
    case trusted(entryID: UUID, displayName: String, matchedBy: NetworkFingerprintSource)
    case untrusted(fingerprintKey: String, source: NetworkFingerprintSource, displayLabel: String)
    case offlineAfterTrusted
    case offline
    case wiredOrCellularNeutral(NetworkInterfaceKind)
    case identityUnavailable(LocationPermissionState)
}

public enum TrustedNetworkBoundaryEvent: Sendable, Equatable {
    case enteredTrustedNetwork(entryID: UUID, displayName: String, matchedBy: NetworkFingerprintSource, restoredSensitivity: GazeSensitivity?)
    case leftTrustedForUntrusted(displayLabel: String, source: NetworkFingerprintSource, armed: Bool, escalatedToStrict: Bool)
    case leftTrustedToOffline(armed: Bool)
    case enteredUnavailableIdentity(LocationPermissionState)
}

public struct TrustedNetworkEvaluationOutput: Sendable, Equatable {
    public let posture: TrustedNetworkPosture
    public let shouldAutoArm: Bool
    /// Non-nil when the coordinator should update `settings.gazeSensitivity`.
    public let updatedGazeSensitivity: GazeSensitivity?
    /// Non-nil when entering Strict escalation and backing up the user's prior sensitivity.
    public let newBaselineSensitivityToSave: GazeSensitivity?
    /// True when returning to a trusted network (or disabling) clears the backed-up baseline.
    public let shouldClearSavedBaseline: Bool
    /// Non-nil when a debounce window is active and `TrustedNetworkMonitor` should schedule a re-evaluation.
    public let pendingReevaluationDelay: TimeInterval?
    public let event: TrustedNetworkBoundaryEvent?

    public init(
        posture: TrustedNetworkPosture,
        shouldAutoArm: Bool = false,
        updatedGazeSensitivity: GazeSensitivity? = nil,
        newBaselineSensitivityToSave: GazeSensitivity? = nil,
        shouldClearSavedBaseline: Bool = false,
        pendingReevaluationDelay: TimeInterval? = nil,
        event: TrustedNetworkBoundaryEvent? = nil
    ) {
        self.posture = posture
        self.shouldAutoArm = shouldAutoArm
        self.updatedGazeSensitivity = updatedGazeSensitivity
        self.newBaselineSensitivityToSave = newBaselineSensitivityToSave
        self.shouldClearSavedBaseline = shouldClearSavedBaseline
        self.pendingReevaluationDelay = pendingReevaluationDelay
        self.event = event
    }
}

private extension GazeSensitivity {
    var escalationRank: Int {
        switch self {
        case .relaxed: return 0
        case .balanced: return 1
        case .strict: return 2
        case .ultra: return 3
        }
    }
}

public struct TrustedNetworkEvaluator: Sendable, Equatable {
    public private(set) var lastPosture: TrustedNetworkPosture = .disabled
    public private(set) var hasObservedTrustedNetworkInSession: Bool = false
    public private(set) var suppressedUntrustedKey: String?
    public private(set) var suppressedOfflineDisconnect: Bool = false
    public private(set) var pendingUntrustedKey: String?
    public private(set) var pendingUntrustedSince: TimeInterval?
    public private(set) var pendingOfflineSince: TimeInterval?
    /// Tracks whether sensitivity was escalated by this evaluator so non-escalated sessions aren't altered.
    public private(set) var isEscalatedByPolicy: Bool = false
    /// Remembers the last untrusted key that fired a log/escalation event to avoid duplicate logs.
    private var activeUntrustedKey: String?

    public init() {}

    /// Evaluates the current network snapshot against enrolled trusted networks and security policy.
    public mutating func evaluate(
        snapshot: NetworkIdentitySnapshot,
        enrolledNetworks: [TrustedNetworkEntry],
        configuration: TrustedNetworkPolicyConfiguration,
        securityState: SecurityState,
        currentGazeSensitivity: GazeSensitivity,
        savedBaselineSensitivity: GazeSensitivity?,
        at now: TimeInterval
    ) -> TrustedNetworkEvaluationOutput {
        guard configuration.isEnabled else {
            let restored: GazeSensitivity?
            if let baseline = savedBaselineSensitivity,
               currentGazeSensitivity == .strict,
               baseline != .strict {
                restored = baseline
            } else {
                restored = nil
            }
            let shouldClear = savedBaselineSensitivity != nil
            reset()
            lastPosture = .disabled
            return TrustedNetworkEvaluationOutput(
                posture: .disabled,
                shouldAutoArm: false,
                updatedGazeSensitivity: restored,
                newBaselineSensitivityToSave: nil,
                shouldClearSavedBaseline: shouldClear,
                pendingReevaluationDelay: nil,
                event: nil
            )
        }

        guard !enrolledNetworks.isEmpty else {
            pendingUntrustedKey = nil
            pendingUntrustedSince = nil
            pendingOfflineSince = nil
            activeUntrustedKey = nil
            lastPosture = .unconfigured
            return TrustedNetworkEvaluationOutput(posture: .unconfigured)
        }

        // Offline / disconnected path
        if !snapshot.isSatisfied || snapshot.primaryInterface == .none {
            pendingUntrustedKey = nil
            pendingUntrustedSince = nil
            activeUntrustedKey = nil

            guard hasObservedTrustedNetworkInSession && configuration.armOnOfflineDisconnect else {
                pendingOfflineSince = nil
                lastPosture = .offline
                return TrustedNetworkEvaluationOutput(posture: .offline)
            }

            if suppressedOfflineDisconnect {
                pendingOfflineSince = nil
                lastPosture = .offlineAfterTrusted
                return TrustedNetworkEvaluationOutput(posture: .offlineAfterTrusted)
            }

            if pendingOfflineSince == nil {
                pendingOfflineSince = now
            }

            let elapsed = max(0, now - (pendingOfflineSince ?? now))
            if elapsed < configuration.offlineDebounceSeconds {
                let remaining = configuration.offlineDebounceSeconds - elapsed
                lastPosture = .offlineAfterTrusted
                return TrustedNetworkEvaluationOutput(
                    posture: .offlineAfterTrusted,
                    pendingReevaluationDelay: remaining
                )
            }

            pendingOfflineSince = nil
            suppressedOfflineDisconnect = true
            lastPosture = .offlineAfterTrusted
            let shouldArm = (securityState == .disarmed) && configuration.policyMode.shouldAutoArm
            return TrustedNetworkEvaluationOutput(
                posture: .offlineAfterTrusted,
                shouldAutoArm: shouldArm,
                event: .leftTrustedToOffline(armed: shouldArm)
            )
        }

        // Wired Ethernet / Cellular / Other neutral interfaces
        if snapshot.primaryInterface != .wifi {
            pendingUntrustedKey = nil
            pendingUntrustedSince = nil
            pendingOfflineSince = nil
            activeUntrustedKey = nil
            let posture: TrustedNetworkPosture = .wiredOrCellularNeutral(snapshot.primaryInterface)
            lastPosture = posture
            return TrustedNetworkEvaluationOutput(posture: posture)
        }

        // Fail closed if Wi-Fi identity cannot be fingerprinted at all
        guard let fingerprintKey = snapshot.sessionFingerprintKey else {
            pendingUntrustedKey = nil
            pendingUntrustedSince = nil
            pendingOfflineSince = nil
            activeUntrustedKey = nil
            let posture: TrustedNetworkPosture = .identityUnavailable(snapshot.locationPermission)
            let event: TrustedNetworkBoundaryEvent? = (lastPosture == posture)
                ? nil
                : .enteredUnavailableIdentity(snapshot.locationPermission)
            lastPosture = posture
            return TrustedNetworkEvaluationOutput(posture: posture, event: event)
        }

        // Trusted match check
        if let (matchedEntry, matchedBy) = matchTrustedEntry(for: snapshot, in: enrolledNetworks) {
            hasObservedTrustedNetworkInSession = true
            suppressedUntrustedKey = nil
            suppressedOfflineDisconnect = false
            pendingUntrustedKey = nil
            pendingUntrustedSince = nil
            pendingOfflineSince = nil
            activeUntrustedKey = nil
            isEscalatedByPolicy = false

            var restoredSensitivity: GazeSensitivity?
            var shouldClearBaseline = false
            if securityState == .disarmed, let baseline = savedBaselineSensitivity {
                shouldClearBaseline = true
                if currentGazeSensitivity == .strict && baseline != .strict {
                    restoredSensitivity = baseline
                }
            }

            let nextPosture: TrustedNetworkPosture = .trusted(
                entryID: matchedEntry.id,
                displayName: matchedEntry.displayName,
                matchedBy: matchedBy
            )

            let wasSameTrustedEntry: Bool
            if case .trusted(let prevID, _, _) = lastPosture, prevID == matchedEntry.id {
                wasSameTrustedEntry = true
            } else {
                wasSameTrustedEntry = false
            }

            let event: TrustedNetworkBoundaryEvent? = (!wasSameTrustedEntry || restoredSensitivity != nil)
                ? .enteredTrustedNetwork(
                    entryID: matchedEntry.id,
                    displayName: matchedEntry.displayName,
                    matchedBy: matchedBy,
                    restoredSensitivity: restoredSensitivity
                )
                : nil

            lastPosture = nextPosture
            return TrustedNetworkEvaluationOutput(
                posture: nextPosture,
                shouldAutoArm: false,
                updatedGazeSensitivity: restoredSensitivity,
                newBaselineSensitivityToSave: nil,
                shouldClearSavedBaseline: shouldClearBaseline,
                pendingReevaluationDelay: nil,
                event: event
            )
        }

        // Untrusted Wi-Fi path
        pendingOfflineSince = nil
        let source = snapshot.activeFingerprintSource
        let displayLabel = snapshot.suggestedDisplayName ?? "Untrusted Wi-Fi"
        let untrustedPosture: TrustedNetworkPosture = .untrusted(
            fingerprintKey: fingerprintKey,
            source: source,
            displayLabel: displayLabel
        )

        // If this untrusted session already cleared debounce, avoid restarting debounce on subsequent polls
        if activeUntrustedKey != fingerprintKey {
            if pendingUntrustedKey != fingerprintKey {
                pendingUntrustedKey = fingerprintKey
                pendingUntrustedSince = now
            }

            let elapsed = max(0, now - (pendingUntrustedSince ?? now))
            if elapsed < configuration.untrustedDebounceSeconds {
                let remaining = configuration.untrustedDebounceSeconds - elapsed
                lastPosture = untrustedPosture
                return TrustedNetworkEvaluationOutput(
                    posture: untrustedPosture,
                    pendingReevaluationDelay: remaining
                )
            }
        }

        pendingUntrustedKey = nil
        pendingUntrustedSince = nil

        let isSuppressed = (suppressedUntrustedKey == fingerprintKey)
        let isFirstActivationForKey = (activeUntrustedKey != fingerprintKey)
        activeUntrustedKey = fingerprintKey

        var updatedSensitivity: GazeSensitivity?
        var newBaseline: GazeSensitivity?
        if !isSuppressed,
           configuration.policyMode.shouldEscalateSensitivity,
           currentGazeSensitivity.escalationRank < GazeSensitivity.strict.escalationRank {
            updatedSensitivity = .strict
            if savedBaselineSensitivity == nil {
                newBaseline = currentGazeSensitivity
            }
            isEscalatedByPolicy = true
        }

        let shouldArm = !isSuppressed
            && configuration.policyMode.shouldAutoArm
            && securityState == .disarmed

        let event: TrustedNetworkBoundaryEvent? = (isFirstActivationForKey && !isSuppressed)
            ? .leftTrustedForUntrusted(
                displayLabel: displayLabel,
                source: source,
                armed: shouldArm,
                escalatedToStrict: updatedSensitivity == .strict
            )
            : nil

        lastPosture = untrustedPosture
        return TrustedNetworkEvaluationOutput(
            posture: untrustedPosture,
            shouldAutoArm: shouldArm,
            updatedGazeSensitivity: updatedSensitivity,
            newBaselineSensitivityToSave: newBaseline,
            shouldClearSavedBaseline: false,
            pendingReevaluationDelay: nil,
            event: event
        )
    }

    /// Matches a live snapshot against enrolled trusted networks with authoritative SSID precedence.
    public func matchTrustedEntry(
        for snapshot: NetworkIdentitySnapshot,
        in enrolled: [TrustedNetworkEntry]
    ) -> (entry: TrustedNetworkEntry, matchedBy: NetworkFingerprintSource)? {
        for entry in enrolled {
            guard entry.hasUsableIdentifier else { continue }

            // 1. Authoritative SSID check when both sides carry an ssidHash
            if let snapSSID = snapshot.ssidHash, let entrySSID = entry.ssidHash {
                if snapSSID == entrySSID {
                    if entry.requireBSSIDPinning {
                        guard let snapBSSID = snapshot.bssidHash,
                              let entryBSSID = entry.bssidHash,
                              snapBSSID == entryBSSID else {
                            continue
                        }
                    }
                    return (entry, .ssid)
                } else {
                    // Explicit SSID mismatch never falls back to gateway MAC or interface hash
                    continue
                }
            }

            // 2. Fallback when SSID is absent on either side
            if let snapGW = snapshot.gatewayMACHash,
               let entryGW = entry.gatewayMACHash,
               snapGW == entryGW {
                return (entry, .gatewayMAC)
            }

            if let snapIF = snapshot.interfaceHash,
               let entryIF = entry.interfaceHash,
               snapIF == entryIF {
                return (entry, .interfaceHash)
            }
        }
        return nil
    }

    /// Suppresses auto-arm/escalation for the current untrusted Wi-Fi session or offline disconnect
    /// until a trusted network is observed again (or the user moves to a different untrusted network).
    public mutating func suppressCurrentUntrustedSession() {
        suppressedUntrustedKey = activeUntrustedKey ?? pendingUntrustedKey
        suppressedOfflineDisconnect = true
        pendingUntrustedKey = nil
        pendingUntrustedSince = nil
        pendingOfflineSince = nil
    }

    /// Resets all evaluator state.
    public mutating func reset() {
        lastPosture = .disabled
        hasObservedTrustedNetworkInSession = false
        suppressedUntrustedKey = nil
        suppressedOfflineDisconnect = false
        pendingUntrustedKey = nil
        pendingUntrustedSince = nil
        pendingOfflineSince = nil
        isEscalatedByPolicy = false
        activeUntrustedKey = nil
    }
}
