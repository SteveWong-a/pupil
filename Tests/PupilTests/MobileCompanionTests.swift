import Foundation
import Testing
@testable import Pupil

@Suite("Mobile Companion & Remote Disarm Tests")
@MainActor
struct MobileCompanionTests {
    private func makeIsolatedManager() throws -> (WebPushManager, PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.mobile.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = PupilSettings(defaults: defaults)
        let manager = WebPushManager(settings: settings)
        return (manager, settings, defaults, suiteName)
    }

    @Test("Remote disarm token generation and HMAC-SHA256 validation")
    func testRemoteDisarmTokenGenerationAndValidation() throws {
        let (manager, settings, defaults, suiteName) = try makeIsolatedManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)

        let token = try #require(manager.makeRemoteDisarmToken(timestampMs: nowMs, nonce: "nonce-valid-1"))
        #expect(token.hasPrefix("pupildisarm://"))

        // Valid token passes once
        #expect(manager.validateRemoteDisarmToken(token, now: now) == true)
        // Replay with same nonce is rejected
        #expect(manager.validateRemoteDisarmToken(token, now: now) == false)

        // Expired token (>120s) is rejected
        let staleMs = Int64(now.addingTimeInterval(-180).timeIntervalSince1970 * 1000)
        let staleToken = try #require(manager.makeRemoteDisarmToken(timestampMs: staleMs, nonce: "nonce-stale"))
        #expect(manager.validateRemoteDisarmToken(staleToken, now: now) == false)

        // Wrong channel is rejected
        let wrongChannelToken = try #require(
            manager.makeRemoteDisarmToken(
                channel: "pupil-pair-wrongchannel",
                timestampMs: nowMs,
                nonce: "nonce-wrong-channel"
            )
        )
        #expect(manager.validateRemoteDisarmToken(wrongChannelToken, now: now) == false)

        // Tampered signature (wrong VAPID key) is rejected
        let forgedToken = try #require(
            manager.makeRemoteDisarmToken(
                channel: settings.pairingChannelID,
                vapidPublicKey: "forged-vapid-key",
                timestampMs: nowMs,
                nonce: "nonce-forged"
            )
        )
        #expect(manager.validateRemoteDisarmToken(forgedToken, now: now) == false)
    }

    @Test("Remote disarm raw JSON payload validation")
    func testRemoteDisarmRawJSONValidation() throws {
        let (manager, _, defaults, suiteName) = try makeIsolatedManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let token = try #require(manager.makeRemoteDisarmToken(timestampMs: nowMs, nonce: "nonce-json-1"))
        let b64Part = String(token.dropFirst("pupildisarm://".count))
        let jsonData = try #require(Data(base64URLEncoded: b64Part))
        let jsonString = try #require(String(data: jsonData, encoding: .utf8))

        #expect(manager.validateRemoteDisarmToken(jsonString, now: now) == true)
        #expect(manager.validateRemoteDisarmToken("not-a-valid-token", now: now) == false)
    }

    @Test("WebPushManager remote command listener lifecycle and ntfy envelope dispatch")
    func testRemoteCommandListenerAndEnvelopeDispatch() throws {
        let (manager, _, defaults, suiteName) = try makeIsolatedManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var disarmCallbackCount = 0
        manager.onRemoteDisarmRequested = {
            disarmCallbackCount += 1
        }

        #expect(manager.isListeningForRemoteCommands == false)
        manager.startRemoteCommandListener()
        #expect(manager.isListeningForRemoteCommands == true)

        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let validToken = try #require(manager.makeRemoteDisarmToken(timestampMs: nowMs, nonce: "nonce-cmd-1"))

        let invalidEnvelope = #"{"id":"evt-0","time":\#(Int(now.timeIntervalSince1970)),"message":"pupilpair://invalid"}"#
        #expect(manager.processRemoteCommandLines(invalidEnvelope, now: now) == false)
        #expect(disarmCallbackCount == 0)

        let validEnvelope = #"{"id":"evt-1","time":\#(Int(now.timeIntervalSince1970)),"message":"\#(validToken)"}"#
        #expect(manager.processRemoteCommandLines(validEnvelope, now: now) == true)
        #expect(disarmCallbackCount == 1)

        // Duplicate event ID / nonce must not re-trigger
        #expect(manager.processRemoteCommandLines(validEnvelope, now: now) == false)
        #expect(disarmCallbackCount == 1)

        manager.stopRemoteCommandListener()
        #expect(manager.isListeningForRemoteCommands == false)

        // unpairPhone also ensures listener is stopped
        manager.startRemoteCommandListener()
        #expect(manager.isListeningForRemoteCommands == true)
        manager.unpairPhone()
        #expect(manager.isListeningForRemoteCommands == false)
    }

    @Test("AlertMessage preserves optional verification snapshotBase64")
    func testAlertMessageSnapshotAttachment() {
        let plain = AlertMessage(title: "Test", body: "Body", severity: "high", tag: "pupil-tamper")
        #expect(plain.snapshotBase64 == nil)

        let withSnapshot = AlertMessage(
            title: "Tamper",
            body: "Motion detected",
            severity: "high",
            tag: "pupil-tamper",
            snapshotBase64: "/9j/4AAQSkZJRgABAQAAAQABAAD/"
        )
        #expect(withSnapshot.snapshotBase64 == "/9j/4AAQSkZJRgABAQAAAQABAAD/")
    }

    @Test("SecurityCoordinator integrates WebPushManager remote command listener and remote disarm")
    func testSecurityCoordinatorRemoteDisarmIntegration() async throws {
        let suiteName = "com.pupil.tests.coordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: defaults)
        let manager = WebPushManager(settings: settings)
        let coordinator = SecurityCoordinator(
            settings: settings,
            webPushManager: manager,
            alertNotifier: AlertNotifier { _ in .delivered }
        )

        #expect(manager.isListeningForRemoteCommands == false)
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)
        #expect(manager.isListeningForRemoteCommands == true)

        coordinator.triggerTamper(source: .chargerUnplugged, immediateAlarm: false, simulated: true)
        #expect(coordinator.state == .tamperPending)

        let now = Date()
        let token = manager.makeRemoteDisarmToken(
            channel: settings.pairingChannelID,
            vapidPublicKey: manager.vapidPublicKeyBase64URL,
            timestampMs: Int64(now.timeIntervalSince1970 * 1000),
            nonce: "coord-nonce-1"
        )!
        let envelope = #"{"id":"evt-coord-1","time":\#(Int(now.timeIntervalSince1970)),"event":"message","message":"\#(token)"}"#

        let handled = manager.processRemoteCommandLines(envelope, now: now)
        #expect(handled == true)
        #expect(coordinator.state == .disarmed)
        #expect(manager.isListeningForRemoteCommands == false)
        #expect(coordinator.events.contains(where: { $0.title == "Disarmed Remotely via Phone" }))
    }
}
