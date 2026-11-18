//
//  USBKeyVault.swift
//  Pupil
//
//  Non-blocking AES-256-GCM encrypted vault for enrolled USB security key signatures
//  and KeychainManager USB key enrollment/verification APIs.
//

import CryptoKit
import Foundation
import Security

public enum USBKeyStorageError: LocalizedError, Sendable, Equatable {
    case invalidDeviceDescriptor
    case corruptedSealedRecord
    case encryptionFailed
    case noEnrolledKey
    case enrollmentBlockedWhileActive

    public var errorDescription: String? {
        switch self {
        case .invalidDeviceDescriptor:
            return "Selected USB device does not provide valid vendor and product identifiers."
        case .corruptedSealedRecord:
            return "Enrolled USB security key record failed cryptographic verification."
        case .encryptionFailed:
            return "Failed to encrypt the USB security key signature."
        case .noEnrolledKey:
            return "No USB security key is currently enrolled."
        case .enrollmentBlockedWhileActive:
            return "Disarm Pupil before enrolling a USB security key."
        }
    }
}

public struct EncryptedUSBKeyEnvelope: Codable, Sendable, Equatable {
    public static let currentSchemaVersion: Int = 1

    public let schemaVersion: Int
    public let updatedAt: Date
    public let saltHex: String
    public let signatureDigestHex: String
    public let sealedCombinedBase64: String

    public init(
        schemaVersion: Int = EncryptedUSBKeyEnvelope.currentSchemaVersion,
        updatedAt: Date = Date(),
        saltHex: String,
        signatureDigestHex: String,
        sealedCombinedBase64: String
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.saltHex = saltHex
        self.signatureDigestHex = signatureDigestHex
        self.sealedCombinedBase64 = sealedCombinedBase64
    }
}

public final class USBKeyVault: Sendable {
    public static let keyDefaultsKey: String = "pupil.usbKeyVaultSymmetricKey"
    public static let shared = USBKeyVault()

    public let fileURL: URL
    private let keyProvider: @Sendable () -> SymmetricKey
    private let lock = NSLock()

    public init(
        fileURL: URL? = nil,
        symmetricKey: SymmetricKey? = nil
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultRecordFileURL
        }

