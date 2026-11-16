//
//  TamperJournalTests.swift
//  PupilTests
//
//  Tests for encrypted tamper journal storage, ring buffer enforcement,
//  sanitized incident export, and SecurityCoordinator integration.
//

import CryptoKit
import Foundation
import Testing
@testable import Pupil

@Suite("Encrypted Tamper Journal Tests", .serialized)
struct TamperJournalTests {
    @MainActor
    private func makeIsolatedSettings() -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.journal.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    private func makeIsolatedStore() -> (TamperJournalStore, URL, SymmetricKey, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PupilTamperJournalTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("tamper-journal.enc.json")
        let key = SymmetricKey(size: .bits256)
        let store = TamperJournalStore(fileURL: fileURL, symmetricKey: key)
        return (store, fileURL, key, tempDir)
    }

    // MARK: - 1. AES.GCM Encrypt & Decrypt Round-Trip

    @Test("AES.GCM encrypt and decrypt round-trip with injectable fileURL and SymmetricKey")
    func testEncryptDecryptRoundTrip() throws {
        let (store, fileURL, _, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Non-existent file should load as empty array without throwing
        #expect(try store.loadRecords().isEmpty)

        let r1 = SecurityEventRecord(
            title: "Arming Started",
            detail: "10s exit delay initiated.",
            stateAtEvent: .disarmed,
            isSimulated: false
        )
        let r2 = SecurityEventRecord(
            title: "System Armed",
            detail: "Monitoring active on battery power.",
            stateAtEvent: .armed,
            isSimulated: false
        )

        try store.saveRecords([r1, r2])
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let loaded = try store.loadRecords()
        #expect(loaded.count == 2)
        #expect(loaded[0].id == r1.id)
        #expect(loaded[0].title == "Arming Started")
        #expect(loaded[0].detail == "10s exit delay initiated.")
        #expect(loaded[0].stateAtEvent == .disarmed)
        #expect(loaded[0].isSimulated == false)
        #expect(loaded[1].id == r2.id)
        #expect(loaded[1].title == "System Armed")
        #expect(loaded[1].detail == "Monitoring active on battery power.")
        #expect(loaded[1].stateAtEvent == .armed)

        // Test append puts new record at index 0
        let r3 = SecurityEventRecord(
            title: "Alarm Triggered",
            detail: "Siren active following charger disconnect.",
            stateAtEvent: .alarm,
            isSimulated: true
        )
        let updated = try store.append(r3)
        #expect(updated.count == 3)
        #expect(updated[0].id == r3.id)
        #expect(updated[0].title == "Alarm Triggered")
        #expect(updated[0].isSimulated == true)

        let reloaded = try store.loadRecords()
        #expect(reloaded.count == 3)
        #expect(reloaded[0].id == r3.id)
        #expect(reloaded[1].id == r1.id)
        #expect(reloaded[2].id == r2.id)

        // Test clear deletes file
        try store.clear()
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try store.loadRecords().isEmpty)
    }

    // MARK: - 2. Zero Plaintext Leakage on Disk

