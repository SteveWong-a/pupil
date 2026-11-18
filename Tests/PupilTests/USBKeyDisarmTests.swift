//
//  USBKeyDisarmTests.swift
//  PupilTests
//
//  Deterministic unit and integration tests for USB security token / YubiKey fast disarm.
//

import CryptoKit
import Foundation
import Testing
@testable import Pupil

@Suite("USB Security Key Fast Disarm Tests", .serialized)
struct USBKeyDisarmTests {
    private let yubikey = USBDeviceDescriptor(
        vendorID: 0x1050,
        productID: 0x0407,
        serialNumber: "24681357",
        productName: "YubiKey OTP+FIDO+CCID",
        vendorName: "Yubico",
        locationID: 0x01100000,
        deviceClass: 0,
        isBuiltIn: false,
        registryEntryID: 1001
    )

    private let sameModelDifferentSerialYubikey = USBDeviceDescriptor(
        vendorID: 0x1050,
        productID: 0x0407,
        serialNumber: "99999999",
        productName: "YubiKey OTP+FIDO+CCID",
        vendorName: "Yubico",
        locationID: 0x01200000,
        deviceClass: 0,
        isBuiltIn: false,
        registryEntryID: 1002
    )

    private let sameModelNilSerialYubikey = USBDeviceDescriptor(
        vendorID: 0x1050,
        productID: 0x0407,
        serialNumber: nil,
        productName: "YubiKey OTP+FIDO+CCID",
        vendorName: "Yubico",
        locationID: 0x01300000,
        deviceClass: 0,
        isBuiltIn: false,
        registryEntryID: 1003
    )

    private let genericTokenNoSerial = USBDeviceDescriptor(
        vendorID: 0x20A0,
        productID: 0x4288,
        serialNumber: nil,
        productName: "Nitrokey 3",
        vendorName: "Nitrokey",
        locationID: 0x01400000,
        deviceClass: 0,
        isBuiltIn: false,
        registryEntryID: 2001
    )

    private let externalMouse = USBDeviceDescriptor(
        vendorID: 0x046D,
        productID: 0xC52B,
        serialNumber: "MOUSE-123",
        productName: "Logitech Unifying Receiver",
        vendorName: "Logitech",
        locationID: 0x01500000,
        deviceClass: 0,
        isBuiltIn: false,
        registryEntryID: 3001
    )

    private let usbHub = USBDeviceDescriptor(
        vendorID: 0x05E3,
        productID: 0x0610,
        serialNumber: nil,
        productName: "USB3.1 Hub",
        vendorName: "Genesys Logic",
        locationID: 0x01000000,
        deviceClass: 9,
        isBuiltIn: false,
        registryEntryID: 4001
    )

    private let builtInCamera = USBDeviceDescriptor(
        vendorID: 0x05AC,
        productID: 0x8514,
        serialNumber: "APPLE-BUILTIN",
        productName: "FaceTime HD Camera",
        vendorName: "Apple Inc.",
        locationID: 0x80200000,
        deviceClass: 0,
        isBuiltIn: true,
        registryEntryID: 5001
    )

    @MainActor
    private func makeIsolatedEnvironment() -> (
        settings: PupilSettings,
        defaults: UserDefaults,
        suiteName: String,
        vault: USBKeyVault,
        journalStore: TamperJournalStore,
        tempDir: URL
    ) {
        let suiteName = "com.pupil.tests.usb.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        settings.exitDelaySeconds = 0
        settings.gracePeriodSeconds = 10

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PupilUSBTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let vaultURL = tempDir.appendingPathComponent("usb-key.record")
        let vault = USBKeyVault(fileURL: vaultURL, symmetricKey: SymmetricKey(size: .bits256))

        let journalURL = tempDir.appendingPathComponent("tamper-journal.enc.json")
        let journalStore = TamperJournalStore(fileURL: journalURL, symmetricKey: SymmetricKey(size: .bits256))

        return (settings, defaults, suiteName, vault, journalStore, tempDir)
    }

    // MARK: - 1. Exact Match with Vendor, Product, and Serial

