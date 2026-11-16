//
//  TamperJournalStore.swift
//  Pupil
//
//  Tamper-evident, encrypted-at-rest ring buffer storage for security event records.
//

import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

public enum TamperJournalError: LocalizedError, Sendable, Equatable {
    case unsupportedSchemaVersion(Int)
    case corruptedSealedBox
    case encryptionFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let v):
            return "Unsupported tamper journal schema version (\(v))."
        case .corruptedSealedBox:
            return "Encrypted tamper journal combined box is malformed or authentication failed."
        case .encryptionFailed:
            return "Failed to seal tamper journal payload."
        }
    }
}

public struct EncryptedJournalEnvelope: Codable, Sendable, Equatable {
    public static let currentSchemaVersion: Int = 1

    public let schemaVersion: Int
    public let updatedAt: Date
    public let sealedCombinedBase64: String

    public init(
        schemaVersion: Int = EncryptedJournalEnvelope.currentSchemaVersion,
        updatedAt: Date = Date(),
        sealedCombinedBase64: String
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.sealedCombinedBase64 = sealedCombinedBase64
    }
}

public final class TamperJournalStore: Sendable {
    public static let maxRecords: Int = 200
    public static let keyDefaultsKey: String = "pupil.tamperJournalSymmetricKey"

    public static let shared = TamperJournalStore()

    public let fileURL: URL
    private let keyProvider: @Sendable () -> SymmetricKey
    private let lock = NSLock()

    /// Initializes a journal store with an optional custom file URL and symmetric key.
    /// - Parameters:
    ///   - fileURL: Location of the versioned encrypted JSON envelope on disk. Defaults to `~/Library/Application Support/Pupil/tamper-journal.enc.json`.
    ///   - symmetricKey: Optional explicit 256-bit `SymmetricKey` (used by unit tests). When `nil`, loads or generates a persistent 256-bit key following `KeychainManager`'s non-blocking Application Support + `UserDefaults` storage pattern (`0o600` POSIX permissions).
    public init(
        fileURL: URL? = nil,
        symmetricKey: SymmetricKey? = nil
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultJournalFileURL
        }

        if let symmetricKey {
            self.keyProvider = { symmetricKey }
        } else {
            let key = Self.loadOrCreateDefaultKey()
            self.keyProvider = { key }
        }
    }

    /// Loads and decrypts stored records, newest first (`index 0` is newest).
    /// Returns `[]` if the file does not exist yet. Throws `TamperJournalError` or `CryptoKitError` if tampered/corrupted or decrypted with the wrong key.
    public func loadRecords() throws -> [SecurityEventRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try unlockedLoadRecords()
    }

    /// Encrypts and atomically persists `records` (truncated to `Self.maxRecords = 200` newest entries) to `fileURL` with `0o600` permissions.
    public func saveRecords(_ records: [SecurityEventRecord]) throws {
        lock.lock()
        defer { lock.unlock() }
        try unlockedSaveRecords(records)
    }

    /// Appends a new record at index 0 (newest-first ring buffer capped at 200 records), persists to disk, and returns the updated array.
    @discardableResult
    public func append(_ record: SecurityEventRecord) throws -> [SecurityEventRecord] {
        lock.lock()
        defer { lock.unlock() }

        var current = try unlockedLoadRecords()
        current.insert(record, at: 0)
        if current.count > Self.maxRecords {
            current.removeLast(current.count - Self.maxRecords)
        }
        try unlockedSaveRecords(current)
        return current
    }

    /// Removes the encrypted journal file from disk.
    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Pure deterministic formatter producing a sanitized Markdown incident report from the given records.
    public static func exportMarkdownReport(
        records: [SecurityEventRecord],
        generatedAt: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        var lines: [String] = []
        lines.append("# Pupil Security Incident Report")
        lines.append("")
        lines.append("- Generated: \(formatter.string(from: generatedAt))")
        lines.append("- Total Events: \(records.count)")
        lines.append("- Privacy Notice: Sanitized activity log. Contains zero PINs, credentials, or camera frames.")
        lines.append("")

        if records.isEmpty {
            lines.append("_No security events recorded._")
        } else {
            lines.append("| Timestamp (UTC) | State | Mode | Event | Detail |")
            lines.append("| --- | --- | --- | --- | --- |")
            for record in records {
                let timestampStr = formatter.string(from: record.timestamp)
                let stateStr = record.stateAtEvent.rawValue
                let modeStr = record.isSimulated ? "Simulated" : "Live"
                let titleStr = sanitizeMarkdownCell(record.title, redactDigits: false)
                let detailStr = sanitizeMarkdownCell(record.detail, redactDigits: true)
                lines.append("| \(timestampStr) | \(stateStr) | \(modeStr) | \(titleStr) | \(detailStr) |")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private Helpers

    private func unlockedLoadRecords() throws -> [SecurityEventRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let envelopeData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(EncryptedJournalEnvelope.self, from: envelopeData)
        guard envelope.schemaVersion == EncryptedJournalEnvelope.currentSchemaVersion else {
            throw TamperJournalError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        guard let combinedData = Data(base64Encoded: envelope.sealedCombinedBase64),
              let sealedBox = try? AES.GCM.SealedBox(combined: combinedData) else {
            throw TamperJournalError.corruptedSealedBox
        }
        let key = keyProvider()
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        let eventDecoder = JSONDecoder()
        eventDecoder.dateDecodingStrategy = .iso8601
        return try eventDecoder.decode([SecurityEventRecord].self, from: decryptedData)
    }

    private func unlockedSaveRecords(_ records: [SecurityEventRecord]) throws {
        let cappedRecords = Array(records.prefix(Self.maxRecords))
        let eventEncoder = JSONEncoder()
        eventEncoder.dateEncodingStrategy = .iso8601
        let plaintextData = try eventEncoder.encode(cappedRecords)

        let key = keyProvider()
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(plaintextData, using: key)
        } catch {
            throw TamperJournalError.encryptionFailed
        }
        guard let combined = sealedBox.combined else {
            throw TamperJournalError.encryptionFailed
        }

        let envelope = EncryptedJournalEnvelope(
            schemaVersion: EncryptedJournalEnvelope.currentSchemaVersion,
            updatedAt: Date(),
            sealedCombinedBase64: combined.base64EncodedString()
        )

        let envelopeEncoder = JSONEncoder()
        envelopeEncoder.dateEncodingStrategy = .iso8601
        envelopeEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let envelopeData = try envelopeEncoder.encode(envelope)

        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        try envelopeData.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static var pupilApplicationSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("Pupil", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }
        return dir
    }

    private static var defaultJournalFileURL: URL {
        pupilApplicationSupportDirectory.appendingPathComponent("tamper-journal.enc.json")
    }

    private static var defaultKeyFileURL: URL {
        pupilApplicationSupportDirectory.appendingPathComponent("journal.key")
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

    private static func sanitizeMarkdownCell(_ text: String, redactDigits: Bool) -> String {
        var result = text
        if redactDigits {
            if let regex = try? NSRegularExpression(pattern: "(?<![a-zA-Z0-9])\\d{4,8}(?![a-zA-Z0-9])") {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[REDACTED]")
            }
        }
        result = result.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        result = result.replacingOccurrences(of: "\\|", with: "|")
        result = result.replacingOccurrences(of: "|", with: "\\|")
        return result
    }
}
