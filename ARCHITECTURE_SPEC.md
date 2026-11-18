# Technical Architecture Specification: USB Security Token / YubiKey Fast Disarm

**Feature Branch:** `feat/usb-security-key`  
**Target Platform:** macOS 14.0+ (Swift 6.0 strict concurrency, `Package.swift`)  
**Status:** Architecture Specification (Design Complete)

---

## 1. Overview & Goals

This specification defines the **USB Security Token / YubiKey Fast Disarm** subsystem for **Pupil**. It enables owners to register a physical USB hardware token (such as a YubiKey, Nitrokey, SoloKey, or generic USB token) as a fast physical disarm credential. When Pupil is `.armed`, `.tamperPending`, or `.alarm`, inserting the designated USB device immediately and silently disarms Pupil, stops the siren, clears countdowns and lockouts, cancels any active Touch ID prompt, releases `HardwareLockdownManager`, and dismisses `ScreenShieldView` across all displays without requiring manual PIN entry.

### Architectural Mandates
1. **100% Native Apple SDKs:** Event-driven USB hotplug detection via `IOKit` (`IOUSBHostDevice`, `IONotificationPortCreate`, `IOServiceAddMatchingNotification`) — zero polling, zero third-party libraries, zero kernel extensions.
2. **Swift 6 Strict Concurrency:** Pure value-type `Sendable` evaluator (`USBKeyDisarmEvaluator`) separated cleanly from `@MainActor @Observable` coordinator/UI layers and serial `DispatchQueue` IOKit callbacks.
3. **Zero Plaintext Serial Leakage:** Enrolled USB serial numbers are never stored in plaintext in `UserDefaults`, `TamperJournalStore` logs, or Markdown incident reports. Authoritative signatures are sealed at rest with `CryptoKit` (`AES.GCM` + salted `SHA256`) via `KeychainManager`.
4. **Non-Blocking Vault Storage:** Follows `KeychainManager.swift` and `TamperJournalStore.swift`'s established `0o600` Application Support vault pattern so ad-hoc signed builds and `swift test` runners never trigger legacy `login.keychain-db` modal password prompts.
5. **Security Boundary:** Fast disarm clears Pupil's `.armed`/`.tamperPending`/`.alarm` state and `ScreenShieldView` only; it does not attempt to bypass macOS LoginWindow, FileVault, or OS-level user session authentication.

---

## 2. Architecture Diagram

```mermaid
flowchart LR
    subgraph Hardware["IOKit USB Subsystem (Serial Utility Queue)"]
        IO["IOServiceAddMatchingNotification\n(IOUSBHostDevice Matched / Terminated)"]
        Reader["USBKeyMonitor.extractDescriptor(service:)"]
    end

    subgraph Core["Pure Evaluator & Vault"]
        Eval["USBKeyDisarmEvaluator\n(Sendable, Pure State)"]
        Vault["KeychainManager + USBKeyVault\n(AES-256-GCM + Salted SHA-256)"]
        Settings["PupilSettings\n(usbKeyDisarmEnabled, non-secret summary)"]
    end

    subgraph Hub["Coordination & UI (@MainActor)"]
        Coord["SecurityCoordinator"]
        Shield["ScreenShieldController / ScreenShieldView"]
        Notch["NotchOverlayController"]
        Siren["SirenSynthesizer & PowerAndLidMonitor"]
        UI["SensorsSettingsPage\n('USB security key')"]
    end

    IO --> Reader -->|USBDeviceEvent| Coord
    UI -->|Enroll / Remove / Toggle| Coord
    UI <--> Settings
    Coord <--> Vault
    Coord -->|evaluate(event, signature, enabled, state)| Eval
    Eval -->|".disarm(device, signature)"| Coord
    Coord -->|performValidatedDisarm| Shield
    Coord -->|performValidatedDisarm| Notch
    Coord -->|stop() & releaseSleepHoldAssertion()| Siren
```

---

## 3. Types, Protocols, and Data Models

All pure domain models live in `Sources/Pupil/Core/USBKeyDisarmEvaluator.swift` (importing `Foundation` only — no `AppKit` or `IOKit` dependency in the evaluator itself).

### 3.1 `USBDeviceDescriptor`

Represents a physical USB device observed via IOKit or injected by tests.

```swift
public struct USBDeviceDescriptor: Codable, Equatable, Hashable, Sendable, Identifiable {
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
}
```

**Normalization & Computed Properties:**
- `normalizeOptionalString(_:)`: Trims whitespace/newlines; empty results become `nil`. This guarantees `""` never acts as a false non-nil serial number.
- `isHub: Bool`: `deviceClass == 9` (`kUSBHubClass`).
- `isEligibleForEnrollment: Bool`: `vendorID > 0 && productID > 0 && !isHub && !isBuiltIn`.
- `formattedVIDPID: String`: `String(format: "0x%04X:0x%04X", vendorID, productID)`.
- `displayName: String`: Uses `productName` if non-empty; else `"\(vendorName) USB Key"` if `vendorName` is non-empty; else `"USB Key (\(formattedVIDPID))"`.
- `isKnownSecurityTokenVendor: Bool`: UX sorting hint (`true` for known hardware token vendors such as Yubico `0x1050`, Nitrokey `0x20A0`, Feitian `0x096E`, Google Titan `0x18D1`, SoloKeys `0x0483` / `0x1209`, Ledger `0x2C97`, Trezor `0x534C`). Strictly advisory for list ordering and never bypasses signature matching.
- `id: String`: Deterministic SwiftUI `Identifiable` key combining `formattedVIDPID`, `serialNumber ?? "noserial"`, `locationID`, and `registryEntryID`.
- `connectionToken: USBConnectionToken`: Physical attachment identity used for baseline tracking (see Section 3.2).