        if let symmetricKey {
            self.keyProvider = { symmetricKey }
        } else {
            let key = Self.loadOrCreateDefaultKey()
            self.keyProvider = { key }
        }
    }

    public func save(_ signature: EnrolledUSBKeySignature) throws {
        lock.lock()
        defer { lock.unlock() }

        var saltBytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        guard status == errSecSuccess else {
            throw USBKeyStorageError.encryptionFailed
        }
        let saltHex = saltBytes.map { String(format: "%02x", $0) }.joined()
        let signatureDigestHex = Self.hashSignature(signature.canonicalSignature, saltHex: saltHex)

        let payloadEncoder = JSONEncoder()
        let plaintextData: Data
        do {
            plaintextData = try payloadEncoder.encode(signature)
        } catch {
            throw USBKeyStorageError.encryptionFailed
        }

        let key = keyProvider()
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(plaintextData, using: key)
        } catch {
            throw USBKeyStorageError.encryptionFailed
        }
        guard let combined = sealedBox.combined else {
            throw USBKeyStorageError.encryptionFailed
        }

        let envelope = EncryptedUSBKeyEnvelope(
            schemaVersion: EncryptedUSBKeyEnvelope.currentSchemaVersion,
            updatedAt: Date(),
            saltHex: saltHex,
            signatureDigestHex: signatureDigestHex,
            sealedCombinedBase64: combined.base64EncodedString()
        )

        let envelopeEncoder = JSONEncoder()
        envelopeEncoder.dateEncodingStrategy = .iso8601
        envelopeEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let envelopeData = try envelopeEncoder.encode(envelope)

        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        try envelopeData.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func load() throws -> EnrolledUSBKeySignature? {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let envelopeData: Data
        do {
            envelopeData = try Data(contentsOf: fileURL)
        } catch {
            throw USBKeyStorageError.corruptedSealedRecord
        }

        let envelopeDecoder = JSONDecoder()
        envelopeDecoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? envelopeDecoder.decode(EncryptedUSBKeyEnvelope.self, from: envelopeData),
              envelope.schemaVersion == EncryptedUSBKeyEnvelope.currentSchemaVersion,
              let combinedData = Data(base64Encoded: envelope.sealedCombinedBase64),
              let sealedBox = try? AES.GCM.SealedBox(combined: combinedData) else {
            throw USBKeyStorageError.corruptedSealedRecord
        }

        let key = keyProvider()
        let decryptedData: Data
        do {
            decryptedData = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw USBKeyStorageError.corruptedSealedRecord
        }

        let payloadDecoder = JSONDecoder()
        guard let signature = try? payloadDecoder.decode(EnrolledUSBKeySignature.self, from: decryptedData) else {
            throw USBKeyStorageError.corruptedSealedRecord
        }

        let expectedDigest = Self.hashSignature(signature.canonicalSignature, saltHex: envelope.saltHex)
        guard KeychainManager.constantTimeEqual(expectedDigest, envelope.signatureDigestHex) else {
            throw USBKeyStorageError.corruptedSealedRecord
        }

        return signature
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Private Helpers

    private static func hashSignature(_ canonicalSignature: String, saltHex: String) -> String {
        let combined = Data((saltHex + ":" + canonicalSignature).utf8)
        let digest = SHA256.hash(data: combined)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static var pupilApplicationSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("Pupil", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        return dir
    }

    private static var defaultRecordFileURL: URL {
        pupilApplicationSupportDirectory.appendingPathComponent("usb-key.record")
    }

    private static var defaultKeyFileURL: URL {
        pupilApplicationSupportDirectory.appendingPathComponent("usb-key.key")
    }

    private static func loadOrCreateDefaultKey() -> SymmetricKey {
        if let data = UserDefaults.standard.data(forKey: keyDefaultsKey), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let keyURL = defaultKeyFileURL
        if let data = try? Data(contentsOf: keyURL), data.count == 32 {
            UserDefaults.standard.set(data, forKey: keyDefaultsKey)
            return SymmetricKey(data: data)
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        UserDefaults.standard.set(keyData, forKey: keyDefaultsKey)
        try? keyData.write(to: keyURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        return newKey
    }
}

extension KeychainManager {
    nonisolated public static var hasEnrolledUSBKey: Bool {
        loadEnrolledUSBKey() != nil
    }

    @discardableResult
    nonisolated public static func enrollUSBKey(
        _ device: USBDeviceDescriptor,
        vault: USBKeyVault = .shared
    ) throws -> EnrolledUSBKeySignature {
        guard device.isEligibleForEnrollment else {
            throw USBKeyStorageError.invalidDeviceDescriptor
        }
        let signature = EnrolledUSBKeySignature(from: device)
        try vault.save(signature)
        return signature
    }

    nonisolated public static func enrollUSBKeySignature(
        _ signature: EnrolledUSBKeySignature,
        vault: USBKeyVault = .shared
    ) throws {
        guard signature.vendorID > 0, signature.productID > 0 else {
            throw USBKeyStorageError.invalidDeviceDescriptor
        }
        try vault.save(signature)
    }

    nonisolated public static func loadEnrolledUSBKey(
        vault: USBKeyVault = .shared
    ) -> EnrolledUSBKeySignature? {
        try? vault.load()
    }

    nonisolated public static func verifyUSBKeyMatch(
        _ device: USBDeviceDescriptor,
        vault: USBKeyVault = .shared
    ) -> Bool {
        guard let enrolled = loadEnrolledUSBKey(vault: vault) else { return false }
        return enrolled.matches(device)
    }

    nonisolated public static func clearEnrolledUSBKey(vault: USBKeyVault = .shared) throws {
        try vault.clear()
    }
}
