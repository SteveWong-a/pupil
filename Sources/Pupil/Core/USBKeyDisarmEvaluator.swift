//
//  USBKeyDisarmEvaluator.swift
//  Pupil
//
//  Pure Sendable domain models and deterministic evaluator for USB security token /
//  YubiKey fast disarm. Imports Foundation only with zero AppKit or IOKit dependencies.
//

import Foundation

public struct USBDeviceDescriptor: Codable, Equatable, Hashable, Sendable, Identifiable {
    private static let knownSecurityTokenVendorIDs: Set<UInt16> = [
        0x1050, // Yubico
        0x20A0, // Nitrokey
        0x096E, // Feitian
        0x18D1, // Google Titan
        0x0483, // SoloKeys / STMicroelectronics
        0x1209, // SoloKeys / pid.codes
        0x2C97, // Ledger
        0x534C  // Trezor
    ]

    public let vendorID: UInt16
    public let productID: UInt16
    public let serialNumber: String?
    public let productName: String?
    public let vendorName: String?
    public let locationID: UInt32?
    public let deviceClass: UInt8?
    public let isBuiltIn: Bool
    public let registryEntryID: UInt64?

    public init(
        vendorID: UInt16,
        productID: UInt16,
        serialNumber: String? = nil,
        productName: String? = nil,
        vendorName: String? = nil,
        locationID: UInt32? = nil,
        deviceClass: UInt8? = nil,
        isBuiltIn: Bool = false,
        registryEntryID: UInt64? = nil
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = Self.normalizeOptionalString(serialNumber)
        self.productName = Self.normalizeOptionalString(productName)
        self.vendorName = Self.normalizeOptionalString(vendorName)
        self.locationID = locationID
        self.deviceClass = deviceClass
        self.isBuiltIn = isBuiltIn
        self.registryEntryID = registryEntryID
    }

    public static func normalizeOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// USB Hub class code (`kUSBHubClass` = 9).
    public var isHub: Bool {
        deviceClass == 9
    }

    public var isEligibleForEnrollment: Bool {
        vendorID > 0 && productID > 0 && !isHub && !isBuiltIn
    }

    public var formattedVIDPID: String {
        String(format: "0x%04X:0x%04X", vendorID, productID)
    }

    public var displayName: String {
        if let productName, !productName.isEmpty {
            return productName
        }
        if let vendorName, !vendorName.isEmpty {
            return "\(vendorName) USB Key"
        }
        return "USB Key (\(formattedVIDPID))"
    }

    /// UX sorting hint for recognized hardware security token vendors; never bypasses signature matching.
    public var isKnownSecurityTokenVendor: Bool {
        Self.knownSecurityTokenVendorIDs.contains(vendorID)
    }

    public var id: String {
        let serialPart = serialNumber ?? "noserial"
        let locationPart = locationID.map { String(format: "0x%08X", $0) } ?? "noloc"
        let registryPart = registryEntryID.map(String.init) ?? "noreg"
        return "\(formattedVIDPID)-\(serialPart)-\(locationPart)-\(registryPart)"
    }

    public var connectionToken: USBConnectionToken {
        USBConnectionToken(from: self)
    }
}

public struct USBConnectionToken: Codable, Equatable, Hashable, Sendable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let serialNumber: String?
    public let locationID: UInt32?
    public let registryEntryID: UInt64?

    public init(from device: USBDeviceDescriptor) {
        self.vendorID = device.vendorID
        self.productID = device.productID
        self.serialNumber = device.serialNumber
        self.locationID = device.locationID
        self.registryEntryID = device.registryEntryID
    }
}