### 3.2 `USBConnectionToken`

Identifies a specific attached USB instance in `USBKeyDisarmEvaluator` across attach/detach cycles, even when a device lacks a `serialNumber`.

```swift
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
```

> **Note:** Including `registryEntryID` (populated from `IORegistryEntryGetRegistryEntryID` in live IOKit extraction, `nil` in synthetic unit tests) and `locationID` means two simultaneously plugged-in identical keys without serial numbers are still tracked independently across unplug/replug events, while synthetic tests constructing equal `USBDeviceDescriptor` values produce identical `USBConnectionToken` keys automatically.

### 3.3 `EnrolledUSBKeySignature` & `EnrolledUSBKeySummary`

`EnrolledUSBKeySignature` is the authoritative credential persisted in `KeychainManager`'s encrypted vault. `EnrolledUSBKeySummary` is the non-sensitive display projection stored in `PupilSettings` (strictly omitting `serialNumber`).

```swift
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

    public var isSerialPinned: Bool { serialNumber != nil }

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

    public var formattedVIDPID: String {
        String(format: "0x%04X:0x%04X", vendorID, productID)
    }
}
```

### 3.4 Events, Decisions, and Enrollment Outcomes

```swift
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
```

### 3.5 Hardware Monitor Protocol / Seam

To support 100% deterministic unit testing without physical USB hardware while matching existing Pupil monitors (`PowerAndLidMonitor`, `NetworkPathSentinel`, `BluetoothProximityMonitor`), define a `@MainActor` monitoring contract plus concrete `IOKit` monitor:

```swift
@MainActor
public protocol USBDeviceMonitoring: AnyObject {
    var isMonitoring: Bool { get }
    var connectedDevicesProvider: () -> [USBDeviceDescriptor] { get set }
    var onUSBEvent: ((USBDeviceEvent) -> Void)? { get set }
    func startMonitoring()
    func stopMonitoring()
}
```

`USBKeyMonitor` (`Sources/Pupil/Core/USBKeyMonitor.swift`) conforms to `USBDeviceMonitoring` and is marked `@MainActor @Observable public final class USBKeyMonitor`.

---

## 4. Pure Logic Evaluator (`USBKeyDisarmEvaluator`)

`USBKeyDisarmEvaluator` (`Sources/Pupil/Core/USBKeyDisarmEvaluator.swift`) is a pure `Sendable`, `Equatable` struct with deterministic state transition logic and zero side effects.

### 4.1 Evaluator State & API

```swift
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
    ) -> USBKeyDisarmDecision

    /// Reconciles a full connected-device snapshot against `baselineConnectionTokens`,
    /// returning `.disarm` for the first newly attached matching device, if any.
    public mutating func evaluateSnapshot(
        _ devices: [USBDeviceDescriptor],
        enrolledSignature: EnrolledUSBKeySignature?,
        featureEnabled: Bool,
        securityState: SecurityState,
        at timestamp: TimeInterval? = nil
    ) -> USBKeyDisarmDecision
}
```

### 4.2 Evaluation Order & Rules (`evaluate`)

When `evaluate(event:enrolledSignature:featureEnabled:securityState:at:)` runs:

1. **Handle `.disconnected(device)` first (always updates baseline):**
   - Remove `device.connectionToken` from `baselineConnectionTokens`.
   - Return `.ignored(reason: .disconnectEvent)`.
   - *Why first?* Even while disabled or in `.arming`, removing unplugged devices keeps `baselineConnectionTokens` accurate so plugging the key back in later is recognized as a fresh insertion.
