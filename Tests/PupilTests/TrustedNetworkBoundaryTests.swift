//
//  TrustedNetworkBoundaryTests.swift
//  PupilTests
//
//  Deterministic unit and integration tests for NetworkIdentifierHasher,
//  TrustedNetworkEvaluator, PupilSettings trusted-network persistence,
//  TrustedNetworkMonitor, and SecurityCoordinator boundary policy wiring.
//

import Foundation
import Network
import Testing
@testable import Pupil

private final class MockTrustedNetworkIdentityProvider: TrustedNetworkIdentityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _permission: LocationPermissionState
    private var _snapshot: NetworkIdentitySnapshot
    private(set) var permissionRequestCount = 0

    init(
        permission: LocationPermissionState = .authorized,
        snapshot: NetworkIdentitySnapshot
    ) {
        self._permission = permission
        self._snapshot = snapshot
    }

    func setPermission(_ permission: LocationPermissionState) {
        lock.lock()
        _permission = permission
        lock.unlock()
    }

    func setSnapshot(_ snapshot: NetworkIdentitySnapshot) {
        lock.lock()
        _snapshot = snapshot
        lock.unlock()
    }

    func currentLocationPermission() -> LocationPermissionState {
        lock.lock()
        defer { lock.unlock() }
        return _permission
    }

    func requestLocationPermissionIfNeeded() {
        lock.lock()
        permissionRequestCount += 1
        lock.unlock()
    }

    func captureSnapshot(from path: NWPath?, at timestamp: TimeInterval) -> NetworkIdentitySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return NetworkIdentitySnapshot(
            isSatisfied: _snapshot.isSatisfied,
            primaryInterface: _snapshot.primaryInterface,
            interfaceName: _snapshot.interfaceName,
            ssidHash: _snapshot.ssidHash,
            bssidHash: _snapshot.bssidHash,
            gatewayMACHash: _snapshot.gatewayMACHash,
            interfaceHash: _snapshot.interfaceHash,
            suggestedDisplayName: _snapshot.suggestedDisplayName,
            locationPermission: _permission,
            capturedAt: timestamp
        )
    }
}

@Suite("Trusted Wi-Fi Boundary Sentinel Tests", .serialized)
struct TrustedNetworkBoundaryTests {

    @MainActor
    private func makeIsolatedSettings() -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.trustedwifi.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    private func makeHomeEntry(
        ssid: String? = "HomeWiFi",
        bssid: String? = "aa:bb:cc:11:22:33",
        gatewayMAC: String? = "00:11:22:33:44:55",
        interfaceHash: String? = "if-hash-home",
        source: NetworkFingerprintSource = .ssid,
        requireBSSIDPinning: Bool = false
    ) -> TrustedNetworkEntry {
        TrustedNetworkEntry(
            displayName: "Home Wi-Fi",
            ssidHash: NetworkIdentifierHasher.hashSSID(ssid),
            bssidHash: NetworkIdentifierHasher.hashBSSID(bssid),
            gatewayMACHash: NetworkIdentifierHasher.hashGatewayMAC(gatewayMAC),
            interfaceHash: interfaceHash,
            enrolledSource: source,
            requireBSSIDPinning: requireBSSIDPinning
        )
    }

    private func makeWiFiSnapshot(
        ssid: String? = nil,
        bssid: String? = nil,
        gatewayMAC: String? = nil,
        interfaceHash: String? = nil,
        suggestedDisplayName: String? = nil,
        permission: LocationPermissionState = .authorized,
        at timestamp: TimeInterval = 100.0
    ) -> NetworkIdentitySnapshot {
        NetworkIdentitySnapshot(
            isSatisfied: true,
            primaryInterface: .wifi,
            interfaceName: "en0",
            ssidHash: NetworkIdentifierHasher.hashSSID(ssid),
            bssidHash: NetworkIdentifierHasher.hashBSSID(bssid),
            gatewayMACHash: NetworkIdentifierHasher.hashGatewayMAC(gatewayMAC),
            interfaceHash: interfaceHash,
            suggestedDisplayName: suggestedDisplayName ?? ssid,
            locationPermission: permission,
            capturedAt: timestamp
        )
    }

    // MARK: - 1. Disabled or Empty Enrolled List

    @Test("Disabled or empty enrolled list never arms or escalates sensitivity")
    func disabledOrEmptyEnrolledListNeverArmsOrEscalates() {
        var evaluator = TrustedNetworkEvaluator()
        let untrusted = makeWiFiSnapshot(ssid: "PublicCafe", gatewayMAC: "de:ad:be:ef:00:01", at: 100.0)
        let home = makeHomeEntry()

        // Feature disabled
        let disabledOut = evaluator.evaluate(
            snapshot: untrusted,
            enrolledNetworks: [home],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: false),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 100.0
        )
        #expect(disabledOut.posture == .disabled)
        #expect(disabledOut.shouldAutoArm == false)
        #expect(disabledOut.updatedGazeSensitivity == nil)
        #expect(disabledOut.newBaselineSensitivityToSave == nil)