public struct EnrolledUSBKeySignature: Codable, Equatable, Hashable, Sendable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let serialNumber: String?
    public let displayName: String
    public let enrolledAt: Date

    public init(
        vendorID: UInt16,
        productID: UInt16,
        serialNumber: String? = nil,
        displayName: String,
        enrolledAt: Date = Date()
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = USBDeviceDescriptor.normalizeOptionalString(serialNumber)
        self.displayName = displayName
        self.enrolledAt = enrolledAt
    }

    public init(from device: USBDeviceDescriptor, enrolledAt: Date = Date()) {
        self.init(
            vendorID: device.vendorID,
            productID: device.productID,
            serialNumber: device.serialNumber,
            displayName: device.displayName,
            enrolledAt: enrolledAt
        )
    }

    public var isSerialPinned: Bool {
        serialNumber != nil
    }

    public var formattedVIDPID: String {
        String(format: "0x%04X:0x%04X", vendorID, productID)
    }

    /// Canonical string hashed for constant-time integrity checking.
    public var canonicalSignature: String {
        "\(vendorID):\(productID):\(serialNumber ?? "")"
    }

    public var summary: EnrolledUSBKeySummary {
        EnrolledUSBKeySummary(
            vendorID: vendorID,
            productID: productID,
            isSerialPinned: isSerialPinned,
            displayName: displayName,
            enrolledAt: enrolledAt
        )
    }

    /// Matches when `device` is an eligible non-hub external device with matching VID/PID
    /// and, if enrolled with a serial number, exact serial equality.
    public func matches(_ device: USBDeviceDescriptor) -> Bool {
        guard !device.isHub, !device.isBuiltIn else { return false }
        guard device.vendorID == vendorID, device.productID == productID else { return false }
        if let enrolledSerial = serialNumber {
            return device.serialNumber == enrolledSerial
        }
        return true
    }
}

public struct EnrolledUSBKeySummary: Codable, Equatable, Sendable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let isSerialPinned: Bool
    public let displayName: String
    public let enrolledAt: Date

    public init(
        vendorID: UInt16,
        productID: UInt16,
        isSerialPinned: Bool,
        displayName: String,
        enrolledAt: Date = Date()
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.isSerialPinned = isSerialPinned
        self.displayName = displayName
        self.enrolledAt = enrolledAt
    }

    public var formattedVIDPID: String {
        String(format: "0x%04X:0x%04X", vendorID, productID)
    }
}

public enum USBDeviceEvent: Sendable, Equatable {
    case connected(USBDeviceDescriptor)
    case disconnected(USBDeviceDescriptor)
}

public enum USBKeyIgnoreReason: Sendable, Equatable {
    case featureDisabled
    case noEnrolledKey
    case inactiveSecurityState(SecurityState)
    case hubOrBuiltInDevice
    case alreadyConnectedAtBaseline
    case nonMatchingDevice
    case disconnectEvent
    case debounced
}

public enum USBKeyDisarmDecision: Sendable, Equatable {
    case disarm(matchedDevice: USBDeviceDescriptor, signature: EnrolledUSBKeySignature)
    case ignored(reason: USBKeyIgnoreReason)

    public var shouldDisarm: Bool {
        if case .disarm = self { return true }
        return false
    }
}

public enum USBEnrollmentOutcome: Sendable, Equatable {
    case enrolled(EnrolledUSBKeySignature)
    case requiresSelection([USBDeviceDescriptor])
    case noDeviceFound
    case failed(String)
}

public struct USBKeyDisarmEvaluator: Sendable, Equatable {
    public static let activeDisarmStates: Set<SecurityState> = [.armed, .tamperPending, .alarm]

    public let debounceIntervalSeconds: TimeInterval
    public private(set) var baselineConnectionTokens: Set<USBConnectionToken> = []
    public private(set) var hasBaseline: Bool = false
    public private(set) var lastMatchedTimestamp: TimeInterval?

    public init(debounceIntervalSeconds: TimeInterval = 0.5) {
        self.debounceIntervalSeconds = max(0, debounceIntervalSeconds)
    }

    /// Latches the currently attached USB devices when arming begins so a key that is already
    /// plugged in does not immediately trigger disarm upon arming or initial IOKit callback drain.
    public mutating func latchBaseline(_ connectedDevices: [USBDeviceDescriptor]) {
        baselineConnectionTokens = Set(connectedDevices.map(USBConnectionToken.init(from:)))
        hasBaseline = true
    }

    /// Clears tracked baseline tokens and debounce state when disarming or disabling the feature.
    public mutating func reset() {
        baselineConnectionTokens.removeAll()
        hasBaseline = false
        lastMatchedTimestamp = nil
    }