    @Test("Zero plaintext leakage on disk: sealed envelope contains no plaintext metadata")
    func testZeroPlaintextLeakage() throws {
        let (store, fileURL, _, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretTitle = "TOP_SECRET_ALERT_IDENTIFIER_X99"
        let secretDetail = "Confidential room corridor movement at coordinates (42, 108)"
        let record = SecurityEventRecord(
            title: secretTitle,
            detail: secretDetail,
            stateAtEvent: .tamperPending,
            isSimulated: false
        )

        try store.saveRecords([record])

        let rawDiskBytes = try Data(contentsOf: fileURL)
        let rawDiskString = String(decoding: rawDiskBytes, as: UTF8.self)

        // Raw disk content must NOT contain any plaintext event identifiers
        #expect(!rawDiskString.contains(secretTitle))
        #expect(!rawDiskString.contains(secretDetail))
        #expect(!rawDiskString.contains("TAMPER_PENDING"))
        #expect(!rawDiskString.contains("Confidential"))

        // Disk content must be a valid EncryptedJournalEnvelope
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(EncryptedJournalEnvelope.self, from: rawDiskBytes)
        #expect(envelope.schemaVersion == EncryptedJournalEnvelope.currentSchemaVersion)
        #expect(!envelope.sealedCombinedBase64.isEmpty)
    }

    // MARK: - 3. Tampered Ciphertext & Wrong Key Detection

    @Test("Tampered ciphertext or wrong SymmetricKey throws and prevents corrupt state")
    func testTamperedCiphertextAndWrongKey() throws {
        let (store, fileURL, _, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let record = SecurityEventRecord(
            title: "Arming Started",
            detail: "Exit delay in progress.",
            stateAtEvent: .disarmed,
            isSimulated: false
        )
        try store.saveRecords([record])

        // 1. Wrong key must throw authentication error
        let wrongKey = SymmetricKey(size: .bits256)
        let wrongKeyStore = TamperJournalStore(fileURL: fileURL, symmetricKey: wrongKey)
        #expect(throws: Error.self) {
            try wrongKeyStore.loadRecords()
        }

        // 2. Tampered ciphertext bytes must fail AES.GCM authentication
        let rawBytes = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(EncryptedJournalEnvelope.self, from: rawBytes)
        guard var combinedData = Data(base64Encoded: envelope.sealedCombinedBase64) else {
            Issue.record("Expected valid base64 in envelope")
            return
        }
        // Flip bits in the middle of the ciphertext
        combinedData[combinedData.count / 2] ^= 0xAA
        let tamperedEnvelope = EncryptedJournalEnvelope(
            schemaVersion: envelope.schemaVersion,
            updatedAt: envelope.updatedAt,
            sealedCombinedBase64: combinedData.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let tamperedBytes = try encoder.encode(tamperedEnvelope)
        try tamperedBytes.write(to: fileURL)

        #expect(throws: Error.self) {
            try store.loadRecords()
        }

        // 3. Unsupported schema version throws TamperJournalError.unsupportedSchemaVersion
        let futureEnvelope = EncryptedJournalEnvelope(
            schemaVersion: 999,
            updatedAt: Date(),
            sealedCombinedBase64: envelope.sealedCombinedBase64
        )
        let futureBytes = try encoder.encode(futureEnvelope)
        try futureBytes.write(to: fileURL)

        #expect(throws: TamperJournalError.unsupportedSchemaVersion(999)) {
            try store.loadRecords()
        }

        // 4. Malformed / corrupted base64 throws TamperJournalError.corruptedSealedBox
        let badBase64Envelope = EncryptedJournalEnvelope(
            schemaVersion: 1,
            updatedAt: Date(),
            sealedCombinedBase64: "NOT_BASE_64!!!"
        )
        let badBytes = try encoder.encode(badBase64Envelope)
        try badBytes.write(to: fileURL)

        #expect(throws: TamperJournalError.corruptedSealedBox) {
            try store.loadRecords()
        }
    }

    // MARK: - 4. 200-Record Ring Buffer Cap Enforcement

    @Test("200-record ring buffer cap enforcement on save and append")
    func testRingBufferCapEnforcement() throws {
        let (store, _, _, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Generate 230 records (indices 0..229)
        let records = (0..<230).map { i in
            SecurityEventRecord(
                title: "Event \(i)",
                detail: "Detail \(i)",
                stateAtEvent: .armed,
                isSimulated: false
            )
        }

        // saveRecords should cap at 200 records (prefix of input array)
        try store.saveRecords(records)
        let loaded = try store.loadRecords()
        #expect(loaded.count == TamperJournalStore.maxRecords)
        #expect(loaded.count == 200)
        #expect(loaded.first?.title == "Event 0")
        #expect(loaded.last?.title == "Event 199")

        // Appending to a 200-item store maintains exactly 200 items, dropping the oldest
        let newest = SecurityEventRecord(
            title: "Event Newest",
            detail: "Triggered after 200-item cap reached",
            stateAtEvent: .alarm,
            isSimulated: false
        )
        let updated = try store.append(newest)
        #expect(updated.count == 200)
        #expect(updated.first?.title == "Event Newest")
        #expect(updated[1].title == "Event 0")
        #expect(updated.last?.title == "Event 198")

        let reloaded = try store.loadRecords()
        #expect(reloaded.count == 200)
        #expect(reloaded.first?.title == "Event Newest")
        #expect(reloaded.last?.title == "Event 198")
    }

    // MARK: - 5. Sanitized Markdown Incident Export

    @Test("Sanitized Markdown incident report formatting, pipe escaping, and PIN redaction")
    func testSanitizedMarkdownReport() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        // 1. Empty records report
        let emptyReport = TamperJournalStore.exportMarkdownReport(records: [], generatedAt: fixedDate)
        #expect(emptyReport.contains("# Pupil Security Incident Report"))
        #expect(emptyReport.contains("- Generated: 2023-11-14T22:13:20Z"))
        #expect(emptyReport.contains("- Total Events: 0"))
        #expect(emptyReport.contains("- Privacy Notice: Sanitized activity log. Contains zero PINs, credentials, or camera frames."))
        #expect(emptyReport.contains("_No security events recorded._"))

        // 2. Report with records containing pipes, newlines, and PIN patterns
        let r1 = SecurityEventRecord(
            title: "Tamper | Corrupted Sensor",
            detail: "Hardware sensor | lid angle mismatch\nDetected at line 2\r\nand line 3",
            stateAtEvent: .alarm,
            isSimulated: false
        )
        let r2 = SecurityEventRecord(
            title: "Disarm Attempt",
            detail: "Failed disarm with PIN 1234 on screen lock.",
            stateAtEvent: .tamperPending,
            isSimulated: false
        )
        let r3 = SecurityEventRecord(
            title: "Backup Code Entry",
            detail: "Owner verification code: 87654321 accepted.",
            stateAtEvent: .disarmed,
            isSimulated: false
        )
        let r4 = SecurityEventRecord(
            title: "Simulation Event",
            detail: "Exit delay 15s. Peripheral device USB3012 unplugged.",
            stateAtEvent: .arming,
            isSimulated: true
        )

        let report = TamperJournalStore.exportMarkdownReport(
            records: [r1, r2, r3, r4],
            generatedAt: fixedDate
        )

        #expect(report.contains("# Pupil Security Incident Report"))
        #expect(report.contains("- Total Events: 4"))
        #expect(report.contains("| Timestamp (UTC) | State | Mode | Event | Detail |"))
        #expect(report.contains("| --- | --- | --- | --- | --- |"))

        // Pipe escaping
        #expect(report.contains("Tamper \\| Corrupted Sensor"))
        #expect(report.contains("Hardware sensor \\| lid angle mismatch"))

        // Newline normalization (no unescaped line breaks inside table cells)
        #expect(report.contains("Detected at line 2 and line 3"))
        #expect(!report.contains("mismatch\nDetected"))

        // Standalone PIN redaction
        #expect(!report.contains("1234"))
        #expect(!report.contains("87654321"))
        #expect(report.contains("Failed disarm with PIN [REDACTED] on screen lock."))
        #expect(report.contains("Owner verification code: [REDACTED] accepted."))

        // Non-standalone PIN patterns and 2/3 digit numbers preserved
        #expect(report.contains("USB3012"))
        #expect(report.contains("15s"))

        // Mode column
        #expect(report.contains("| Live |"))
        #expect(report.contains("| Simulated |"))
    }

    // MARK: - 6. SecurityCoordinator Integration

    @Test("SecurityCoordinator logging, disk persistence, markdown export, and clear integration")
    @MainActor
    func testSecurityCoordinatorIntegration() throws {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let (store, fileURL, _, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured }),
            journalStore: store
        )
        defer { coordinator.disarmWithPin("1234") }

        #expect(coordinator.events.isEmpty)

        // 1. Arming logs events and persists to journalStore
        coordinator.startArming(immediate: true)
        #expect(!coordinator.events.isEmpty)
        let loadedAfterArming = try store.loadRecords()
        #expect(loadedAfterArming.count == coordinator.events.count)
        #expect(loadedAfterArming.first?.title == coordinator.events.first?.title)

        // 2. Tamper triggers log additional events
        coordinator.triggerTamper(source: .manualTest, immediateAlarm: false, simulated: true)
        let loadedAfterTamper = try store.loadRecords()
        #expect(loadedAfterTamper.count == coordinator.events.count)
        #expect(loadedAfterTamper.contains { $0.title == "Manual Test" || $0.isSimulated })

        // 3. exportIncidentReportMarkdown helper produces sanitized markdown
        let markdown = coordinator.exportIncidentReportMarkdown()
        #expect(markdown.contains("# Pupil Security Incident Report"))
        #expect(markdown.contains("- Total Events: \(coordinator.events.count)"))

        // 4. Persistence reload across coordinator instances
        let coordinator2 = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured }),
            journalStore: store
        )
        #expect(coordinator2.events.count == coordinator.events.count)
        #expect(coordinator2.events.first?.id == coordinator.events.first?.id)

        // 5. clearEventLog clears in-memory events and wipes journal on disk
        coordinator2.clearEventLog()
        #expect(coordinator2.events.isEmpty)
        #expect(try store.loadRecords().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
}
