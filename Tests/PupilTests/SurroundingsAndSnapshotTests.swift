import CoreGraphics
import Foundation
import Testing
@testable import Pupil

@Suite("Surroundings Watch & Remote Snapshot Ping Tests")
@MainActor
struct SurroundingsAndSnapshotTests {
    private func makeIsolatedSettings() throws -> (PupilSettings, UserDefaults, String) {
        let suiteName = "com.pupil.tests.surroundings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = PupilSettings(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    private func makeSceneImage(
        width: Int = 320,
        height: Int = 240,
        patchRectInCoreGraphicsCoords: CGRect? = nil,
        patchGray: CGFloat = 0.92
    ) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Add subtle background texture across the frame
        for x in stride(from: 8, to: width, by: 32) {
            for y in stride(from: 8, to: height, by: 32) {
                ctx.setFillColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1)
                ctx.fill(CGRect(x: x, y: y, width: 10, height: 10))
            }
        }

        if let rect = patchRectInCoreGraphicsCoords {
            ctx.setFillColor(red: patchGray, green: patchGray, blue: patchGray, alpha: 1)
            ctx.fill(rect)
        }
        return ctx.makeImage()!
    }

    @Test("PupilSettings surroundingsWatchEnabled defaults to false and persists")
    func testSurroundingsSettingDefaultAndPersistence() throws {
        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(settings.surroundingsWatchEnabled == false)
        settings.surroundingsWatchEnabled = true
        #expect(PupilSettings(defaults: defaults).surroundingsWatchEnabled == true)
    }

    @Test("WebPushManager parses PING_SNAPSHOT commands and invokes onRemoteSnapshotRequested")
    func testPingSnapshotCommandParsing() throws {
        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = WebPushManager(settings: settings)
        var snapshotRequests = 0
        manager.onRemoteSnapshotRequested = {
            snapshotRequests += 1
        }

        let now = Date()
        let nowSec = Int(now.timeIntervalSince1970)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)

        // 1. Plain PING_SNAPSHOT string envelope
        let plainEnvelope = #"{"id":"snap-1","time":\#(nowSec),"message":"PING_SNAPSHOT"}"#
        #expect(manager.processRemoteCommandLines(plainEnvelope, now: now) == true)
        #expect(snapshotRequests == 1)

        // Duplicate event ID is ignored
        #expect(manager.processRemoteCommandLines(plainEnvelope, now: now) == false)
        #expect(snapshotRequests == 1)

        // 2. JSON envelope with command = PING_SNAPSHOT
        let jsonCmd = #"{"command":"PING_SNAPSHOT","channel":"\#(settings.pairingChannelID)"}"#
            .replacingOccurrences(of: "\"", with: "\\\"")
        let jsonEnvelope = #"{"id":"snap-2","time":\#(nowSec),"message":"\#(jsonCmd)"}"#
        #expect(manager.processRemoteCommandLines(jsonEnvelope, now: now) == true)
        #expect(snapshotRequests == 2)

        // 3. Signed pupilsnapshot:// token
        let signedToken = try #require(
            manager.makeRemoteSnapshotToken(timestampMs: nowMs, nonce: "snap-nonce-1")
        )
        #expect(signedToken.hasPrefix("pupilsnapshot://"))
        let signedEnvelope = #"{"id":"snap-3","time":\#(nowSec),"message":"\#(signedToken)"}"#
        #expect(manager.processRemoteCommandLines(signedEnvelope, now: now) == true)
        #expect(snapshotRequests == 3)

        // Replay of same signed nonce is rejected even with a new ntfy event ID
        let replayEnvelope = #"{"id":"snap-4","time":\#(nowSec),"message":"\#(signedToken)"}"#
        #expect(manager.processRemoteCommandLines(replayEnvelope, now: now) == false)
        #expect(snapshotRequests == 3)

        // Forged signature is rejected
        let forgedToken = try #require(
            manager.makeRemoteSnapshotToken(
                channel: settings.pairingChannelID,
                vapidPublicKey: "forged-key",
                timestampMs: nowMs,
                nonce: "snap-nonce-forged"
            )
        )
        let forgedEnvelope = #"{"id":"snap-5","time":\#(nowSec),"message":"\#(forgedToken)"}"#
        #expect(manager.processRemoteCommandLines(forgedEnvelope, now: now) == false)
        #expect(snapshotRequests == 3)
    }

    @Test("VisionMotionDetector detects peripheral left/right/lower changes only when surroundingsWatchEnabled is true")
    func testPeripheralSurroundingsDetection() {
        let baseFrame = makeSceneImage()

        // Disabled mode: peripheral change must not set surroundingsActivityDetected
        let disabledDetector = VisionMotionDetector()
        disabledDetector.surroundingsWatchEnabled = false
        _ = disabledDetector.analyzeFrame(baseFrame, timestamp: 0)
        // Left edge patch
        let leftChangedFrame = makeSceneImage(
            patchRectInCoreGraphicsCoords: CGRect(x: 0, y: 40, width: 70, height: 160)
        )
        let disabledSample = disabledDetector.analyzeFrame(leftChangedFrame, timestamp: 0.1)
        #expect(disabledSample.surroundingsActivityDetected == false)

        // Enabled mode: static frame -> false
        let detector = VisionMotionDetector()
        detector.surroundingsWatchEnabled = true
        _ = detector.analyzeFrame(baseFrame, timestamp: 0)
        let staticSample = detector.analyzeFrame(baseFrame, timestamp: 0.1)
        #expect(staticSample.surroundingsActivityDetected == false)

        // Change strictly inside central upper anchor (x in [0.25w, 0.75w], top 55% -> CG y >= 0.45h)
        let centralUpperFrame = makeSceneImage(
            patchRectInCoreGraphicsCoords: CGRect(x: 110, y: 140, width: 100, height: 80)
        )
        let centralOnlySample = detector.analyzeFrame(centralUpperFrame, timestamp: 0.2)
        #expect(centralOnlySample.surroundingsActivityDetected == false)

        // Reset to baseline, then introduce change in peripheral left region
        _ = detector.analyzeFrame(baseFrame, timestamp: 0.3)
        let leftSample = detector.analyzeFrame(leftChangedFrame, timestamp: 0.4)
        #expect(leftSample.surroundingsActivityDetected == true)

        // Reset to baseline, then introduce change in peripheral lower region (CG y near 0)
        _ = detector.analyzeFrame(baseFrame, timestamp: 0.5)
        let lowerChangedFrame = makeSceneImage(
            patchRectInCoreGraphicsCoords: CGRect(x: 80, y: 0, width: 160, height: 70)
        )
        let lowerSample = detector.analyzeFrame(lowerChangedFrame, timestamp: 0.6)
        #expect(lowerSample.surroundingsActivityDetected == true)
    }

    @Test("SecurityCoordinator wires surroundingsWatchEnabled and PING_SNAPSHOT remote snapshot delivery")
    func testSecurityCoordinatorSurroundingsAndSnapshotPing() async throws {
        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.surroundingsWatchEnabled = true
        settings.isSpatialMotionEnabled = false

        var sentMessages: [AlertMessage] = []
        let pushManager = WebPushManager(settings: settings)
        let cameraManager = CameraManager()
        cameraManager.isCaptureEnabled = false
        cameraManager.lastFrameImage = makeSceneImage()

        let coordinator = SecurityCoordinator(
            settings: settings,
            cameraManager: cameraManager,
            webPushManager: pushManager,
            alertNotifier: AlertNotifier { message in
                sentMessages.append(message)
                return .delivered
            }
        )

        #expect(cameraManager.motionDetector.surroundingsWatchEnabled == true)

        // PING_SNAPSHOT while disarmed should be ignored
        let now = Date()
        let envelopeDisarmed = #"{"id":"snap-disarmed","time":\#(Int(now.timeIntervalSince1970)),"message":"PING_SNAPSHOT"}"#
        #expect(pushManager.processRemoteCommandLines(envelopeDisarmed, now: now) == true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(sentMessages.isEmpty)

        // Arm and send PING_SNAPSHOT -> should deliver informational AlertMessage with snapshotBase64
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        let envelopeArmed = #"{"id":"snap-armed","time":\#(Int(now.timeIntervalSince1970)),"message":"PING_SNAPSHOT"}"#
        #expect(pushManager.processRemoteCommandLines(envelopeArmed, now: now) == true)
        for _ in 0..<50 {
            await coordinator.alertNotifier.waitUntilIdle()
            if sentMessages.contains(where: { $0.tag == "pupil-snapshot" }) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(sentMessages.contains { $0.tag == "pupil-snapshot" && !($0.snapshotBase64 ?? "").isEmpty })

        // Ingesting a surroundings activity sample while armed logs advisory event without triggering spatial lift tamper
        coordinator.ingestMotionSample(
            MotionSample(timestamp: 100, translationMagnitude: 0, surroundingsActivityDetected: true)
        )
        await coordinator.alertNotifier.waitUntilIdle()

        #expect(coordinator.state == .armed)
        #expect(coordinator.events.contains { $0.title == "Surroundings Activity" })
        #expect(sentMessages.contains { $0.tag == "pupil-surroundings" })
    }
}