2. **Handle `.connected(device)`:**
   - Compute `token = device.connectionToken`.
   - **Pre-attached check:** If `baselineConnectionTokens.contains(token)`, return `.ignored(reason: .alreadyConnectedAtBaseline)`.
   - **Record token in baseline:** Insert `token` into `baselineConnectionTokens`?
     - *Careful subtlety:* Wait to insert into `baselineConnectionTokens` OR insert immediately?
       - If inserted immediately before feature/state gates: suppose the user inserts their key while `.disarmed`, leaves it plugged in, then arms -> `startArming()` calls `latchBaseline(...)` anyway. Suppose the user inserts an unrecognized USB drive while `.armed` -> inserting into `baselineConnectionTokens` prevents duplicate re-evaluation of the same attachment. Suppose the user inserts the enrolled key while `.armed` -> inserts into `baselineConnectionTokens`, returns `.disarm(...)`, and coordinator disarms and calls `reset()`.
       - Therefore inserting `token` into `baselineConnectionTokens` on `.connected` (after checking `contains(token)`) accurately models physical connection state at all times!
   - **Hub / Built-in gate:** If `device.isHub || device.isBuiltIn`, return `.ignored(reason: .hubOrBuiltInDevice)`.
   - **Feature gate:** Guard `featureEnabled` else return `.ignored(reason: .featureDisabled)`.
   - **Enrollment gate:** Guard `let signature = enrolledSignature` else return `.ignored(reason: .noEnrolledKey)`.
   - **Security state gate:** Guard `Self.activeDisarmStates.contains(securityState)` (`.armed`, `.tamperPending`, `.alarm`) else return `.ignored(reason: .inactiveSecurityState(securityState))`.
     - *Design Decision on `.arming` and `.disarmed`:* `.disarmed` is already idle. `.arming` (exit delay) is excluded just like `SecurityCoordinator.disarmViaRemotePhone()` so exit delay cannot be inadvertently aborted while unplugging or re-enumerating hardware before stepping away; once armed (`.armed`), counting down (`.tamperPending`), or sounding (`.alarm`), insertion disarms immediately.
   - **Descriptor signature match:** Guard `signature.matches(device)` else return `.ignored(reason: .nonMatchingDevice)`.
   - **Optional time-based debounce guard:** If `let ts = timestamp`, `let last = lastMatchedTimestamp`, `(ts - last) < debounceIntervalSeconds`, return `.ignored(reason: .debounced)`.
   - **Success:** If `let ts = timestamp`, set `lastMatchedTimestamp = ts`. Return `.disarm(matchedDevice: device, signature: signature)`.

### 4.3 Snapshot Reconciliation Rules (`evaluateSnapshot`)

Mirroring `DisplayTopologyEvaluator.evaluate(_:)`:
1. Compute `currentTokens = Set(devices.map(USBConnectionToken.init(from:)))`.
2. If `!hasBaseline`:
   - `baselineConnectionTokens = currentTokens`
   - `hasBaseline = true`
   - Return `.ignored(reason: .alreadyConnectedAtBaseline)`.
3. Compute `addedTokens = currentTokens.subtracting(baselineConnectionTokens)`.
4. Update `baselineConnectionTokens = currentTokens`.
5. Filter `devices` where `addedTokens.contains(device.connectionToken)`.
6. Evaluate candidate added devices in order against feature gate, enrollment, active state, non-hub/non-built-in, `signature.matches(device)`, and debounce:
   - Return `.disarm` on the first match, or the highest-priority `.ignored(reason:)` if none match.

### 4.4 Matching Matrix (Serial Number Semantics)