    @Test("Exact match with VID, PID, and serial disarms across armed, tamperPending, and alarm")
    func testExactMatchWithVendorProductAndSerial() {
        let signature = EnrolledUSBKeySignature(from: yubikey)
        #expect(signature.isSerialPinned == true)

        for activeState in [SecurityState.armed, .tamperPending, .alarm] {
            var evaluator = USBKeyDisarmEvaluator(debounceIntervalSeconds: 0.5)
            let decision = evaluator.evaluate(
                event: .connected(yubikey),
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: activeState,
                at: 100.0
            )
            #expect(decision == .disarm(matchedDevice: yubikey, signature: signature))
            #expect(decision.shouldDisarm == true)
        }
    }

    // MARK: - 2. Rejects Different or Missing Serial When Serial-Pinned

    @Test("Rejects different serial, nil serial, or different VID/PID when enrollment is serial-pinned")
    func testRejectsDifferentOrMissingSerialWhenSerialPinned() {
        let signature = EnrolledUSBKeySignature(from: yubikey)
        var evaluator = USBKeyDisarmEvaluator()

        let wrongSerialDecision = evaluator.evaluate(
            event: .connected(sameModelDifferentSerialYubikey),
            enrolledSignature: signature,
            featureEnabled: true,
            securityState: .armed,
            at: 10.0
        )
        #expect(wrongSerialDecision == .ignored(reason: .nonMatchingDevice))

        let nilSerialDecision = evaluator.evaluate(
            event: .connected(sameModelNilSerialYubikey),
            enrolledSignature: signature,
            featureEnabled: true,
            securityState: .armed,
            at: 11.0
        )
        #expect(nilSerialDecision == .ignored(reason: .nonMatchingDevice))

        let emptySerialDevice = USBDeviceDescriptor(
            vendorID: 0x1050,
            productID: 0x0407,
            serialNumber: "   \n ",
            productName: "YubiKey OTP+FIDO+CCID",
            registryEntryID: 1004
        )
        #expect(emptySerialDevice.serialNumber == nil)
        let emptySerialDecision = evaluator.evaluate(
            event: .connected(emptySerialDevice),
            enrolledSignature: signature,
            featureEnabled: true,
            securityState: .armed,
            at: 12.0
        )
        #expect(emptySerialDecision == .ignored(reason: .nonMatchingDevice))

        let wrongVIDPIDDecision = evaluator.evaluate(
            event: .connected(externalMouse),
            enrolledSignature: signature,
            featureEnabled: true,
            securityState: .armed,
            at: 13.0
        )
        #expect(wrongVIDPIDDecision == .ignored(reason: .nonMatchingDevice))
    }

    // MARK: - 3. Optional Serial Number Matches by VID/PID Only

    @Test("Enrollment without serial number matches by VID/PID regardless of observed serial presence")
    func testOptionalSerialNumberMatchesByVIDPIDOnly() {
        let signature = EnrolledUSBKeySignature(from: genericTokenNoSerial)
        #expect(signature.isSerialPinned == false)

        var evaluator = USBKeyDisarmEvaluator()
        let nilObserved = evaluator.evaluate(
            event: .connected(genericTokenNoSerial),
            enrolledSignature: signature,
            featureEnabled: true,
            securityState: .armed,
            at: 20.0
        )
        #expect(nilObserved == .disarm(matchedDevice: genericTokenNoSerial, signature: signature))

        let observedWithSerial = USBDeviceDescriptor(
            vendorID: genericTokenNoSerial.vendorID,
            productID: genericTokenNoSerial.productID,
            serialNumber: "OPTIONAL-SER-01",
            productName: "Nitrokey 3",
            registryEntryID: 2002
        )
        let withSerialDecision = evaluator.evaluate(
            event: .connected(observedWithSerial),
            enrolledSignature: signature,
            featureEnabled: true,
            securityState: .tamperPending,
            at: 25.0
        )
        #expect(withSerialDecision == .disarm(matchedDevice: observedWithSerial, signature: signature))
    }

    // MARK: - 4. Pre-Connected Baseline Ignored Until Unplugged and Reinserted