        // Enabled, but empty enrolled list -> unconfigured fail-safe (prevents self-lockout)
        let emptyOut = evaluator.evaluate(
            snapshot: untrusted,
            enrolledNetworks: [],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 200.0
        )
        #expect(emptyOut.posture == .unconfigured)
        #expect(emptyOut.shouldAutoArm == false)
        #expect(emptyOut.updatedGazeSensitivity == nil)
        #expect(emptyOut.newBaselineSensitivityToSave == nil)
    }

    // MARK: - 2. SSID Hash Match & Sensitivity Restoration

    @Test("SSID hash match recognizes trusted network and restores saved baseline sensitivity")
    func ssidHashMatchRecognizesTrustedAndRestoresSensitivity() {
        var evaluator = TrustedNetworkEvaluator()
        let home = makeHomeEntry(ssid: "HomeStudio-5G")
        let snapshot = makeWiFiSnapshot(ssid: "HomeStudio-5G", at: 100.0)

        let out = evaluator.evaluate(
            snapshot: snapshot,
            enrolledNetworks: [home],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true),
            securityState: .disarmed,
            currentGazeSensitivity: .strict,
            savedBaselineSensitivity: .balanced,
            at: 100.0
        )

        #expect(out.posture == .trusted(entryID: home.id, displayName: "Home Wi-Fi", matchedBy: .ssid))
        #expect(out.shouldAutoArm == false)
        #expect(out.updatedGazeSensitivity == .balanced)
        #expect(out.shouldClearSavedBaseline == true)
        #expect(evaluator.hasObservedTrustedNetworkInSession == true)
        #expect(evaluator.suppressedUntrustedKey == nil)
        #expect(out.event == .enteredTrustedNetwork(
            entryID: home.id,
            displayName: "Home Wi-Fi",
            matchedBy: .ssid,
            restoredSensitivity: .balanced
        ))
    }

    // MARK: - 3. Authoritative SSID Mismatch Precedence

    @Test("SSID mismatch authoritatively rejects matching gateway MAC and interface hash")
    func ssidMismatchAuthoritativelyRejectsMatchingGatewayAndInterfaceHash() {
        var evaluator = TrustedNetworkEvaluator()
        let sharedGatewayMAC = "c0:ff:ee:19:21:68"
        let sharedInterfaceHash = NetworkIdentifierHasher.hashInterfaceFingerprint(
            interfaceName: "en0",
            localHardwareMAC: "12:34:56:78:9a:bc",
            routerIP: "192.168.1.1",
            subnetCIDR: "192.168.1.0/24",
            dhcpServerID: "192.168.1.1"
        )
        let home = makeHomeEntry(
            ssid: "HomeWiFi",
            gatewayMAC: sharedGatewayMAC,
            interfaceHash: sharedInterfaceHash
        )
        let coffeeShop = makeWiFiSnapshot(
            ssid: "CoffeeShop",
            gatewayMAC: sharedGatewayMAC,
            interfaceHash: sharedInterfaceHash,
            at: 100.0
        )

        #expect(evaluator.matchTrustedEntry(for: coffeeShop, in: [home]) == nil)

        // Past debounce -> classified as untrusted despite identical gateway MAC and subnet
        _ = evaluator.evaluate(
            snapshot: coffeeShop,
            enrolledNetworks: [home],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 100.0
        )
        let out = evaluator.evaluate(
            snapshot: coffeeShop,
            enrolledNetworks: [home],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 103.0
        )

        if case .untrusted(_, let source, let label) = out.posture {
            #expect(source == .ssid)
            #expect(label == "CoffeeShop")
        } else {
            Issue.record("Expected untrusted posture when SSIDs differ, got \(out.posture)")
        }
        #expect(out.shouldAutoArm == true)
        #expect(out.updatedGazeSensitivity == .strict)
    }

    // MARK: - 4. Location-Denied Fallback & Fail-Closed Guard

    @Test("Location-denied fallback matches gateway MAC then interface hash, and fails closed when unavailable")
    func locationDeniedFallbackMatchesGatewayMACAndInterfaceHashAndFailsClosed() {
        var evaluator = TrustedNetworkEvaluator()
        let ifHash = NetworkIdentifierHasher.hashInterfaceFingerprint(
            interfaceName: "en0",
            localHardwareMAC: "aa:bb:cc:dd:ee:ff",
            routerIP: "10.0.0.1",
            subnetCIDR: "10.0.0.0/24",
            dhcpServerID: "10.0.0.1"
        )
        let homeWithGW = makeHomeEntry(
            ssid: "HomeWiFi",
            gatewayMAC: "00:11:22:33:44:55",
            interfaceHash: ifHash
        )

        // 1. Gateway MAC match when Location is denied (ssidHash == nil)
        let gwSnap = makeWiFiSnapshot(
            ssid: nil,
            gatewayMAC: "00:11:22:33:44:55",
            interfaceHash: nil,
            suggestedDisplayName: "Wi-Fi (en0 • Router deadbe)",
            permission: .denied,
            at: 100.0
        )
        let gwOut = evaluator.evaluate(
            snapshot: gwSnap,
            enrolledNetworks: [homeWithGW],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 100.0
        )
        #expect(gwOut.posture == .trusted(entryID: homeWithGW.id, displayName: "Home Wi-Fi", matchedBy: .gatewayMAC))

        // 2. Interface hash alone (no SSID, no BSSID, no gatewayMAC) must NOT grant trust
        let ifAloneSnap = makeWiFiSnapshot(
            ssid: nil,
            bssid: nil,
            gatewayMAC: nil,
            interfaceHash: ifHash,
            suggestedDisplayName: "Wi-Fi (en0 • Subnet 123456)",
            permission: .denied,
            at: 110.0
        )
        #expect(evaluator.matchTrustedEntry(for: ifAloneSnap, in: [homeWithGW]) == nil)

        // 3. Interface hash with corroborating BSSID (and no conflicting gateway MAC) matches .interfaceHash
        let ifCorroboratedSnap = makeWiFiSnapshot(
            ssid: nil,
            bssid: "aa:bb:cc:11:22:33",
            gatewayMAC: nil,
            interfaceHash: ifHash,
            suggestedDisplayName: "Wi-Fi (en0 • Subnet 123456)",
            permission: .denied,
            at: 112.0
        )
        let ifOut = evaluator.evaluate(
            snapshot: ifCorroboratedSnap,
            enrolledNetworks: [homeWithGW],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 112.0
        )
        #expect(ifOut.posture == .trusted(entryID: homeWithGW.id, displayName: "Home Wi-Fi", matchedBy: .interfaceHash))

        // 4. Interface hash with conflicting gateway MAC is rejected even if BSSID matches
        let ifConflictingGWSnap = makeWiFiSnapshot(
            ssid: nil,
            bssid: "aa:bb:cc:11:22:33",
            gatewayMAC: "de:ad:be:ef:99:99",
            interfaceHash: ifHash,
            permission: .denied,
            at: 114.0
        )
        #expect(evaluator.matchTrustedEntry(for: ifConflictingGWSnap, in: [homeWithGW]) == nil)

        // 5. Fail-closed when interface has no router/subnet/DHCP entropy
        let bareInterfaceHash = NetworkIdentifierHasher.hashInterfaceFingerprint(
            interfaceName: "en0",
            localHardwareMAC: "aa:bb:cc:dd:ee:ff",
            routerIP: nil,
            subnetCIDR: nil,
            dhcpServerID: nil
        )
        #expect(bareInterfaceHash == nil)

        let unavailSnap = makeWiFiSnapshot(
            ssid: nil,
            gatewayMAC: nil,
            interfaceHash: bareInterfaceHash,
            permission: .denied,
            at: 120.0
        )
        let unavailOut = evaluator.evaluate(
            snapshot: unavailSnap,
            enrolledNetworks: [homeWithGW],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 120.0
        )
        #expect(unavailOut.posture == .identityUnavailable(.denied))
        #expect(unavailOut.shouldAutoArm == false)
        #expect(unavailOut.event == .enteredUnavailableIdentity(.denied))
    }

    // MARK: - 5. Untrusted Debounce Suppresses Transient Flaps

    @Test("Untrusted debounce suppresses transient flaps and fires once after window elapses")
    func untrustedDebounceSuppressesTransientFlaps() {
        var evaluator = TrustedNetworkEvaluator()
        let home = makeHomeEntry(ssid: "HomeWiFi")
        let config = TrustedNetworkPolicyConfiguration(isEnabled: true, untrustedDebounceSeconds: 2.5)

        let homeSnap = makeWiFiSnapshot(ssid: "HomeWiFi", at: 90.0)
        _ = evaluator.evaluate(
            snapshot: homeSnap,
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 90.0
        )

        // Join untrusted at t = 100.0 -> debounce starts
        let cafeSnap = makeWiFiSnapshot(ssid: "CafeGuest", at: 100.0)
        let outStart = evaluator.evaluate(
            snapshot: cafeSnap,
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 100.0
        )
        #expect(outStart.shouldAutoArm == false)
        #expect(outStart.updatedGazeSensitivity == nil)
        #expect(outStart.pendingReevaluationDelay == 2.5)

        // Flap back to trusted at t = 101.5 -> cancels pending candidate
        let backHome = evaluator.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "HomeWiFi", at: 101.5),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 101.5
        )
        #expect(backHome.shouldAutoArm == false)
        #expect(evaluator.pendingUntrustedKey == nil)

        // Leave again at t = 100.0 (reset baseline timestamp) and wait past 2.5s
        let outSecondStart = evaluator.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "CafeGuest", at: 200.0),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 200.0
        )
        #expect(outSecondStart.shouldAutoArm == false)
        #expect(outSecondStart.pendingReevaluationDelay == 2.5)

        let outMid = evaluator.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "CafeGuest", at: 201.5),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 201.5
        )
        #expect(outMid.shouldAutoArm == false)
        #expect(outMid.pendingReevaluationDelay == 1.0)

        let outFired = evaluator.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "CafeGuest", at: 202.5),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 202.5
        )
        #expect(outFired.shouldAutoArm == true)
        #expect(outFired.updatedGazeSensitivity == .strict)
        #expect(outFired.newBaselineSensitivityToSave == .balanced)
        #expect(outFired.pendingReevaluationDelay == nil)
    }

    // MARK: - 6. Session Suppression Lifecycle

    @Test("Session suppression prevents infinite re-arm until returning to trusted Wi-Fi")
    func sessionSuppressionPreventsInfiniteRearmUntilTrustedReturn() {
        var evaluator = TrustedNetworkEvaluator()
        let home = makeHomeEntry(ssid: "HomeWiFi")
        let config = TrustedNetworkPolicyConfiguration(isEnabled: true, untrustedDebounceSeconds: 2.5)
        let cafeSnap = makeWiFiSnapshot(ssid: "CafeGuest", at: 100.0)

        _ = evaluator.evaluate(
            snapshot: cafeSnap,
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 100.0
        )
        let triggered = evaluator.evaluate(
            snapshot: cafeSnap,
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 102.5
        )
        #expect(triggered.shouldAutoArm == true)

        // User cancels / disarms while still on CafeGuest
        evaluator.suppressCurrentUntrustedSession()

        for t in [110.0, 200.0] {
            let suppressedOut = evaluator.evaluate(
                snapshot: makeWiFiSnapshot(ssid: "CafeGuest", at: t),
                enrolledNetworks: [home],
                configuration: config,
                securityState: .disarmed,
                currentGazeSensitivity: .strict,
                savedBaselineSensitivity: .balanced,
                at: t
            )
            #expect(suppressedOut.shouldAutoArm == false)
            #expect(suppressedOut.event == nil)
        }

        // Reconnect to trusted Wi-Fi -> clears suppression
        let returnedHome = evaluator.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "HomeWiFi", at: 250.0),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .strict,
            savedBaselineSensitivity: .balanced,
            at: 250.0
        )
        #expect(returnedHome.updatedGazeSensitivity == .balanced)
        #expect(evaluator.suppressedUntrustedKey == nil)

        // Leave home again -> debounces and triggers cleanly
        _ = evaluator.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "CafeGuest", at: 300.0),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 300.0
        )
        let rearmedOut = evaluator.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "CafeGuest", at: 303.0),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 303.0
        )
        #expect(rearmedOut.shouldAutoArm == true)
    }

    // MARK: - 7. Monotonic Sensitivity Escalation & Manual Override Preservation

    @Test("Monotonic sensitivity escalation preserves Ultra and respects manual override while away")
    func monotonicSensitivityEscalationPreservesUltraAndRespectsManualOverride() {
        let home = makeHomeEntry(ssid: "HomeWiFi")
        let config = TrustedNetworkPolicyConfiguration(isEnabled: true, untrustedDebounceSeconds: 0.0)

        // .relaxed -> .strict (saves .relaxed)
        var relaxedEval = TrustedNetworkEvaluator()
        let relaxedOut = relaxedEval.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "AirportFree", at: 10.0),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .relaxed,
            savedBaselineSensitivity: nil,
            at: 10.0
        )
        #expect(relaxedOut.updatedGazeSensitivity == .strict)
        #expect(relaxedOut.newBaselineSensitivityToSave == .relaxed)

        // .ultra stays .ultra with no baseline saved
        var ultraEval = TrustedNetworkEvaluator()
        let ultraOut = ultraEval.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "AirportFree", at: 10.0),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .ultra,
            savedBaselineSensitivity: nil,
            at: 10.0
        )
        #expect(ultraOut.updatedGazeSensitivity == nil)
        #expect(ultraOut.newBaselineSensitivityToSave == nil)

        // .balanced escalated to .strict, then user manually elevates to .ultra while away -> returning home preserves .ultra
        var overrideEval = TrustedNetworkEvaluator()
        let awayOut = overrideEval.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "AirportFree", at: 10.0),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 10.0
        )
        #expect(awayOut.updatedGazeSensitivity == .strict)
        #expect(awayOut.newBaselineSensitivityToSave == .balanced)

        let homeOut = overrideEval.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "HomeWiFi", at: 20.0),
            enrolledNetworks: [home],
            configuration: config,
            securityState: .disarmed,
            currentGazeSensitivity: .ultra,
            savedBaselineSensitivity: .balanced,
            at: 20.0
        )
        #expect(homeOut.updatedGazeSensitivity == nil)
        #expect(homeOut.shouldClearSavedBaseline == true)
    }

    // MARK: - 8. Wired Ethernet Neutral & Optional Offline Disconnect Policy

    @Test("Wired Ethernet is neutral and offline disconnect arms only when enabled and debounced")
    func wiredEthernetNeutralAndOptionalOfflineDisconnectPolicy() {
        var evaluator = TrustedNetworkEvaluator()
        let home = makeHomeEntry(ssid: "HomeWiFi")

        // Observe trusted home first
        _ = evaluator.evaluate(
            snapshot: makeWiFiSnapshot(ssid: "HomeWiFi", at: 10.0),
            enrolledNetworks: [home],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true, armOnOfflineDisconnect: true, offlineDebounceSeconds: 8.0),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 10.0
        )

        // Switch to wired Ethernet -> neutral, never auto-arms
        let ethernetSnap = NetworkIdentitySnapshot(
            isSatisfied: true,
            primaryInterface: .wiredEthernet,
            interfaceName: "en5",
            capturedAt: 20.0
        )
        let ethernetOut = evaluator.evaluate(
            snapshot: ethernetSnap,
            enrolledNetworks: [home],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true, armOnOfflineDisconnect: true, offlineDebounceSeconds: 8.0),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 20.0
        )
        #expect(ethernetOut.posture == .wiredOrCellularNeutral(.wiredEthernet))
        #expect(ethernetOut.shouldAutoArm == false)

        // Offline with armOnOfflineDisconnect = false -> .offline, no auto-arm
        let offlineSnap = NetworkIdentitySnapshot(isSatisfied: false, primaryInterface: .none, capturedAt: 30.0)
        let offlineDisabledOut = evaluator.evaluate(
            snapshot: offlineSnap,
            enrolledNetworks: [home],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true, armOnOfflineDisconnect: false, offlineDebounceSeconds: 8.0),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 30.0
        )
        #expect(offlineDisabledOut.posture == .offline)
        #expect(offlineDisabledOut.shouldAutoArm == false)

        // Offline with armOnOfflineDisconnect = true -> debounces 8.0s then arms once
        let offlineWaitOut = evaluator.evaluate(
            snapshot: offlineSnap,
            enrolledNetworks: [home],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true, armOnOfflineDisconnect: true, offlineDebounceSeconds: 8.0),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 40.0
        )
        #expect(offlineWaitOut.posture == .offlineAfterTrusted)
        #expect(offlineWaitOut.shouldAutoArm == false)
        #expect(offlineWaitOut.pendingReevaluationDelay == 8.0)

        let offlineFireOut = evaluator.evaluate(
            snapshot: NetworkIdentitySnapshot(isSatisfied: false, primaryInterface: .none, capturedAt: 48.0),
            enrolledNetworks: [home],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true, armOnOfflineDisconnect: true, offlineDebounceSeconds: 8.0),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 48.0
        )
        #expect(offlineFireOut.posture == .offlineAfterTrusted)
        #expect(offlineFireOut.shouldAutoArm == true)
        #expect(offlineFireOut.event == .leftTrustedToOffline(armed: true))

        // Subsequent poll stays suppressed until trusted reconnection
        let offlineRepeatOut = evaluator.evaluate(
            snapshot: NetworkIdentitySnapshot(isSatisfied: false, primaryInterface: .none, capturedAt: 60.0),
            enrolledNetworks: [home],
            configuration: TrustedNetworkPolicyConfiguration(isEnabled: true, armOnOfflineDisconnect: true, offlineDebounceSeconds: 8.0),
            securityState: .disarmed,
            currentGazeSensitivity: .balanced,
            savedBaselineSensitivity: nil,
            at: 60.0
        )
        #expect(offlineRepeatOut.shouldAutoArm == false)
    }

    // MARK: - 9. NetworkIdentifierHasher Canonicalization & Determinism

    @Test("NetworkIdentifierHasher canonicalizes MACs, preserves SSID case, computes CIDR, and fails closed")
    func networkIdentifierHasherCanonicalizationAndDeterminism() {
        #expect(NetworkIdentifierHasher.canonicalizeMAC("AA-b-0C-dd-ee-ff") == "aa:0b:0c:dd:ee:ff")
        #expect(NetworkIdentifierHasher.canonicalizeMAC("00:00:00:00:00:00") == nil)
        #expect(NetworkIdentifierHasher.canonicalizeMAC("FF-FF-FF-FF-FF-FF") == nil)
        #expect(NetworkIdentifierHasher.canonicalizeMAC("invalid-mac") == nil)

        let ssidLower = NetworkIdentifierHasher.hashSSID("homewifi")
        let ssidUpper = NetworkIdentifierHasher.hashSSID("HomeWiFi")
        #expect(ssidLower != nil)
        #expect(ssidUpper != nil)
        #expect(ssidLower != ssidUpper)
        #expect(NetworkIdentifierHasher.hashSSID("\0\0") == nil)
        #expect(NetworkIdentifierHasher.hashSSID(nil) == nil)

        // Gateway MAC and BSSID use distinct domain separation
        let mac = "aa:bb:cc:dd:ee:ff"
        #expect(NetworkIdentifierHasher.hashBSSID(mac) != NetworkIdentifierHasher.hashGatewayMAC(mac))

        // Subnet CIDR computation
        #expect(NetworkIdentifierHasher.ipv4SubnetCIDR(address: "192.168.1.42", netmask: "255.255.255.0") == "192.168.1.0/24")
        #expect(NetworkIdentifierHasher.ipv4SubnetCIDR(address: "10.12.34.56", netmask: "255.255.0.0") == "10.12.0.0/16")
        #expect(NetworkIdentifierHasher.ipv4SubnetCIDR(address: "192.168.1.1", netmask: "255.0.255.0") == nil)

        // Interface fingerprint requires at least one network-scoped field
        #expect(
            NetworkIdentifierHasher.hashInterfaceFingerprint(
                interfaceName: "en0",
                localHardwareMAC: "12:34:56:78:9a:bc",
                routerIP: nil,
                subnetCIDR: nil,
                dhcpServerID: nil
            ) == nil
        )
        #expect(
            NetworkIdentifierHasher.hashInterfaceFingerprint(
                interfaceName: "en0",
                localHardwareMAC: "12:34:56:78:9a:bc",
                routerIP: "192.168.1.1",
                subnetCIDR: "192.168.1.0/24",
                dhcpServerID: nil
            ) != nil
        )
    }

    // MARK: - 10. PupilSettings Persistence & Deduplication

    @Test("PupilSettings trusted network defaults, JSON persistence, deduplication, and sync notification")
    @MainActor
    func pupilSettingsTrustedNetworkPersistenceAndDeduplication() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(settings.trustedNetworkAutoArmEnabled == false)
        #expect(settings.trustedNetworks.isEmpty)
        #expect(settings.trustedNetworkPolicyMode == .autoArmAndEscalate)
        #expect(settings.trustedNetworkArmOnOfflineDisconnect == false)
        #expect(settings.trustedNetworkBaselineGazeSensitivity == nil)

        final class CounterBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _count = 0
            func increment() {
                lock.lock()
                _count += 1
                lock.unlock()
            }
            var count: Int {
                lock.lock()
                defer { lock.unlock() }
                return _count
            }
        }
        let syncCounter = CounterBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .screenShieldSync,
            object: nil,
            queue: .main
        ) { _ in
            syncCounter.increment()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        settings.trustedNetworkAutoArmEnabled = true
        settings.trustedNetworkPolicyMode = .autoArmOnly
        settings.trustedNetworkArmOnOfflineDisconnect = true

        let homeEntry = makeHomeEntry(ssid: "HomeWiFi", gatewayMAC: "11:22:33:44:55:66")
        settings.enrollTrustedNetwork(homeEntry)
        #expect(settings.trustedNetworks.count == 1)

        // Duplicate enrollment with same SSID updates existing entry rather than appending
        let updatedHome = TrustedNetworkEntry(
            displayName: "Home Wi-Fi Updated",
            ssidHash: NetworkIdentifierHasher.hashSSID("HomeWiFi"),
            bssidHash: NetworkIdentifierHasher.hashBSSID("aa:bb:cc:11:22:99"),
            gatewayMACHash: NetworkIdentifierHasher.hashGatewayMAC("11:22:33:44:55:66"),
            enrolledSource: .ssid
        )
        settings.enrollTrustedNetwork(updatedHome)
        #expect(settings.trustedNetworks.count == 1)
        #expect(settings.trustedNetworks.first?.id == homeEntry.id)
        #expect(settings.trustedNetworks.first?.displayName == "Home Wi-Fi Updated")
        #expect(syncCounter.count >= 5)

        // Reload from UserDefaults
        let reloaded = PupilSettings(defaults: defaults)
        #expect(reloaded.trustedNetworkAutoArmEnabled == true)
        #expect(reloaded.trustedNetworkPolicyMode == .autoArmOnly)
        #expect(reloaded.trustedNetworkArmOnOfflineDisconnect == true)
        #expect(reloaded.trustedNetworks.count == 1)
        #expect(reloaded.trustedNetworks.first?.displayName == "Home Wi-Fi Updated")

        reloaded.removeTrustedNetwork(id: homeEntry.id)
        #expect(reloaded.trustedNetworks.isEmpty)
    }

    // MARK: - 11. SecurityCoordinator Integration & Evil Twin Safety

    @Test("SecurityCoordinator auto-arms and escalates on untrusted Wi-Fi and never auto-disarms on trusted return")
    @MainActor
    func coordinatorAutoArmsEscalatesAndNeverAutoDisarmsOnTrustedReturn() throws {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.exitDelaySeconds = 0 // Immediate arming for deterministic test state
        settings.gazeSensitivity = .balanced
        settings.trustedNetworkPolicyMode = .autoArmAndEscalate

        let homeEntry = makeHomeEntry(ssid: "HomeWiFi")
        settings.enrollTrustedNetwork(homeEntry)

        let homeSnap = makeWiFiSnapshot(ssid: "HomeWiFi", at: 100.0)
        let provider = MockTrustedNetworkIdentityProvider(permission: .authorized, snapshot: homeSnap)

        var simTime: TimeInterval = 100.0
        let monitor = TrustedNetworkMonitor(identityProvider: provider, clock: { simTime })
        let coordinator = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured }),
            trustedNetworkMonitor: monitor
        )
        coordinator.clock = { simTime }
        defer {
            settings.trustedNetworkAutoArmEnabled = false
            coordinator.syncTrustedNetworkMonitoring()
        }

        // Enable trusted network sentinel while at home
        settings.trustedNetworkAutoArmEnabled = true
        #expect(coordinator.state == .disarmed)
        #expect(settings.gazeSensitivity == .balanced)
        if case .trusted(let entryID, _, _) = coordinator.trustedNetworkPosture {
            #expect(entryID == homeEntry.id)
        } else {
            Issue.record("Expected trusted posture on home Wi-Fi, got \(coordinator.trustedNetworkPosture)")
        }

        // Move to untrusted Wi-Fi at t = 200.0 (start debounce)
        simTime = 200.0
        let cafeSnap = makeWiFiSnapshot(ssid: "AirportPublic", at: simTime)
        provider.setSnapshot(cafeSnap)
        monitor.refreshCurrentNetwork(at: simTime)
        #expect(coordinator.state == .disarmed)
        #expect(settings.gazeSensitivity == .balanced)

        // Past 2.5s debounce at t = 203.0 -> arms and escalates sensitivity to .strict
        simTime = 203.0
        monitor.refreshCurrentNetwork(at: simTime)
        #expect(coordinator.state == .armed)
        #expect(settings.gazeSensitivity == .strict)
        #expect(settings.trustedNetworkBaselineGazeSensitivity == .balanced)
        #expect(coordinator.isUntrustedNetworkEscalationActive == true)

        // Return to trusted SSID while .armed -> MUST NOT auto-disarm (Evil Twin defense)
        simTime = 220.0
        provider.setSnapshot(makeWiFiSnapshot(ssid: "HomeWiFi", at: simTime))
        monitor.refreshCurrentNetwork(at: simTime)
        #expect(coordinator.state == .armed)
        #expect(settings.gazeSensitivity == .strict)
        #expect(settings.trustedNetworkBaselineGazeSensitivity == .balanced)

        // Disarm with PIN -> restores gazeSensitivity to .balanced and clears baseline
        try KeychainManager.enrollPin("1234")
        let disarmed = coordinator.disarmWithPin("1234")
        #expect(disarmed == true)
        #expect(coordinator.state == .disarmed)
        #expect(settings.gazeSensitivity == .balanced)
        #expect(settings.trustedNetworkBaselineGazeSensitivity == nil)

        // Also verify suppression when disarming directly on untrusted Wi-Fi
        simTime = 300.0
        provider.setSnapshot(makeWiFiSnapshot(ssid: "CoffeeShop", at: simTime))
        monitor.refreshCurrentNetwork(at: simTime)
        simTime = 303.0
        monitor.refreshCurrentNetwork(at: simTime)
        #expect(coordinator.state == .armed)

        try KeychainManager.enrollPin("1234")
        #expect(coordinator.disarmWithPin("1234") == true)
        #expect(coordinator.state == .disarmed)

        // Subsequent poll on same untrusted Wi-Fi must stay disarmed (suppressed)
        simTime = 310.0
        monitor.refreshCurrentNetwork(at: simTime)
        #expect(coordinator.state == .disarmed)
    }

    @Test("BSSID pinning is enforced across fallback gatewayMAC and interfaceHash matches")
    func bssidPinningEnforcedAcrossFallbackMatches() {
        let evaluator = TrustedNetworkEvaluator()
        let ifHash = NetworkIdentifierHasher.hashInterfaceFingerprint(
            interfaceName: "en0",
            localHardwareMAC: "aa:bb:cc:dd:ee:ff",
            routerIP: "10.0.0.1",
            subnetCIDR: "10.0.0.0/24",
            dhcpServerID: "10.0.0.1"
        )
        let pinnedHome = makeHomeEntry(
            ssid: "HomeWiFi",
            bssid: "aa:bb:cc:11:22:33",
            gatewayMAC: "00:11:22:33:44:55",
            interfaceHash: ifHash,
            requireBSSIDPinning: true
        )

        // Absent BSSID with matching gateway MAC -> rejected
        let noBSSID = makeWiFiSnapshot(ssid: nil, bssid: nil, gatewayMAC: "00:11:22:33:44:55", interfaceHash: ifHash)
        #expect(evaluator.matchTrustedEntry(for: noBSSID, in: [pinnedHome]) == nil)

        // Wrong BSSID with matching gateway MAC -> rejected
        let wrongBSSID = makeWiFiSnapshot(ssid: nil, bssid: "ff:ee:dd:cc:bb:aa", gatewayMAC: "00:11:22:33:44:55", interfaceHash: ifHash)
        #expect(evaluator.matchTrustedEntry(for: wrongBSSID, in: [pinnedHome]) == nil)

        // Matching BSSID with matching gateway MAC -> trusted
        let matchingBSSID = makeWiFiSnapshot(ssid: nil, bssid: "aa:bb:cc:11:22:33", gatewayMAC: "00:11:22:33:44:55", interfaceHash: ifHash)
        let matched = evaluator.matchTrustedEntry(for: matchingBSSID, in: [pinnedHome])
        #expect(matched?.entry.id == pinnedHome.id)
        #expect(matched?.matchedBy == .gatewayMAC)
    }

    @Test("Switching untrusted networks during exit delay and canceling suppresses the pending network")
    @MainActor
    func exitDelayCancelSuppressesPendingNetworkAfterSwitch() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.exitDelaySeconds = 10
        settings.gazeSensitivity = .balanced
        settings.trustedNetworkPolicyMode = .autoArmAndEscalate

        let homeEntry = makeHomeEntry(ssid: "HomeWiFi")
        settings.enrollTrustedNetwork(homeEntry)

        let provider = MockTrustedNetworkIdentityProvider(
            permission: .authorized,
            snapshot: makeWiFiSnapshot(ssid: "HomeWiFi", at: 100.0)
        )

        var simTime: TimeInterval = 100.0
        let monitor = TrustedNetworkMonitor(identityProvider: provider, clock: { simTime })
        let coordinator = SecurityCoordinator(
            settings: settings,
            alertNotifier: AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured }),
            trustedNetworkMonitor: monitor
        )
        coordinator.clock = { simTime }
        defer {
            settings.trustedNetworkAutoArmEnabled = false
            coordinator.syncTrustedNetworkMonitoring()
        }

        settings.trustedNetworkAutoArmEnabled = true
        #expect(coordinator.state == .disarmed)

        // Move to untrusted network A and wait past debounce to enter exit-delay (.arming)
        simTime = 200.0
        provider.setSnapshot(makeWiFiSnapshot(ssid: "UntrustedA", at: simTime))
        monitor.refreshCurrentNetwork(at: simTime)
        simTime = 203.0
        monitor.refreshCurrentNetwork(at: simTime)
        #expect(coordinator.state == .arming)

        // Switch to untrusted network B while still in exit delay
        simTime = 204.0
        provider.setSnapshot(makeWiFiSnapshot(ssid: "UntrustedB", at: simTime))
        monitor.refreshCurrentNetwork(at: simTime)
        #expect(coordinator.state == .arming)

        // Cancel during exit delay -> disarms and suppresses pending network B
        coordinator.cancelArmingDuringExitDelay()
        #expect(coordinator.state == .disarmed)

        // Advance past B's debounce window -> B must remain suppressed and NOT auto-arm
        simTime = 207.5
        monitor.refreshCurrentNetwork(at: simTime)
        #expect(coordinator.state == .disarmed)

        simTime = 215.0
        monitor.refreshCurrentNetwork(at: simTime)
        #expect(coordinator.state == .disarmed)
    }

    @Test("enrollTrustedSnapshot rejects interface-only snapshots and upgrades legacy interface-only entries")
    @MainActor
    func enrollTrustedSnapshotRejectsInterfaceOnlyAndUpgradesLegacyEntries() {
        let (settings, defaults, suiteName) = makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ifHash = NetworkIdentifierHasher.hashInterfaceFingerprint(
            interfaceName: "en0",
            localHardwareMAC: "aa:bb:cc:dd:ee:ff",
            routerIP: "192.168.1.1",
            subnetCIDR: "192.168.1.0/24",
            dhcpServerID: "192.168.1.1"
        )!

        // 1. Offline / non-Wi-Fi snapshot is rejected
        let offlineSnap = NetworkIdentitySnapshot(isSatisfied: false, primaryInterface: .none)
        #expect(settings.enrollTrustedSnapshot(offlineSnap) == .failure(.notOnWiFi))

        // 2. Interface-only Wi-Fi snapshot (no SSID, BSSID, or gateway MAC) is rejected
        let ifOnlySnap = makeWiFiSnapshot(
            ssid: nil,
            bssid: nil,
            gatewayMAC: nil,
            interfaceHash: ifHash,
            permission: .denied
        )
        #expect(settings.enrollTrustedSnapshot(ifOnlySnap) == .failure(.missingStrongerIdentifier))
        #expect(settings.trustedNetworks.isEmpty)

        // 3. Existing persisted interface-only entry can be re-enrolled with a stronger identifier and upgraded in place
        let legacyEntry = TrustedNetworkEntry(
            displayName: "Legacy Subnet",
            ssidHash: nil,
            bssidHash: nil,
            gatewayMACHash: nil,
            interfaceHash: ifHash,
            enrolledSource: .interfaceHash
        )
        settings.trustedNetworks = [legacyEntry]
        #expect(legacyEntry.hasStrongerIdentifier == false)

        let upgradedSnap = makeWiFiSnapshot(
            ssid: "HomeWiFi",
            bssid: "aa:bb:cc:11:22:33",
            gatewayMAC: "00:11:22:33:44:55",
            interfaceHash: ifHash,
            permission: .authorized
        )
        let result = settings.enrollTrustedSnapshot(upgradedSnap)
        guard case .success(let enrolled) = result else {
            Issue.record("Expected enrollment to succeed with stronger identifier, got \(result)")
            return
        }
        #expect(settings.trustedNetworks.count == 1)
        #expect(settings.trustedNetworks.first?.id == legacyEntry.id)
        #expect(settings.trustedNetworks.first?.hasStrongerIdentifier == true)
        #expect(settings.trustedNetworks.first?.ssidHash == NetworkIdentifierHasher.hashSSID("HomeWiFi"))
        #expect(enrolled.enrolledSource == .ssid)
    }
}