| Enrolled `serialNumber` | Observed `serialNumber` | VID & PID Match? | Result | Rationale |
|---|---|---|---|---|
| `"24681357"` | `"24681357"` | Yes | **Match (`.disarm`)** | Exact serial-pinned token verified |
| `"24681357"` | `"99999999"` | Yes | **Reject (`.nonMatchingDevice`)** | Different physical token of same model (e.g., attacker's YubiKey) |
| `"24681357"` | `nil` / `""` | Yes | **Reject (`.nonMatchingDevice`)** | Missing serial cannot satisfy serial-pinned enrollment |
| `nil` | `nil` | Yes | **Match (`.disarm`)** | Token without USB serial descriptor matched by VID/PID |
| `nil` | `"11223344"` | Yes | **Match (`.disarm`)** | Enrolled without serial pinning; VID/PID matched |
| Any | Any | No | **Reject (`.nonMatchingDevice`)** | Wrong vendor or product ID |

---

## 5. Settings & Keychain Vault Schema

### 5.1 `PupilSettings` Schema (`Sources/Pupil/Settings/PupilSettings.swift`)

Add the following `@Observable` persisted properties and `Keys` entries to `PupilSettings`:

```swift
public var usbKeyDisarmEnabled: Bool {
    didSet {
        defaults.set(usbKeyDisarmEnabled, forKey: Keys.usbKeyDisarmEnabled)
        NotificationCenter.default.post(name: .screenShieldSync, object: nil)
    }
}

/// Non-sensitive UI display projection (never contains `serialNumber`).
/// Authoritative matching always reads `EnrolledUSBKeySignature` from `KeychainManager` / `USBKeyVault`.
public var enrolledUSBKeySummary: EnrolledUSBKeySummary? {
    didSet {
        if let enrolledUSBKeySummary,
           let encoded = try? JSONEncoder().encode(enrolledUSBKeySummary) {
            defaults.set(encoded, forKey: Keys.enrolledUSBKeySummary)
        } else {
            defaults.removeObject(forKey: Keys.enrolledUSBKeySummary)
        }
    }
}
```

In `PupilSettings.init(defaults:)`:
```swift
self.usbKeyDisarmEnabled = defaults.object(forKey: Keys.usbKeyDisarmEnabled) as? Bool ?? false
if let summaryData = defaults.data(forKey: Keys.enrolledUSBKeySummary),
   let summary = try? JSONDecoder().decode(EnrolledUSBKeySummary.self, from: summaryData) {
    self.enrolledUSBKeySummary = summary
} else {
    self.enrolledUSBKeySummary = nil
}
```

In `PupilSettings.Keys`:
```swift
static let usbKeyDisarmEnabled = "pupil.usbKeyDisarmEnabled"
static let enrolledUSBKeySummary = "pupil.enrolledUSBKeySummary"
```

### 5.2 `KeychainManager` & `USBKeyVault` Schema (`Sources/Pupil/Core/KeychainManager.swift`)

Following `KeychainManager` and `TamperJournalStore`'s non-blocking encrypted vault architecture (preventing legacy macOS Keychain prompt dialogs on ad-hoc builds and headless `swift test` runners):

#### Storage Errors & Envelope
```swift
public enum USBKeyStorageError: LocalizedError, Sendable, Equatable {
    case invalidDeviceDescriptor
    case corruptedSealedRecord
    case encryptionFailed
    case noEnrolledKey

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
}
```

#### `USBKeyVault` (`Sendable`)
Mirrors `TamperJournalStore` (`NSLock` thread safety + `CryptoKit.AES.GCM` + `0o600` file permissions):
- **Shared Instance:** `USBKeyVault.shared`
  - **Record File:** `~/Library/Application Support/Pupil/usb-key.record` (`0o600` POSIX permissions; parent directory `0o700`)
  - **Vault Key File:** `~/Library/Application Support/Pupil/usb-key.key` (`0o600` POSIX permissions) + `UserDefaults.standard` fallback key `"pupil.usbKeyVaultSymmetricKey"` (256-bit `SymmetricKey`)
- **Test Isolation:** `USBKeyVault(fileURL: URL, symmetricKey: SymmetricKey)` allows `SecurityCoordinator` and unit tests to isolate credentials in ephemeral temporary storage without touching the host Mac's enrolled key.
- **Cryptographic Operations on `save(_ signature:)`:**
  1. Generate 16 random salt bytes via `SecRandomCopyBytes` -> `saltHex`.
  2. Compute `signatureDigestHex = SHA256(saltHex + ":" + signature.canonicalSignature)`.
  3. JSON-encode `signature` (`iso8601` date strategy) and seal with `AES.GCM.seal(plaintext, using: key)`.
  4. Write `EncryptedUSBKeyEnvelope` atomically to `fileURL` with `0o600` POSIX permissions.
- **Cryptographic Operations on `load() -> EnrolledUSBKeySignature?`:**
  1. Decode `EncryptedUSBKeyEnvelope` and verify `schemaVersion == 1`.
  2. Open `AES.GCM.SealedBox(combined:)` using `key` (tampered ciphertext or wrong key fails GCM tag verification and returns `nil` / throws `corruptedSealedRecord`).
  3. Decode `EnrolledUSBKeySignature` and verify constant-time equality (`KeychainManager.constantTimeEqual`) of `SHA256(envelope.saltHex + ":" + signature.canonicalSignature)` against `envelope.signatureDigestHex`.

#### `KeychainManager` Public USB Key API
```swift
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

    nonisolated public static func clearEnrolledUSBKey(vault: USBKeyVault = .shared) {
        try? vault.clear()
    }
}
```

#### Tamper-Resistance Invariant
`SecurityCoordinator` **never** authorizes fast disarm from `PupilSettings.enrolledUSBKeySummary` (`UserDefaults`). Matching always runs exclusively against `enrolledUSBKey` loaded from `KeychainManager` (`USBKeyVault`), ensuring that modifying `UserDefaults` plist files alone cannot spoof an arbitrary USB flash drive as a disarm key.

---

## 6. Hardware Monitor (`USBKeyMonitor`)

`Sources/Pupil/Core/USBKeyMonitor.swift` implements event-driven USB attach/detach detection using `IOKit`.

### 6.1 IOKit Hotplug Lifecycle
1. **Service Matching:** Matches `"IOUSBHostDevice"` (`kIOUSBHostDeviceClassName`), consistent with `PowerAndLidMonitor.readUSBDeviceCount()`. Using `IOUSBHostDevice` (rather than `IOUSBHostInterface`) emits **one** notification per physical device insertion even for composite tokens like YubiKey 5 (CCID + FIDO HID + OTP).
2. **Dispatch Integration:**
   - Creates `IONotificationPortCreate(kIOMainPortDefault)` and attaches it to a serial queue `DispatchQueue(label: "com.pupil.usb.monitor", qos: .userInitiated)` via `IONotificationPortSetDispatchQueue`.
   - Registers two separate matching dictionaries (each `IOServiceMatching("IOUSBHostDevice")` call creates an independent `CFMutableDictionary`, since `IOServiceAddMatchingNotification` consumes one reference per registration):
     - `kIOMatchedNotification` -> handles attach events
     - `kIOTerminatedNotification` -> handles detach events
   - Uses a `CallbackBox: @unchecked Sendable` (`weak var monitor: USBKeyMonitor?`) passed via `Unmanaged.passRetained` and released cleanly in `stopMonitoring()` so `@convention(c)` IOKit callbacks comply with Swift 6 strict concurrency without dangling pointers.
3. **Mandatory Initial Drain:** Immediately drains both iterators upon registration:
   - Draining `matchedIterator` arms future kernel attach callbacks and populates initial connected devices **without** emitting `.connected` events for pre-existing hardware.
   - Draining `terminatedIterator` arms future kernel detach callbacks without emitting spurious `.disconnected` events.
4. **Descriptor Extraction (`extractDescriptor(from service: io_service_t) -> USBDeviceDescriptor?`):**
   Reads IORegistry properties via `IORegistryEntryCreateCFProperties`:
   - `vendorID`: `"idVendor"` (`NSNumber` -> `UInt16`)
   - `productID`: `"idProduct"` (`NSNumber` -> `UInt16`)
   - `serialNumber`: `"kUSBSerialNumberString"` (fallback `"USB Serial Number"`)
   - `productName`: `"kUSBProductString"` (fallback `"USB Product Name"`)
   - `vendorName`: `"kUSBVendorString"` (fallback `"USB Vendor Name"`)
   - `locationID`: `"locationID"` (`NSNumber` -> `UInt32`)
   - `deviceClass`: `"bDeviceClass"` (`NSNumber` -> `UInt8`)
   - `isBuiltIn`: `"BuiltIn"` or `"built-in"` (`Bool`)
   - `registryEntryID`: `IORegistryEntryGetRegistryEntryID(service, &entryID)`
   - Always calls `IOObjectRelease(service)` for every yielded object.
5. **On-Demand Snapshot (`readConnectedUSBDevices() -> [USBDeviceDescriptor]`):**
   `nonisolated public static func readConnectedUSBDevices() -> [USBDeviceDescriptor]` iterates `IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator)` and returns all parsed descriptors (used for Settings enrollment and arming baseline latching even before monitoring starts).
6. **Test Injection:**
   - `public var connectedDevicesProvider: () -> [USBDeviceDescriptor] = { USBKeyMonitor.readConnectedUSBDevices() }`
   - `public func ingestEventForTesting(_ event: USBDeviceEvent)` forwards `onUSBEvent?(event)` directly on `@MainActor`.

---

## 7. Coordinator Wiring & Disarm Pipeline

### 7.1 `SecurityCoordinator` Additions (`Sources/Pupil/Core/SecurityCoordinator.swift`)

#### Properties & Initialization
```swift
public let usbMonitor: USBKeyMonitor
public let usbKeyVault: USBKeyVault
public internal(set) var usbKeyEvaluator = USBKeyDisarmEvaluator()
public private(set) var enrolledUSBKey: EnrolledUSBKeySignature?
public var hasEnrolledUSBKey: Bool { enrolledUSBKey != nil }
public private(set) var availableUSBDevicesForEnrollment: [USBDeviceDescriptor] = []
```

`SecurityCoordinator.init` accepts two optional defaulted parameters (preserving full backwards compatibility with all existing call sites and tests):
```swift
usbMonitor: USBKeyMonitor? = nil,
usbKeyVault: USBKeyVault? = nil
```
Vault isolation follows the exact `TamperJournalStore` pattern (`SecurityCoordinator.swift` lines 207–216):
- If `usbKeyVault != nil`, use it.
- Else if `settings === PupilSettings.shared`, use `USBKeyVault.shared`.
- Else create an isolated temp `USBKeyVault` in `FileManager.default.temporaryDirectory` with an ephemeral `SymmetricKey(size: .bits256)`.

Default `usbMonitor` is `USBKeyMonitor(startImmediately: false)`. On `init`:
1. Load `enrolledUSBKey = KeychainManager.loadEnrolledUSBKey(vault: resolvedUSBKeyVault)`.
2. Reconcile `settings.enrolledUSBKeySummary = enrolledUSBKey?.summary`.
3. In `bindSensors()`, wire:
   ```swift
   usbMonitor.onUSBEvent = { [weak self] event in
       self?.handleUSBKeyEvent(event)
   }
   ```
4. Call `syncUSBKeyMonitoring()`, and also call `syncUSBKeyMonitoring()` inside the `.screenShieldSync` `NotificationCenter` observer.

#### `syncUSBKeyMonitoring()`
```swift
public func syncUSBKeyMonitoring() {
    if settings.usbKeyDisarmEnabled && hasEnrolledUSBKey {
        usbMonitor.startMonitoring()
    } else {
        usbMonitor.stopMonitoring()
        usbKeyEvaluator.reset()
    }
}
```
Only listens to IOKit USB notifications when both `settings.usbKeyDisarmEnabled` is `true` and a key is enrolled.

#### Baseline Latching on Arm
- In `startArming(immediate:)`:
  `usbKeyEvaluator.latchBaseline(usbMonitor.connectedDevicesProvider())`
- In `completeArming()`:
  `usbKeyEvaluator.latchBaseline(usbMonitor.connectedDevicesProvider())`

#### Fast Disarm Handling (`handleUSBKeyEvent`)
```swift
public func handleUSBKeyEvent(_ event: USBDeviceEvent) {
    let decision = usbKeyEvaluator.evaluate(
        event: event,
        enrolledSignature: enrolledUSBKey,
        featureEnabled: settings.usbKeyDisarmEnabled,
        securityState: state,
        at: clock()
    )
    if case .disarm(_, let signature) = decision {
        performValidatedDisarm(method: "USB Security Key (\(signature.displayName))")
    }
}
```

#### Critical `performValidatedDisarm(method:)` Guarantees
When `performValidatedDisarm(method:)` runs during USB fast disarm:
1. `idleEvaluator.suppressCurrentStreak()` prevents immediate idle auto-arm re-triggering.
2. `resetPinLockout()` clears any active `PinAttemptLimiter` lockout (`pinLockoutSecondsRemaining = 0`).
3. `KeychainManager.cancelPendingAuthentication()` invalidates and dismisses any active Touch ID `LAContext` modal sheet.
4. `countdownTimer` and `alarmReminderTimer` are invalidated; `countdownSecondsRemaining = 0`, `alarmStartTime = nil`.
5. `SirenSynthesizer.shared.stop()` immediately silences any active alarm and restores system audio.
6. `powerMonitor.releaseSleepHoldAssertion()` releases `IOPMAssertion` sleep holds.
7. `state` transitions to `.disarmed`; `activeTamperSource`, `activeTamperTime`, `activeAlarmTime` clear to `nil`; `isGazeWarningActive`, `isShieldPreviewActive`, `isInteractiveUnlockRequested` clear to `false`.
8. `usbKeyEvaluator.reset()` clears evaluator baseline/debounce state.
9. `logEvent("Disarmed", detail: "Session disarmed via \(method).")` records the event in encrypted `TamperJournalStore` (only `displayName` is included — never raw `serialNumber`).
10. `onStateChanged?(state)`, `onNotchUpdateNeeded?()`, **and `NotificationCenter.default.post(name: .screenShieldSync, object: nil)`** are dispatched so `ScreenShieldController.syncWithCoordinator()` always calls `hideShield()`, calling `HardwareLockdownManager.shared.release()` and tearing down all `ScreenShieldWindow` instances across every display — even if `AppDelegate` callbacks are not attached (e.g., isolated controller tests).

> **Existing Gap Addressed:** Currently `performValidatedDisarm(method:)` in `SecurityCoordinator.swift` invokes `onStateChanged?(state)` without posting `.screenShieldSync`. Adding `NotificationCenter.default.post(name: .screenShieldSync, object: nil)` inside `performValidatedDisarm(method:)` guarantees deterministic `ScreenShieldView` dismissal across all integration paths.

#### Enrollment & Removal API
- `refreshEnrollableUSBDevices() -> [USBDeviceDescriptor]`:
  Reads `usbMonitor.connectedDevicesProvider()`, filters `.isEligibleForEnrollment`, sorts with `isKnownSecurityTokenVendor == true` first then alphabetically by `displayName`, stores in `availableUSBDevicesForEnrollment`, and returns the sorted array.
- `enrollCurrentUSBKey() -> USBEnrollmentOutcome`:
  - `candidates = refreshEnrollableUSBDevices()`
  - `candidates.isEmpty` -> `.noDeviceFound`
  - `candidates.count == 1` -> calls `enrollUSBKey(candidates[0])`, returns `.enrolled(signature)`
  - `candidates.count > 1` -> returns `.requiresSelection(candidates)`
- `enrollUSBKey(_ device: USBDeviceDescriptor) throws -> EnrolledUSBKeySignature`:
  - Calls `KeychainManager.enrollUSBKey(device, vault: usbKeyVault)`.
  - Updates `enrolledUSBKey`, `settings.enrolledUSBKeySummary`, sets `settings.usbKeyDisarmEnabled = true`.
  - Latches `usbKeyEvaluator.latchBaseline(usbMonitor.connectedDevicesProvider())`.
  - Calls `syncUSBKeyMonitoring()`.
  - Logs `"USB Key Enrolled"` with `displayName`, `formattedVIDPID`, and `"serial-pinned"` / `"model-matched"` (no raw serial number).
- `removeEnrolledUSBKey()`:
  - Calls `KeychainManager.clearEnrolledUSBKey(vault: usbKeyVault)`.
  - Clears `enrolledUSBKey = nil`, `settings.enrolledUSBKeySummary = nil`, `settings.usbKeyDisarmEnabled = false`.
  - Calls `syncUSBKeyMonitoring()`.
  - Logs `"USB Key Removed"`.

### 7.2 Cross-Subsystem Interactions

| Subsystem | Interaction Behavior |
|---|---|
| `PowerAndLidMonitor` (`peripheralDisconnect`) | Inserting a USB key increments `usbCount` (does not fire disconnect). Transition to `.disarmed` completes synchronously before any future removal, so unplugging the key *after* disarming is ignored while `.disarmed`. |
| `ScreenShieldController` / `HardwareLockdownManager` | `.screenShieldSync` + `onStateChanged` immediately invoke `hideShield()` -> `HardwareLockdownManager.shared.release()` + `destroyWindows()`. |
| `Touch ID` (`LAContext`) | `KeychainManager.cancelPendingAuthentication()` dismisses any open Touch ID prompt immediately on USB key insertion. |
| `PinAttemptLimiter` | `resetPinLockout()` resets failed-attempt counters and active lockouts immediately upon valid USB key disarm. |
| `IdleInactivityEvaluator` | `idleEvaluator.suppressCurrentStreak()` prevents immediate idle auto-arm after USB disarm until fresh user input occurs. |
| `AlertNotifier` | Silent during `.armed` and `.tamperPending` disarm (zero push alerts, zero chimes, zero modals). When silencing an active `.alarm`, dispatches `"Pupil Disarmed"` phone push matching existing alarm-silence behavior. |

---

## 8. Settings UI Specification (`SensorsSettingsPage.swift`)

### Placement Rationale
`SensorsSettingsPage.swift` already houses hardware peripherals, device enrollment, and physical auto-disarm controls (`Phone Companion` and `Bluetooth Proximity`), whereas `GeneralSettingsPage.swift` houses core app preferences, built-in Touch ID, delays, and Disarm PIN. Placing **USB security key** in `SensorsSettingsPage.swift` (immediately below `Bluetooth Proximity`) maintains clear functional symmetry across all hardware/token disarm mechanisms.

### UI Structure & Sentence-Case Design Rules
Using existing `SettingsControls.swift` primitives (`SettingsSectionTitle`, `SettingsGroup`, `SettingsGroupDivider`, `SettingsRowContent`, `PupilToggle`, `PillActionButton`, `SettingsCaption`):

1. **Section Header:**
   `SettingsSectionTitle(text: "USB security key")`
2. **Row 1 — Toggle Row (`SettingsRowContent`):**
   - **Title:** `"Disarm with USB key"`
   - **Subtitle:** `"Automatically and silently disarms Pupil when your enrolled USB security key is inserted."`
   - **Info popover (`SettingsInfoButton`):** `"Matches your enrolled key by USB vendor ID, product ID, and serial number (when exposed by the token) via native IOKit hotplug events."`
   - **Trailing control:** `PupilToggle(isOn: $settings.usbKeyDisarmEnabled)`
3. **Divider:** `SettingsGroupDivider()`
4. **Row 2 — Enrollment Row (`SettingsRowContent`):**
   - **Title:** `"Enrolled key"`
   - **Subtitle:**
     - If `let enrolled = coordinator.enrolledUSBKey`:
       `"\(enrolled.displayName) · \(enrolled.formattedVIDPID) · \(enrolled.isSerialPinned ? "Serial pinned" : "Model match")"`
     - Else if `let summary = settings.enrolledUSBKeySummary`:
       `"\(summary.displayName) · \(summary.formattedVIDPID)"`
     - Else:
       `"No USB key enrolled. Plug in your YubiKey, Nitrokey, or USB token."`
   - **Trailing controls (`HStack(spacing: 8)`):**
     - Conditional when `coordinator.hasEnrolledUSBKey`: `PillActionButton(title: "Remove")` -> calls `coordinator.removeEnrolledUSBKey()`.
     - Primary action: `PillActionButton(title: "Enroll current USB key")` -> calls `coordinator.enrollCurrentUSBKey()`:
       - `.enrolled(sig)`: updates inline status `"Enrolled \(sig.displayName)."`.
       - `.noDeviceFound`: updates inline status `"No external USB key detected. Insert your USB key and try again."`.
       - `.requiresSelection(devices)`: presents a compact `.popover(isPresented: $showUSBDeviceChooser, arrowEdge: .bottom)` listing `"Choose USB key"` with each candidate (`device.displayName`, `device.formattedVIDPID`, and `"Serial available"` / `"No serial"` badge); selecting a row calls `try? coordinator.enrollUSBKey(device)`.
       - `.failed(message)`: displays `message` inline.
5. **Conditional Inline Status Footer:**
   Shown inside `SettingsGroup` below a `SettingsGroupDivider()` when `usbStatusMessage` is non-nil (mirroring `Phone Companion`'s status footer row in `SensorsSettingsPage.swift`).

---

## 9. Deterministic Test Plan

All unit and integration tests live in `Tests/PupilTests/USBKeyDisarmTests.swift` under `@Suite("USB Security Key Fast Disarm Tests", .serialized)`. Every test uses synthetic `USBDeviceDescriptor` values, isolated `UserDefaults(suiteName:)`, and temporary `USBKeyVault` instances — zero physical USB hardware is required.

| # | Test Name | Layer | Scenario & Assertions |
|---|---|---|---|
| 1 | `testExactMatchWithVendorProductAndSerial` | `USBKeyDisarmEvaluator` | Enroll YubiKey (`0x1050:0x0407`, serial `"24681357"`). Verify `.connected` with identical VID/PID/serial returns `.disarm` in `.armed`, `.tamperPending`, and `.alarm` states when `featureEnabled == true`. |
| 2 | `testRejectsDifferentOrMissingSerialWhenSerialPinned` | `USBKeyDisarmEvaluator` | Enroll serial-pinned YubiKey (`"24681357"`). Verify inserting a second YubiKey of the exact same model (`0x1050:0x0407`, serial `"99999999"`), a device with `serialNumber: nil`, or a device with a different VID/PID all return `.ignored(reason: .nonMatchingDevice)`. |
| 3 | `testOptionalSerialNumberMatchesByVIDPIDOnly` | `USBKeyDisarmEvaluator` | Enroll generic USB token with `serialNumber: nil`. Verify inserting matching VID/PID (whether observed descriptor has `serialNumber: nil` or non-nil) returns `.disarm`. |
| 4 | `testPreConnectedBaselineIgnoredUntilUnpluggedAndReinserted` | `USBKeyDisarmEvaluator` | Call `latchBaseline([enrolledKey])` before arming. Verify immediate `.connected(enrolledKey)` or `evaluateSnapshot([enrolledKey])` returns `.ignored(reason: .alreadyConnectedAtBaseline)`. Send `.disconnected(enrolledKey)`, then `.connected(enrolledKey)` -> returns `.disarm`. |
| 5 | `testEvaluatorFeatureStateHubAndDebounceGuards` | `USBKeyDisarmEvaluator` | Verify `.ignored(reason: .featureDisabled)` when disabled, `.ignored(reason: .noEnrolledKey)` when nil, `.ignored(reason: .inactiveSecurityState(.disarmed))` and `.inactiveSecurityState(.arming)`, `.ignored(reason: .hubOrBuiltInDevice)` when `deviceClass == 9` or `isBuiltIn == true`, `.ignored(reason: .disconnectEvent)` on `.disconnected`, and `.ignored(reason: .debounced)` within `debounceIntervalSeconds`. |
| 6 | `testKeychainVaultEncryptsAndDetectsTampering` | `KeychainManager` / `USBKeyVault` | Enroll `USBDeviceDescriptor` into isolated `USBKeyVault` (`0o600` file permissions). Verify raw file bytes and `UserDefaults` do not contain plaintext `serialNumber`. Verify `loadEnrolledUSBKey(vault:)` restores exact fields, and loading with wrong `SymmetricKey` or tampered envelope bytes fails cleanly (`nil` / throws `.corruptedSealedRecord`). |
| 7 | `testPupilSettingsUSBKeyPersistence` | `PupilSettings` | Using isolated `UserDefaults(suiteName:)`, verify `usbKeyDisarmEnabled` defaults to `false`, `enrolledUSBKeySummary` defaults to `nil`, both persist across `PupilSettings(defaults:)` reloads, and mutating `usbKeyDisarmEnabled` posts `.screenShieldSync`. |
| 8 | `testCoordinatorFastDisarmFromArmedClearsScreenShieldAndInteractiveUnlock` | `SecurityCoordinator` + `ScreenShieldController` | Enroll YubiKey, arm coordinator (`immediate: true`), trigger `handleArmedUserInput()` (`isInteractiveUnlockRequested == true`), and sync `ScreenShieldController`. Inject `.connected(enrolledYubiKey)` via `usbMonitor.ingestEventForTesting`. Verify `state == .disarmed`, `isInteractiveUnlockRequested == false`, `idleEvaluator.isSuppressedForCurrentStreak == true`, and journal records `"Disarmed"` without exposing raw serial number. |
| 9 | `testCoordinatorFastDisarmClearsTamperCountdownAlarmSirenAndLockout` | `SecurityCoordinator` | Trigger `.tamperPending` and `.alarm`, record failed PIN attempts to activate `PinAttemptLimiter` lockout (`isPinLockedOut == true`). Inject `.connected(enrolledYubiKey)` via `usbMonitor.ingestEventForTesting`. Verify immediate transition to `.disarmed`, `countdownSecondsRemaining == 0`, `activeTamperSource == nil`, `pinLockoutSecondsRemaining == 0`, `SirenSynthesizer.shared.isActive == false`, `powerMonitor.isSleepAssertionActive == false`, and `.screenShieldSync` notification posted. |
| 10 | `testCoordinatorEnrollmentOutcomesAndIgnoredTriggers` | `SecurityCoordinator` | Mock `usbMonitor.connectedDevicesProvider` for `[]` / `[hub]` -> `.noDeviceFound`; `[yubikey]` -> `.enrolled` (auto-enables `usbKeyDisarmEnabled`); `[mouse, yubikey]` -> `.requiresSelection([yubikey, mouse])` sorted with security-token vendor first. Also verify unrecognized USB devices and `usbKeyDisarmEnabled = false` leave `.armed`/`.tamperPending` unchanged. |

---

## 10. File Impact Summary

| File | Action | Purpose |
|---|---|---|
| `Sources/Pupil/Core/USBKeyDisarmEvaluator.swift` | **Create** | Pure `Sendable` models (`USBDeviceDescriptor`, `EnrolledUSBKeySignature`, `EnrolledUSBKeySummary`, `USBDeviceEvent`, `USBKeyDisarmDecision`, `USBEnrollmentOutcome`) and `USBKeyDisarmEvaluator` |
| `Sources/Pupil/Core/USBKeyMonitor.swift` | **Create** | `USBDeviceMonitoring` protocol + `@MainActor @Observable USBKeyMonitor` using event-driven `IOKit` `IOUSBHostDevice` notifications |
| `Sources/Pupil/Core/KeychainManager.swift` | **Modify** | Add `USBKeyStorageError`, `EncryptedUSBKeyEnvelope`, `USBKeyVault`, and `KeychainManager` USB key enroll/load/verify/clear APIs |
| `Sources/Pupil/Settings/PupilSettings.swift` | **Modify** | Add `usbKeyDisarmEnabled` and non-sensitive `enrolledUSBKeySummary` properties & `Keys` |
| `Sources/Pupil/Core/SecurityCoordinator.swift` | **Modify** | Wire `usbMonitor`, `usbKeyVault`, `usbKeyEvaluator`, baseline latching on arm, `handleUSBKeyEvent`, `enrollCurrentUSBKey` / `removeEnrolledUSBKey`, and post `.screenShieldSync` in `performValidatedDisarm` |
| `Sources/Pupil/Settings/Pages/SensorsSettingsPage.swift` | **Modify** | Add sentence-case `"USB security key"` section with `"Disarm with USB key"` toggle, `"Enroll current USB key"` / `"Remove"` buttons, and multi-device chooser popover |
| `Tests/PupilTests/USBKeyDisarmTests.swift` | **Create** | 10 deterministic unit & integration tests covering evaluator, vault crypto/tampering, settings, coordinator disarm, `ScreenShieldController` sync, and enrollment |