    @Test("Pre-connected baseline key is ignored until unplugged and reinserted")
    func testPreConnectedBaselineIgnoredUntilUnpluggedAndReinserted() {
        let signature = EnrolledUSBKeySignature(from: yubikey)
        var evaluator = USBKeyDisarmEvaluator()
        evaluator.latchBaseline([yubikey, externalMouse])

        let initialConnected = evaluator.evaluate(
            event: .connected(yubikey),
            enrolledSignature: signature,
            featureEnabled: true,
            securityState: .armed,
            at: 10.0
        )
        #expect(initialConnected == .ignored(reason: .alreadyConnectedAtBaseline))

        let initialSnapshot = evaluator.evaluateSnapshot(
            [yubikey, externalMouse],
            enrolledSignature: signature,
            featureEnabled: true,
            securityState: .armed,
            at: 11.0
        )
        #expect(initialSnapshot == .ignored(reason: .alreadyConnectedAtBaseline))

        let unplugEvent = evaluator.evaluate(
            event: .disconnected(yubikey),
            enrolledSignature: signature,
            featureEnabled: true,
            securityState: .armed,
            at: 12.0
        )
        #expect(unplugEvent == .ignored(reason: .disconnectEvent))

        let reinsertDecision = evaluator.evaluate(
            event: .connected(yubikey),
            enrolledSignature: signature,
            featureEnabled: true,
            securityState: .armed,
            at: 13.0
        )
        #expect(reinsertDecision == .disarm(matchedDevice: yubikey, signature: signature))

        // Snapshot reconciliation also detects unplug -> replug transitions cleanly.
        var snapshotEvaluator = USBKeyDisarmEvaluator()
        snapshotEvaluator.latchBaseline([yubikey])
        #expect(
            snapshotEvaluator.evaluateSnapshot(
                [],
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: .armed,
                at: 20.0
            ) == .ignored(reason: .alreadyConnectedAtBaseline)
        )
        #expect(
            snapshotEvaluator.evaluateSnapshot(
                [yubikey],
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: .armed,
                at: 21.0
            ) == .disarm(matchedDevice: yubikey, signature: signature)
        )
    }

    // MARK: - 5. Evaluator Feature, State, Hub, and Debounce Guards

    @Test("Evaluator enforces feature flag, enrollment, security state, hub/built-in, disconnect, and debounce guards")
    func testEvaluatorFeatureStateHubAndDebounceGuards() {
        let signature = EnrolledUSBKeySignature(from: yubikey)

        // Feature disabled
        var disabledEval = USBKeyDisarmEvaluator()
        #expect(
            disabledEval.evaluate(
                event: .connected(yubikey),
                enrolledSignature: signature,
                featureEnabled: false,
                securityState: .armed,
                at: 1.0
            ) == .ignored(reason: .featureDisabled)
        )

        // No enrolled key
        var noKeyEval = USBKeyDisarmEvaluator()
        #expect(
            noKeyEval.evaluate(
                event: .connected(yubikey),
                enrolledSignature: nil,
                featureEnabled: true,
                securityState: .armed,
                at: 1.0
            ) == .ignored(reason: .noEnrolledKey)
        )

        // Inactive security states (.disarmed and .arming)
        var disarmedEval = USBKeyDisarmEvaluator()
        #expect(
            disarmedEval.evaluate(
                event: .connected(yubikey),
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: .disarmed,
                at: 1.0
            ) == .ignored(reason: .inactiveSecurityState(.disarmed))
        )

        var armingEval = USBKeyDisarmEvaluator()
        #expect(
            armingEval.evaluate(
                event: .connected(yubikey),
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: .arming,
                at: 1.0
            ) == .ignored(reason: .inactiveSecurityState(.arming))
        )

        // Hub and built-in devices
        var hubEval = USBKeyDisarmEvaluator()
        #expect(
            hubEval.evaluate(
                event: .connected(usbHub),
                enrolledSignature: EnrolledUSBKeySignature(
                    vendorID: usbHub.vendorID,
                    productID: usbHub.productID,
                    serialNumber: nil,
                    displayName: usbHub.displayName
                ),
                featureEnabled: true,
                securityState: .armed,
                at: 1.0
            ) == .ignored(reason: .hubOrBuiltInDevice)
        )
        #expect(
            hubEval.evaluate(
                event: .connected(builtInCamera),
                enrolledSignature: EnrolledUSBKeySignature(
                    vendorID: builtInCamera.vendorID,
                    productID: builtInCamera.productID,
                    serialNumber: builtInCamera.serialNumber,
                    displayName: builtInCamera.displayName
                ),
                featureEnabled: true,
                securityState: .armed,
                at: 1.0
            ) == .ignored(reason: .hubOrBuiltInDevice)
        )

        // Disconnect event
        #expect(
            hubEval.evaluate(
                event: .disconnected(yubikey),
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: .armed,
                at: 1.5
            ) == .ignored(reason: .disconnectEvent)
        )

        // Debounce within 0.5s window
        var debounceEval = USBKeyDisarmEvaluator(debounceIntervalSeconds: 0.5)
        #expect(
            debounceEval.evaluate(
                event: .connected(yubikey),
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: .armed,
                at: 10.0
            ) == .disarm(matchedDevice: yubikey, signature: signature)
        )
        #expect(
            debounceEval.evaluate(
                event: .disconnected(yubikey),
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: .armed,
                at: 10.1
            ) == .ignored(reason: .disconnectEvent)
        )
        #expect(
            debounceEval.evaluate(
                event: .connected(yubikey),
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: .armed,
                at: 10.2
            ) == .ignored(reason: .debounced)
        )
        #expect(
            debounceEval.evaluate(
                event: .disconnected(yubikey),
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: .armed,
                at: 10.4
            ) == .ignored(reason: .disconnectEvent)
        )
        #expect(
            debounceEval.evaluate(
                event: .connected(yubikey),
                enrolledSignature: signature,
                featureEnabled: true,
                securityState: .armed,
                at: 10.6
            ) == .disarm(matchedDevice: yubikey, signature: signature)
        )
    }

    // MARK: - 6. Keychain Vault Encrypts and Detects Tampering

    @MainActor
    @Test("USBKeyVault encrypts enrolled signature with 0o600 permissions and detects tampering")
    func testKeychainVaultEncryptsAndDetectsTampering() throws {
        let suiteName = "com.pupil.tests.usb.vault.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PupilUSBVaultTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vaultURL = tempDir.appendingPathComponent("usb-key.record")
        let key = SymmetricKey(size: .bits256)
        let vault = USBKeyVault(fileURL: vaultURL, symmetricKey: key)

        let enrolled = try KeychainManager.enrollUSBKey(yubikey, vault: vault)
        #expect(enrolled.serialNumber == "24681357")
        #expect(FileManager.default.fileExists(atPath: vaultURL.path))

        // Verify 0o600 file permissions.
        let attrs = try FileManager.default.attributesOfItem(atPath: vaultURL.path)
        let posix = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(posix == 0o600)

        // Verify zero plaintext serial leakage on disk or in UserDefaults summary.
        let rawDiskString = String(decoding: try Data(contentsOf: vaultURL), as: UTF8.self)
        #expect(!rawDiskString.contains("24681357"))

        let settings = PupilSettings(defaults: defaults)
        settings.enrolledUSBKeySummary = enrolled.summary
        let summaryData = defaults.data(forKey: "pupil.enrolledUSBKeySummary")!
        let summaryString = String(decoding: summaryData, as: UTF8.self)
        #expect(!summaryString.contains("24681357"))

        // Exact round-trip load and match verification.
        let loaded = KeychainManager.loadEnrolledUSBKey(vault: vault)
        #expect(loaded == enrolled)
        #expect(KeychainManager.verifyUSBKeyMatch(yubikey, vault: vault) == true)
        #expect(KeychainManager.verifyUSBKeyMatch(sameModelDifferentSerialYubikey, vault: vault) == false)

        // Wrong symmetric key fails cleanly.
        let wrongKeyVault = USBKeyVault(fileURL: vaultURL, symmetricKey: SymmetricKey(size: .bits256))
        #expect(KeychainManager.loadEnrolledUSBKey(vault: wrongKeyVault) == nil)
        #expect(throws: USBKeyStorageError.corruptedSealedRecord) {
            try wrongKeyVault.load()
        }

        // Tampering with stored envelope bytes fails verification.
        var tamperedData = try Data(contentsOf: vaultURL)
        let tamperIndex = tamperedData.count / 2
        tamperedData[tamperIndex] ^= 0xFF
        try tamperedData.write(to: vaultURL, options: [.atomic])
        #expect(KeychainManager.loadEnrolledUSBKey(vault: vault) == nil)
        #expect(throws: USBKeyStorageError.corruptedSealedRecord) {
            try vault.load()
        }

        try KeychainManager.clearEnrolledUSBKey(vault: vault)
        #expect(!FileManager.default.fileExists(atPath: vaultURL.path))
    }

    // MARK: - 7. PupilSettings USB Key Persistence

    @MainActor
    @Test("PupilSettings persists usbKeyDisarmEnabled and enrolledUSBKeySummary and posts screenShieldSync")
    func testPupilSettingsUSBKeyPersistence() {
        let suiteName = "com.pupil.tests.usb.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: defaults)
        #expect(settings.usbKeyDisarmEnabled == false)
        #expect(settings.enrolledUSBKeySummary == nil)

        final class SyncCounter: @unchecked Sendable {
            var count = 0
        }
        let syncCounter = SyncCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .screenShieldSync,
            object: nil,
            queue: nil
        ) { _ in
            syncCounter.count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let summary = EnrolledUSBKeySignature(from: yubikey).summary
        settings.usbKeyDisarmEnabled = true
        settings.enrolledUSBKeySummary = summary
        #expect(syncCounter.count >= 1)

        let reloaded = PupilSettings(defaults: defaults)
        #expect(reloaded.usbKeyDisarmEnabled == true)
        #expect(reloaded.enrolledUSBKeySummary == summary)
        #expect(reloaded.enrolledUSBKeySummary?.isSerialPinned == true)
        #expect(reloaded.enrolledUSBKeySummary?.formattedVIDPID == "0x1050:0x0407")
    }

    // MARK: - 8. Coordinator Fast Disarm from Armed Clears Screen Shield & Interactive Unlock

    @MainActor
    @Test("Coordinator fast disarm from armed clears screen shield, interactive unlock, and suppresses idle streak")
    func testCoordinatorFastDisarmFromArmedClearsScreenShieldAndInteractiveUnlock() throws {
        let env = makeIsolatedEnvironment()
        defer {
            env.defaults.removePersistentDomain(forName: env.suiteName)
            try? FileManager.default.removeItem(at: env.tempDir)
        }

        let monitor = USBKeyMonitor(startImmediately: false)
        monitor.connectedDevicesProvider = { [] }
        let powerMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100)
        env.settings.idleAutoArmEnabled = true

        let coordinator = SecurityCoordinator(
            settings: env.settings,
            powerMonitor: powerMonitor,
            journalStore: env.journalStore,
            usbMonitor: monitor,
            usbKeyVault: env.vault
        )
        let shieldController = ScreenShieldController(coordinator: coordinator)

        _ = try coordinator.enrollUSBKey(yubikey)
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        coordinator.handleArmedUserInput()
        #expect(coordinator.isInteractiveUnlockRequested == true)
        shieldController.syncWithCoordinator()

        monitor.ingestEventForTesting(.connected(yubikey))

        #expect(coordinator.state == .disarmed)
        #expect(coordinator.isInteractiveUnlockRequested == false)
        #expect(coordinator.idleEvaluator.isSuppressedForCurrentStreak == true)

        let disarmedEvent = coordinator.events.first(where: { $0.title == "Disarmed" })
        #expect(disarmedEvent != nil)
        #expect(disarmedEvent?.detail.contains("USB Security Key") == true)
        // Must never expose raw USB serial numbers in journal records or markdown exports.
        let markdown = coordinator.exportIncidentReportMarkdown()
        #expect(!markdown.contains("24681357"))
    }

    // MARK: - 9. Coordinator Fast Disarm Clears Tamper Countdown, Alarm Siren, and Lockout

    @MainActor
    @Test("Coordinator fast disarm clears tamper countdown, alarm siren, sleep hold, lockout, and posts screenShieldSync")
    func testCoordinatorFastDisarmClearsTamperCountdownAlarmSirenAndLockout() throws {
        let env = makeIsolatedEnvironment()
        defer {
            SirenSynthesizer.shared.stop()
            env.defaults.removePersistentDomain(forName: env.suiteName)
            try? FileManager.default.removeItem(at: env.tempDir)
        }

        let monitor = USBKeyMonitor(startImmediately: false)
        monitor.connectedDevicesProvider = { [] }
        let powerMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100)
        env.settings.idleAutoArmEnabled = true

        let coordinator = SecurityCoordinator(
            settings: env.settings,
            powerMonitor: powerMonitor,
            journalStore: env.journalStore,
            usbMonitor: monitor,
            usbKeyVault: env.vault
        )
        let previousPinStoreData = UserDefaults.standard.data(forKey: KeychainManager.storeKey)
        let previousFallbackPinData = UserDefaults.standard.data(forKey: "pupil.fallbackPinRecord")
        let pinRecordURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pupil", isDirectory: true)
            .appendingPathComponent("pin.record")
        let previousPinFileData = pinRecordURL.flatMap { try? Data(contentsOf: $0) }
        defer {
            if let previousPinStoreData {
                UserDefaults.standard.set(previousPinStoreData, forKey: KeychainManager.storeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: KeychainManager.storeKey)
            }
            if let previousFallbackPinData {
                UserDefaults.standard.set(previousFallbackPinData, forKey: "pupil.fallbackPinRecord")
            } else {
                UserDefaults.standard.removeObject(forKey: "pupil.fallbackPinRecord")
            }
            if let pinRecordURL {
                if let previousPinFileData {
                    try? previousPinFileData.write(to: pinRecordURL, options: [.atomic])
                } else {
                    try? FileManager.default.removeItem(at: pinRecordURL)
                }
            }
        }
        try KeychainManager.enrollPin("4321")
        _ = try coordinator.enrollUSBKey(yubikey)

        // First verify fast disarm from .tamperPending clears countdown cleanly.
        coordinator.startArming(immediate: true)
        coordinator.triggerTamper(source: .chargerUnplugged, immediateAlarm: false)
        #expect(coordinator.state == .tamperPending)
        #expect(coordinator.countdownSecondsRemaining > 0)

        monitor.ingestEventForTesting(.connected(yubikey))
        #expect(coordinator.state == .disarmed)
        #expect(coordinator.countdownSecondsRemaining == 0)
        #expect(coordinator.activeTamperSource == nil)

        // Now arm again, escalate to .alarm, and trigger PIN lockout.
        coordinator.startArming(immediate: true)
        coordinator.enterAlarm(source: .lidClosed)
        #expect(coordinator.state == .alarm)

        for _ in 0..<PinAttemptLimiter.tier1FailureThreshold {
            #expect(coordinator.disarmWithPin("0000") == false)
        }
        #expect(coordinator.isPinLockedOut == true)
        #expect(coordinator.pinLockoutSecondsRemaining > 0)

        final class SyncFlag: @unchecked Sendable {
            var posted = false
        }
        let syncFlag = SyncFlag()
        let syncObserver = NotificationCenter.default.addObserver(
            forName: .screenShieldSync,
            object: nil,
            queue: nil
        ) { _ in
            syncFlag.posted = true
        }
        defer { NotificationCenter.default.removeObserver(syncObserver) }

        monitor.ingestEventForTesting(.connected(yubikey))

        #expect(coordinator.state == .disarmed)
        #expect(coordinator.countdownSecondsRemaining == 0)
        #expect(coordinator.activeTamperSource == nil)
        #expect(coordinator.pinLockoutSecondsRemaining == 0)
        #expect(coordinator.isPinLockedOut == false)
        #expect(SirenSynthesizer.shared.isActive == false)
        #expect(powerMonitor.isSleepAssertionActive == false)
        #expect(syncFlag.posted == true)
    }

    // MARK: - 10. Coordinator Enrollment Outcomes and Ignored Triggers

    @MainActor
    @Test("Coordinator enrollment outcomes sort security tokens first and ignore disabled or unrecognized keys")
    func testCoordinatorEnrollmentOutcomesAndIgnoredTriggers() throws {
        let env = makeIsolatedEnvironment()
        defer {
            env.defaults.removePersistentDomain(forName: env.suiteName)
            try? FileManager.default.removeItem(at: env.tempDir)
        }

        var connectedList: [USBDeviceDescriptor] = []
        let monitor = USBKeyMonitor(startImmediately: false)
        monitor.connectedDevicesProvider = { connectedList }
        let powerMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100)

        let coordinator = SecurityCoordinator(
            settings: env.settings,
            powerMonitor: powerMonitor,
            journalStore: env.journalStore,
            usbMonitor: monitor,
            usbKeyVault: env.vault
        )

        // Empty or hub-only -> .noDeviceFound
        connectedList = []
        #expect(coordinator.enrollCurrentUSBKey() == .noDeviceFound)
        connectedList = [usbHub, builtInCamera]
        #expect(coordinator.enrollCurrentUSBKey() == .noDeviceFound)

        // Multiple eligible devices -> .requiresSelection sorted with security-token vendor first
        connectedList = [externalMouse, yubikey]
        let multiOutcome = coordinator.enrollCurrentUSBKey()
        #expect(multiOutcome == .requiresSelection([yubikey, externalMouse]))

        // Single eligible device -> .enrolled and auto-enables usbKeyDisarmEnabled
        connectedList = [yubikey]
        let singleOutcome = coordinator.enrollCurrentUSBKey()
        if case .enrolled(let sig) = singleOutcome {
            #expect(sig.vendorID == yubikey.vendorID)
            #expect(sig.productID == yubikey.productID)
            #expect(sig.serialNumber == yubikey.serialNumber)
        } else {
            Issue.record("Expected .enrolled outcome, got \(String(describing: singleOutcome))")
        }
        #expect(env.settings.usbKeyDisarmEnabled == true)
        #expect(coordinator.hasEnrolledUSBKey == true)

        // Unrecognized device and disabled toggle leave .armed and .tamperPending unchanged.
        connectedList = []
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        monitor.ingestEventForTesting(.connected(sameModelDifferentSerialYubikey))
        #expect(coordinator.state == .armed)

        env.settings.usbKeyDisarmEnabled = false
        coordinator.triggerTamper(source: .chargerUnplugged, immediateAlarm: false)
        #expect(coordinator.state == .tamperPending)

        monitor.ingestEventForTesting(.connected(yubikey))
        #expect(coordinator.state == .tamperPending)

        // Re-enabling and removing enrollment resets state cleanly.
        env.settings.usbKeyDisarmEnabled = true
        try coordinator.removeEnrolledUSBKey()
        #expect(coordinator.hasEnrolledUSBKey == false)
        #expect(env.settings.enrolledUSBKeySummary == nil)
        #expect(env.settings.usbKeyDisarmEnabled == false)
    }

    @MainActor
    @Test("Coordinator refuses USB key enrollment while security state is active")
    func testCoordinatorRefusesUSBKeyEnrollmentWhileSecurityStateIsActive() throws {
        let env = makeIsolatedEnvironment()
        defer {
            SirenSynthesizer.shared.stop()
            env.defaults.removePersistentDomain(forName: env.suiteName)
            try? FileManager.default.removeItem(at: env.tempDir)
        }

        let monitor = USBKeyMonitor(startImmediately: false)
        monitor.connectedDevicesProvider = { [yubikey, externalMouse] }
        let powerMonitor = PowerAndLidMonitor(isOnACPower: true, batteryPercentage: 100)

        let coordinator = SecurityCoordinator(
            settings: env.settings,
            powerMonitor: powerMonitor,
            journalStore: env.journalStore,
            usbMonitor: monitor,
            usbKeyVault: env.vault
        )

        func assertEnrollmentBlocked() {
            #expect(throws: USBKeyStorageError.enrollmentBlockedWhileActive) {
                try coordinator.enrollUSBKey(yubikey)
            }
            let outcome = coordinator.enrollCurrentUSBKey()
            #expect(outcome == .failed(USBKeyStorageError.enrollmentBlockedWhileActive.localizedDescription))
            #expect(coordinator.hasEnrolledUSBKey == false)
            #expect(coordinator.enrolledUSBKey == nil)
            #expect(env.settings.enrolledUSBKeySummary == nil)
            #expect(env.settings.usbKeyDisarmEnabled == false)
        }

        // .arming
        env.settings.exitDelaySeconds = 10
        coordinator.startArming(immediate: false)
        #expect(coordinator.state == .arming)
        assertEnrollmentBlocked()

        // .armed
        coordinator.completeArming()
        #expect(coordinator.state == .armed)
        assertEnrollmentBlocked()

        // .tamperPending
        coordinator.triggerTamper(source: .chargerUnplugged, immediateAlarm: false)
        #expect(coordinator.state == .tamperPending)
        assertEnrollmentBlocked()

        // .alarm
        coordinator.enterAlarm(source: .lidClosed)
        #expect(coordinator.state == .alarm)
        assertEnrollmentBlocked()
    }
}