    /// Evaluates a discrete USB attach/detach event.
    public mutating func evaluate(
        event: USBDeviceEvent,
        enrolledSignature: EnrolledUSBKeySignature?,
        featureEnabled: Bool,
        securityState: SecurityState,
        at timestamp: TimeInterval? = nil
    ) -> USBKeyDisarmDecision {
        switch event {
        case .disconnected(let device):
            baselineConnectionTokens.remove(device.connectionToken)
            return .ignored(reason: .disconnectEvent)

        case .connected(let device):
            let token = device.connectionToken
            if baselineConnectionTokens.contains(token) {
                return .ignored(reason: .alreadyConnectedAtBaseline)
            }
            baselineConnectionTokens.insert(token)

            return evaluateCandidateDevice(
                device,
                enrolledSignature: enrolledSignature,
                featureEnabled: featureEnabled,
                securityState: securityState,
                at: timestamp
            )
        }
    }

    /// Reconciles a full connected-device snapshot against `baselineConnectionTokens`,
    /// returning `.disarm` for the first newly attached matching device, if any.
    public mutating func evaluateSnapshot(
        _ devices: [USBDeviceDescriptor],
        enrolledSignature: EnrolledUSBKeySignature?,
        featureEnabled: Bool,
        securityState: SecurityState,
        at timestamp: TimeInterval? = nil
    ) -> USBKeyDisarmDecision {
        let currentTokens = Set(devices.map(USBConnectionToken.init(from:)))
        if !hasBaseline {
            baselineConnectionTokens = currentTokens
            hasBaseline = true
            return .ignored(reason: .alreadyConnectedAtBaseline)
        }

        let addedTokens = currentTokens.subtracting(baselineConnectionTokens)
        baselineConnectionTokens = currentTokens

        let addedDevices = devices.filter { addedTokens.contains($0.connectionToken) }
        guard !addedDevices.isEmpty else {
            return .ignored(reason: .alreadyConnectedAtBaseline)
        }

        var fallbackIgnoreReason: USBKeyIgnoreReason?
        for device in addedDevices {
            let decision = evaluateCandidateDevice(
                device,
                enrolledSignature: enrolledSignature,
                featureEnabled: featureEnabled,
                securityState: securityState,
                at: timestamp
            )
            switch decision {
            case .disarm:
                return decision
            case .ignored(let reason):
                // Immediate global gates (disabled, un-enrolled, inactive state) apply to all devices.
                switch reason {
                case .featureDisabled, .noEnrolledKey, .inactiveSecurityState:
                    return decision
                case .debounced:
                    fallbackIgnoreReason = .debounced
                case .nonMatchingDevice:
                    if fallbackIgnoreReason != .debounced {
                        fallbackIgnoreReason = .nonMatchingDevice
                    }
                case .hubOrBuiltInDevice, .alreadyConnectedAtBaseline, .disconnectEvent:
                    if fallbackIgnoreReason == nil {
                        fallbackIgnoreReason = reason
                    }
                }
            }
        }

        return .ignored(reason: fallbackIgnoreReason ?? .alreadyConnectedAtBaseline)
    }

    private mutating func evaluateCandidateDevice(
        _ device: USBDeviceDescriptor,
        enrolledSignature: EnrolledUSBKeySignature?,
        featureEnabled: Bool,
        securityState: SecurityState,
        at timestamp: TimeInterval?
    ) -> USBKeyDisarmDecision {
        if device.isHub || device.isBuiltIn {
            return .ignored(reason: .hubOrBuiltInDevice)
        }
        guard featureEnabled else {
            return .ignored(reason: .featureDisabled)
        }
        guard let signature = enrolledSignature else {
            return .ignored(reason: .noEnrolledKey)
        }
        guard Self.activeDisarmStates.contains(securityState) else {
            return .ignored(reason: .inactiveSecurityState(securityState))
        }
        guard signature.matches(device) else {
            return .ignored(reason: .nonMatchingDevice)
        }
        if let ts = timestamp, let last = lastMatchedTimestamp, (ts - last) < debounceIntervalSeconds {
            return .ignored(reason: .debounced)
        }
        if let ts = timestamp {
            lastMatchedTimestamp = ts
        }
        return .disarm(matchedDevice: device, signature: signature)
    }
}
