import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import Pupil

@Suite("Pupil Core & Vision Tests", .serialized)
struct PupilSecurityTests {
    @Test("Keychain PIN enrollment and verification")
    func testPinEnrollmentAndVerification() throws {
        try KeychainManager.enrollPin("4829")
        #expect(KeychainManager.hasEnrolledPin == true)
        #expect(KeychainManager.verifyPin("4829") == true)
        #expect(KeychainManager.verifyPin("0000") == false)
        #expect(KeychainManager.isValidPinFormat("12") == false)
        #expect(KeychainManager.isValidPinFormat("12345678") == true)
    }

    @Test("GazeTemporalAggregator accumulates sustained dwell and tolerates brief blinks")
    func testGazeDwellAggregator() {
        var aggregator = GazeTemporalAggregator()
        let baseTime: TimeInterval = 1000.0

        // Frame at t=0.0s
        let s0 = GazeSample(
            timestamp: baseTime,
            faceCount: 1,
            faceInsideROI: true,
            faceCentroid: CGPoint(x: 0.4, y: 0.5),
            towardScreenScore: 0.85,
            yawRadians: 0.05,
            pitchRadians: 0.02,
            irisHorizontalRatio: 0.5,
            trackingConfidence: 0.92
        )
        let snap0 = aggregator.ingest(s0, scoreThreshold: 0.65, dwellThresholdSeconds: 2.0)
        #expect(snap0.isGazeWarningActive == false)
        #expect(snap0.dwellProgress == 0.0)

        // Brief blink at t=1.0s (<= 0.35s gap after qualifying sample at t=0.9s)
        let s1 = GazeSample(
            timestamp: baseTime + 0.9,
            faceCount: 1,
            faceInsideROI: true,
            faceCentroid: CGPoint(x: 0.41, y: 0.5),
            towardScreenScore: 0.82,
            yawRadians: 0.04,
            pitchRadians: 0.02,
            irisHorizontalRatio: 0.5,
            trackingConfidence: 0.90
        )
        _ = aggregator.ingest(s1, scoreThreshold: 0.65, dwellThresholdSeconds: 2.0)

        let blinkSample = GazeSample(
            timestamp: baseTime + 1.1,
            faceCount: 1,
            faceInsideROI: true,
            faceCentroid: CGPoint(x: 0.41, y: 0.5),
            towardScreenScore: 0.20,
            yawRadians: 0.04,
            pitchRadians: 0.02,
            irisHorizontalRatio: 0.5,
            trackingConfidence: 0.90
        )
        let snapBlink = aggregator.ingest(blinkSample, scoreThreshold: 0.65, dwellThresholdSeconds: 2.0)
        #expect(snapBlink.dwellProgress > 0.4)

        // Frame at t=2.1s crosses 2.0s dwell threshold
        let s2 = GazeSample(
            timestamp: baseTime + 2.1,
            faceCount: 1,
            faceInsideROI: true,
            faceCentroid: CGPoint(x: 0.42, y: 0.5),
            towardScreenScore: 0.88,
            yawRadians: 0.02,
            pitchRadians: 0.01,
            irisHorizontalRatio: 0.5,
            trackingConfidence: 0.95
        )
        let snapFinal = aggregator.ingest(s2, scoreThreshold: 0.65, dwellThresholdSeconds: 2.0)
        #expect(snapFinal.isGazeWarningActive == true)
        #expect(snapFinal.dwellProgress == 1.0)
    }

    @Test("SecurityCoordinator state machine transitions")
    @MainActor
    func testSecurityCoordinatorLifecycle() throws {
        try KeychainManager.enrollPin("2468")
        let coordinator = SecurityCoordinator()
        #expect(coordinator.state == .disarmed)

        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        coordinator.triggerTamper(source: .chargerUnplugged, immediateAlarm: false, simulated: true)
        #expect(coordinator.state == .tamperPending)
        #expect(coordinator.activeTamperSource == .chargerUnplugged)

        // Wrong PIN should not disarm
        #expect(coordinator.disarmWithPin("9999") == false)
        #expect(coordinator.state == .tamperPending)

        // Correct PIN disarms cleanly
        #expect(coordinator.disarmWithPin("2468") == true)
        #expect(coordinator.state == .disarmed)
    }

    @Test("Screen shield blur settings and preview lifecycle")
    @MainActor
    func testScreenShieldAndBlurSettings() {
        let suiteName = "PupilTest-Shield-\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults")
            return
        }
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: isolatedDefaults)
        let coordinator = SecurityCoordinator(settings: settings)
        #expect(settings.blurBackgroundWhenArmed == false)
        #expect(settings.blurScreenOnGaze == true)
        #expect(settings.lockOnInputWhenArmed == true)

        settings.blurBackgroundWhenArmed = true
        #expect(settings.blurBackgroundWhenArmed == true)

        let shieldController = ScreenShieldController(coordinator: coordinator)
        shieldController.syncWithCoordinator()

        #expect(coordinator.isShieldPreviewActive == false)
        coordinator.previewScreenShield(durationSeconds: 0.1)
        #expect(coordinator.isShieldPreviewActive == true)
        shieldController.syncWithCoordinator()

        // Verify shield window creation and prompt notification tokens
        let window = ScreenShieldWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600))
        #expect(window.canBecomeKey == true)
        #expect(window.canBecomeMain == true)
        #expect(Notification.Name.screenShieldOpenPrompt.rawValue == "PupilScreenShieldOpenPrompt")
        #expect(Notification.Name.screenShieldDismissPrompt.rawValue == "PupilScreenShieldDismissPrompt")
        #expect(Notification.Name.screenShieldDeleteKey.rawValue == "PupilScreenShieldDeleteKey")
        #expect(Notification.Name.screenShieldSubmitPrompt.rawValue == "PupilScreenShieldSubmitPrompt")
        #expect(Notification.Name.screenShieldDigitTyped.rawValue == "PupilScreenShieldDigitTyped")
        #expect(Notification.Name.screenShieldFocusPrimary.rawValue == "PupilScreenShieldFocusPrimary")
        #expect(Notification.Name.screenShieldSync.rawValue == "PupilScreenShieldSync")
        #expect(Notification.Name.screenShieldAnyKeyPressed.rawValue == "PupilScreenShieldAnyKeyPressed")
        #expect(Notification.Name.screenShieldInputDetected.rawValue == "PupilScreenShieldInputDetected")

        // Verify armed user input triggers interactive unlock challenge and shield activation
        try? KeychainManager.enrollPin("2468")
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)
        #expect(coordinator.isInteractiveUnlockRequested == false)

        coordinator.handleArmedUserInput()
        #expect(coordinator.isInteractiveUnlockRequested == true)
        shieldController.syncWithCoordinator()

        // Disarm with PIN clears interactive challenge and resets state
        #expect(coordinator.disarmWithPin("2468") == true)
        #expect(coordinator.state == .disarmed)
        #expect(coordinator.isInteractiveUnlockRequested == false)

        // Verify Case 1: Gaze triggers privacy blur while armed, and looking away clears it
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)
        #expect(coordinator.isGazeWarningActive == false)

        coordinator.simulateGazeWarning()
        #expect(coordinator.isGazeWarningActive == true)
        shieldController.syncWithCoordinator()

        coordinator.dismissGazeWarning()
        #expect(coordinator.isGazeWarningActive == false)
        shieldController.syncWithCoordinator()

        #expect(coordinator.disarmWithPin("2468") == true)
        #expect(coordinator.state == .disarmed)

        _ = ScreenShieldView(coordinator: coordinator, isPrimary: true)
        _ = ScreenShieldView(coordinator: coordinator, isPrimary: false)

        // Verify NotchWindow and NotchHostingView hit-testing passes through outside active notch bounds
        let notchWin = NotchWindow(contentRect: NSRect(x: 0, y: 0, width: 442, height: 284))
        notchWin.activeNotchSize = CGSize(width: 200, height: 44)
        notchWin.ignoresMouseEvents = false
        let hostingView = NotchHostingView(
            rootView: NotchOverlayView(coordinator: coordinator, geometry: NotchGeometry.forPreferredScreen(), onRequestInteractive: { _, _ in }),
            window: notchWin
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 442, height: 284)

        // Point outside active notch bounds (e.g. at bottom center (221, 50)) should return nil to let website clicks pass through
        let outsidePoint = NSPoint(x: 221, y: 50)
        #expect(hostingView.hitTest(outsidePoint) == nil)
    }

    @Test("Gaze warning receptiveness: Ultra sensitivity, fast dwell stops, and screen privacy blur")
    @MainActor
    func testGazeWarningReceptivenessAndPrivacyBlur() {
        let suiteName = "PupilTest-Gaze-\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults")
            return
        }
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: isolatedDefaults)
        let coordinator = SecurityCoordinator(settings: settings)

        // 1. Verify Ultra sensitivity cone and dwell stops
        #expect(GazeSensitivity.ultra.scoreThreshold == 0.40)
        #expect(PupilSettings.dwellStops.contains(0.5))
        #expect(PupilSettings.dwellStops.contains(1.0))

        // 2. Verify wide peripheral ROI for Ultra
        settings.gazeSensitivity = .ultra
        #expect(settings.activeCameraROI.width == 0.90)

        // 3. Verify Privacy Blur on Gaze triggers screen shield during armed state
        settings.blurBackgroundWhenArmed = false
        settings.blurScreenOnGaze = true
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        let shieldController = ScreenShieldController(coordinator: coordinator)
        shieldController.syncWithCoordinator()

        // Gaze warning active -> shield should be showing
        coordinator.simulateGazeWarning()
        #expect(coordinator.isGazeWarningActive == true)
        shieldController.syncWithCoordinator()

        // Dismiss gaze warning -> shield unblurs cleanly
        coordinator.dismissGazeWarning()
        #expect(coordinator.isGazeWarningActive == false)
        shieldController.syncWithCoordinator()
    }

    @Test("Notch deterrent style has only minimal pill and silent log options")
    @MainActor
    func testNotchDeterrentStyleOptions() {
        let options = NotchDeterrentStyle.allCases
        #expect(options.count == 2)
        #expect(options.contains(.minimalPill))
        #expect(options.contains(.silent))

        let settings = PupilSettings.shared
        #expect(settings.notchStyle == .minimalPill || settings.notchStyle == .silent)
    }

    @Test("Brief < 0.5s table-bump motion spikes do NOT trigger tamper escalation")
    @MainActor
    func testTableBumpMotionSpikeSuppressed() throws {
        try KeychainManager.enrollPin("1357")
        let coordinator = SecurityCoordinator()
        coordinator.settings.isSpatialMotionEnabled = true
        coordinator.settings.spatialMotionSensitivity = .medium
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        let t0: TimeInterval = 2000.0
        // Frame 0: Anchor captured at arming
        coordinator.ingestMotionSample(.anchor(at: t0, metricDepthZ0: 0.60))
        #expect(coordinator.hasMotionAnchor == true)
        #expect(coordinator.state == .armed)

        // Transient table bump at t+0.10s and t+0.35s (< 0.5s duration)
        coordinator.ingestMotionSample(MotionSample(
            timestamp: t0 + 0.10,
            translationMagnitude: 0.12,
            homographyWarpMagnitude: 0.25
        ))
        #expect(coordinator.state == .armed)

        coordinator.ingestMotionSample(MotionSample(
            timestamp: t0 + 0.35,
            translationMagnitude: 0.11,
            homographyWarpMagnitude: 0.22
        ))
        #expect(coordinator.state == .armed)

        // Settles back to stationary at t+0.45s
        coordinator.ingestMotionSample(MotionSample(
            timestamp: t0 + 0.45,
            translationMagnitude: 0.005,
            homographyWarpMagnitude: 0.01
        ))
        #expect(coordinator.state == .armed)
        #expect(coordinator.continuousMotionSeconds == 0)

        _ = coordinator.disarmWithPin("1357")
    }

    @Test("Sustained > 1.2s motion displacement while ARMED transitions SecurityCoordinator to tamper countdown and resets on PIN disarm")
    @MainActor
    func testSustainedSpatialLiftEscalationAndDisarmReset() throws {
        try KeychainManager.enrollPin("8642")
        let coordinator = SecurityCoordinator()
        coordinator.settings.isSpatialMotionEnabled = true
        coordinator.settings.spatialMotionSensitivity = .medium
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)

        let t0: TimeInterval = 3000.0
        // Capture Frame 0 anchor with metric depth Z_0 = 0.62m
        coordinator.ingestMotionSample(.anchor(at: t0, metricDepthZ0: 0.62))
        #expect(coordinator.hasMotionAnchor == true)
        #expect(coordinator.motionAnchorDepthMeters == 0.62)

        // Start lifting laptop at t+0.1s
        coordinator.ingestMotionSample(MotionSample(
            timestamp: t0 + 0.10,
            translationMagnitude: 0.095,
            homographyWarpMagnitude: 0.20
        ))
        #expect(coordinator.state == .armed)

        // Sustained lift at t+0.8s (0.7s elapsed, still <= 1.2s)
        coordinator.ingestMotionSample(MotionSample(
            timestamp: t0 + 0.80,
            translationMagnitude: 0.105,
            homographyWarpMagnitude: 0.24
        ))
        #expect(coordinator.state == .armed)

        // Sustained lift at t+1.45s (> 1.2s): a lone camera signal only warns, it does not start the countdown
        coordinator.ingestMotionSample(MotionSample(
            timestamp: t0 + 1.45,
            translationMagnitude: 0.115,
            homographyWarpMagnitude: 0.28
        ))
        #expect(coordinator.state == .armed)
        #expect(coordinator.events.contains { $0.title.contains("unconfirmed") })

        // Motion that keeps going past the lone-signal limit (4s) is treated as real -> Tamper Countdown!
        coordinator.ingestMotionSample(MotionSample(
            timestamp: t0 + 4.3,
            translationMagnitude: 0.115,
            homographyWarpMagnitude: 0.28
        ))
        #expect(coordinator.state == .tamperPending)
        #expect(coordinator.activeTamperSource == .cameraMotionDetected)
        #expect(coordinator.activeTamperSource == .spatialLiftDetected)

        // Disarming with a valid PIN resets the motion detector anchor state
        #expect(coordinator.disarmWithPin("8642") == true)
        #expect(coordinator.state == .disarmed)
        #expect(coordinator.hasMotionAnchor == false)
        #expect(coordinator.continuousMotionSeconds == 0)
        #expect(coordinator.latestMotionDisplacementScore == 0)
        #expect(coordinator.motionAnchorDepthMeters == nil)
        #expect(coordinator.cameraManager.motionDetector.hasAnchorFrame == false)
    }

    @Test("Sustained > 1.2s webcam occlusion triggers tamper escalation and VisionMotionDetector processes frames in memory")
    @MainActor
    func testWebcamOcclusionAndVisionMotionDetector() throws {
        var aggregator = MotionTemporalAggregator()
        let t0: TimeInterval = 4000.0

        _ = aggregator.ingest(.anchor(at: t0))
        // Occluded frame at t+0.1s (mean luminance & variance near zero)
        let s1 = aggregator.ingest(MotionSample(
            timestamp: t0 + 0.10,
            translationMagnitude: 0,
            meanLuminance: 0.01,
            luminanceVariance: 0.0001
        ))
        #expect(s1.isTamperTriggered == false)

        // Occluded continuously for 1.3s (> 1.2s)
        let s2 = aggregator.ingest(MotionSample(
            timestamp: t0 + 1.45,
            translationMagnitude: 0,
            meanLuminance: 0.01,
            luminanceVariance: 0.0001
        ))
        #expect(s2.isSustainedOcclusionDetected == true)
        #expect(s2.isTamperTriggered == true)

        // Verify VisionMotionDetector anchor lifecycle with synthetic in-memory CGImage frames
        let detector = VisionMotionDetector()
        #expect(detector.hasAnchorFrame == false)
        if let testImage = Self.makeSyntheticFrame(width: 64, height: 48, lumaByte: 120) {
            let anchorSample = detector.analyzeFrame(testImage, metricDepthZ0: 0.58, timestamp: t0)
            #expect(anchorSample.isAnchorFrame == true)
            #expect(detector.hasAnchorFrame == true)
            #expect(detector.currentAnchorDepthZ0 == 0.58)

            let nextSample = detector.analyzeFrame(testImage, timestamp: t0 + 0.1)
            #expect(nextSample.isAnchorFrame == false)

            detector.resetAnchor()
            #expect(detector.hasAnchorFrame == false)
        }
    }

    @Test("Auto Touch ID setting and Gaze Detection off stops camera/blur")
    @MainActor
    func testAutoTouchIDAndGazeOffStopsCameraAndBlur() throws {
        let suiteName = "PupilTest-Recovery-\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults")
            return
        }
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: isolatedDefaults)
        let coordinator = SecurityCoordinator(settings: settings)

        // 1. Verify autoPromptTouchID defaults to true and persists
        #expect(settings.autoPromptTouchID == true)
        settings.autoPromptTouchID = false
        #expect(settings.autoPromptTouchID == false)
        settings.autoPromptTouchID = true

        // 2. Verify turning off gazeDetectionEnabled dismisses gaze warning, stops camera, and prevents gaze blur
        try KeychainManager.enrollPin("5678")
        coordinator.startArming(immediate: true)
        #expect(coordinator.state == .armed)
        coordinator.simulateGazeWarning()
        #expect(coordinator.isGazeWarningActive == true)

        settings.gazeDetectionEnabled = false
        NotificationCenter.default.post(name: .screenShieldSync, object: nil)
        #expect(coordinator.isGazeWarningActive == false)
        #expect(coordinator.cameraManager.isRunning == false)

        // While gazeDetectionEnabled is false, gaze samples must not trigger gaze warnings
        let sample = GazeSample(
            timestamp: 9000.0,
            faceCount: 1,
            faceInsideROI: true,
            faceCentroid: CGPoint(x: 0.5, y: 0.5),
            towardScreenScore: 0.95,
            yawRadians: 0.0,
            pitchRadians: 0.0,
            irisHorizontalRatio: 0.5,
            trackingConfidence: 0.99
        )
        coordinator.ingestGazeSample(sample)
        #expect(coordinator.isGazeWarningActive == false)

        _ = coordinator.disarmWithPin("5678")
    }

    @Test("Web Push RFC 8291 aes128gcm encryption, VAPID ES256 signing, and one-time QR pairing")
    @MainActor
    func testWebPushEncryptionAndOneTimePairing() throws {
        let suiteName = "PupilTest-WebPush-\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults")
            return
        }
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let settings = PupilSettings(defaults: isolatedDefaults)
        let manager = WebPushManager(settings: settings)

        // 1. Verify 65-byte uncompressed P-256 VAPID public key and QR image generation
        let pubKeyData = try #require(Data(base64URLEncoded: manager.vapidPublicKeyBase64URL))
        #expect(pubKeyData.count == 65)
        #expect(pubKeyData[0] == 0x04)
        #expect(manager.pairingURLString.contains("https://stevewong-a.github.io/pupil/?"))
        #expect(manager.makePairingQRCodeImage(dimension: 120) != nil)

        // 2. Verify VAPID ES256 JWT generation for Apple Web Push origin
        let appleEndpoint = try #require(URL(string: "https://web.push.apple.com/QGp9testEndpoint"))
        let vapidHeader = try WebPushManager.makeVAPIDAuthorizationHeader(
            for: appleEndpoint,
            privateKey: manager.vapidPrivateKey
        )
        #expect(vapidHeader.hasPrefix("vapid t="))
        #expect(vapidHeader.contains(", k=\(manager.vapidPublicKeyBase64URL)"))

        // 3. Verify RFC 8291 + RFC 8188 aes128gcm round-trip payload encryption & decryption
        let receiverKey = P256.KeyAgreement.PrivateKey()
        let receiverP256dh = receiverKey.publicKey.x963Representation.base64URLEncodedString()
        let authSecret = Data((0 ..< 16).map { UInt8($0 + 1) })
        let authB64 = authSecret.base64URLEncodedString()

        let samplePlaintext = Data(#"{"title":"Pupil Alarm","body":"Charger unplugged!"}"#.utf8)
        let encrypted = try WebPushManager.encryptWebPushPayload(
            samplePlaintext,
            p256dhBase64URL: receiverP256dh,
            authBase64URL: authB64
        )
        #expect(encrypted.count == 86 + samplePlaintext.count + 1 + 16)

        let decrypted = try WebPushManager.decryptWebPushPayload(
            encrypted,
            receiverPrivateKey: receiverKey,
            authSecret: authSecret
        )
        #expect(decrypted == samplePlaintext)

        // 4. Verify one-time pairing token import and persistence
        let pairingJSON: [String: Any] = [
            "type": "pupil-webpush-pair",
            "deviceName": "Steve's iPhone",
            "endpoint": "https://web.push.apple.com/QGp9testEndpoint",
            "p256dh": receiverP256dh,
            "auth": authB64
        ]
        let pairingData = try JSONSerialization.data(withJSONObject: pairingJSON)
        let token = "pupilpair://\(pairingData.base64URLEncodedString())"

        #expect(manager.isPaired == false)
        let imported = manager.importPairingToken(token)
        #expect(imported == true)
        #expect(manager.isPaired == true)
        #expect(manager.activeSubscription?.deviceName == "Steve's iPhone")
        #expect(manager.activeSubscription?.endpointHost == "web.push.apple.com")
        #expect(settings.relayEnabled == true)

        manager.unpairPhone()
        #expect(manager.isPaired == false)
    }

    private static func makeSyntheticFrame(width: Int, height: Int, lumaByte: UInt8) -> CGImage? {
        var pixels = [UInt8](repeating: lumaByte, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        return ctx.makeImage()
    }

    private func liftSample(_ t: TimeInterval) -> MotionSample {
        MotionSample(timestamp: t, translationMagnitude: 0.12, homographyWarpMagnitude: 0.3)
    }

    @MainActor
    private func armedCoordinator(pin: String) throws -> SecurityCoordinator {
        try KeychainManager.enrollPin(pin)
        let notifier = AlertNotifier(backoffSeconds: [], transport: { _ in .notConfigured })
        let c = SecurityCoordinator(alertNotifier: notifier)
        c.settings.isSpatialMotionEnabled = true
        c.settings.spatialMotionSensitivity = .medium
        // Keep the camera off: the test host has no NSCameraUsageDescription and would abort on access.
        c.settings.gazeDetectionEnabled = false
        c.startArming(immediate: true)
        return c
    }

    @Test("Scorer: lone lift warns, persistence or corroboration escalates")
    func scorerDecisions() {
        var scorer = TamperScorer()
        #expect(scorer.decideWeak(.cameraMotionDetected, persistenceSeconds: 1.3, isOcclusion: false, alreadyCountingDown: false, at: 100) == .warn)
        #expect(scorer.decideWeak(.cameraMotionDetected, persistenceSeconds: 4.1, isOcclusion: false, alreadyCountingDown: false, at: 100) == .countdown)
        // Lights going out look like occlusion, so it needs longer
        #expect(scorer.decideWeak(.cameraMotionDetected, persistenceSeconds: 5, isOcclusion: true, alreadyCountingDown: false, at: 100) == .warn)
        #expect(scorer.decideWeak(.cameraMotionDetected, persistenceSeconds: 8.5, isOcclusion: true, alreadyCountingDown: false, at: 100) == .countdown)
        scorer.record(.chargerUnplugged, at: 95)
        // Corroborated with charger unplug: starts countdown immediately without waiting for 4.0s
        #expect(scorer.decideWeak(.cameraMotionDetected, persistenceSeconds: 1.3, isOcclusion: false, alreadyCountingDown: false, at: 100) == .countdown)
        // While already counting down, weak motion never escalates to alarmNow (preserves owner's disarm grace period)
        #expect(scorer.decideWeak(.cameraMotionDetected, persistenceSeconds: 1.3, isOcclusion: false, alreadyCountingDown: true, at: 100) == .warn)
        // Old corroboration expires
        #expect(scorer.decideWeak(.cameraMotionDetected, persistenceSeconds: 1.3, isOcclusion: false, alreadyCountingDown: false, at: 120) == .warn)
        #expect(scorer.hasRecentWeakSignal(at: 100) == false)
        scorer.record(.cameraMotionDetected, at: 100)
        #expect(scorer.hasRecentWeakSignal(at: 105) == true)
    }

    @Test("Motion warning followed by charger unplug grants grace countdown to disarm")
    @MainActor
    func motionPlusChargerGrantsGracePeriod() throws {
        let c = try armedCoordinator(pin: "2468")
        var now: TimeInterval = 5000
        c.clock = { now }
        c.ingestMotionSample(.anchor(at: now))
        c.ingestMotionSample(liftSample(now + 0.1))
        c.ingestMotionSample(liftSample(now + 1.6))
        #expect(c.state == .armed)
        now += 2
        c.triggerTamper(source: .chargerUnplugged)
        // Must start grace countdown (tamperPending), NOT immediate siren alarm
        #expect(c.state == .tamperPending)
        // Moving during countdown to type PIN does not cut countdown short
        c.ingestMotionSample(liftSample(now + 3))
        #expect(c.state == .tamperPending)
        _ = c.disarmWithPin("2468")
        #expect(c.state == .disarmed)
    }

    @Test("Charger unplug alone still starts the normal countdown")
    @MainActor
    func chargerAloneCountsDown() throws {
        let c = try armedCoordinator(pin: "2468")
        c.triggerTamper(source: .chargerUnplugged)
        #expect(c.state == .tamperPending)
        _ = c.disarmWithPin("2468")
    }

    @Test("Reconnecting power during grace countdown reverts state back to armed when setting enabled")
    @MainActor
    func powerRestoredRevertsToArmed() throws {
        let c = try armedCoordinator(pin: "2468")
        c.settings.revertTamperOnPowerRestored = true
        c.triggerTamper(source: .chargerUnplugged)
        #expect(c.state == .tamperPending)
        #expect(c.activeTamperSource == .chargerUnplugged)

        // Simulate charger plugged back in
        c.powerMonitor.onHardwareEvent?(.chargerPluggedIn)
        #expect(c.state == .armed)
        #expect(c.activeTamperSource == nil)
        #expect(c.events.contains { $0.title == "Tamper Canceled" })
        _ = c.disarmWithPin("2468")
    }

    @Test("Reconnecting power does NOT revert if setting is disabled or if alarm already latched")
    @MainActor
    func powerRestoredDoesNotRevertWhenDisabledOrAlarmed() throws {
        let c = try armedCoordinator(pin: "2468")
        c.settings.revertTamperOnPowerRestored = false
        c.triggerTamper(source: .chargerUnplugged)
        #expect(c.state == .tamperPending)

        c.powerMonitor.onHardwareEvent?(.chargerPluggedIn)
        // Should remain counting down since setting is disabled
        #expect(c.state == .tamperPending)

        // Now test when in alarm
        c.settings.revertTamperOnPowerRestored = true
        c.enterAlarm(source: .chargerUnplugged)
        #expect(c.state == .alarm)
        c.powerMonitor.onHardwareEvent?(.chargerPluggedIn)
        // Must stay in alarm — power restored cannot silence an active siren
        #expect(c.state == .alarm)
        _ = c.disarmWithPin("2468")
    }

    @Test("Spatial motion settles back down during countdown reverts to armed")
    @MainActor
    func spatialMotionSettledRevertsToArmed() throws {
        let c = try armedCoordinator(pin: "2468")
        c.settings.isSpatialMotionEnabled = true
        c.triggerTamper(source: .cameraMotionDetected)
        #expect(c.state == .tamperPending)
        #expect(c.activeTamperSource == .cameraMotionDetected)
        #expect(c.activeAlertTimestampFormatted != nil)

        // Simulate stationary motion samples for 1.3 seconds
        let t0 = 100.0
        for i in 0...14 {
            let sample = MotionSample(
                timestamp: t0 + Double(i) * 0.1,
                translationMagnitude: 0.001,
                homographyWarpMagnitude: 0.01,
                meanLuminance: 0.5,
                luminanceVariance: 0.1,
                interFrameTranslation: 0.001,
                isRegistrationReliable: true,
                textureEnergy: 0.05
            )
            c.ingestMotionSample(sample)
        }

        #expect(c.state == .armed)
        #expect(c.activeTamperSource == nil)
        #expect(c.events.contains { $0.title == "Tamper Canceled" })
        _ = c.disarmWithPin("2468")
    }

    @Test("Reconnecting power reverts to armed even if plugging moved laptop (cameraMotionDetected)")
    @MainActor
    func powerRestoredRevertsCameraMotionTamper() throws {
        let c = try armedCoordinator(pin: "2468")
        c.settings.revertTamperOnPowerRestored = true
        c.triggerTamper(source: .cameraMotionDetected)
        #expect(c.state == .tamperPending)

        c.powerMonitor.onHardwareEvent?(.chargerPluggedIn)
        #expect(c.state == .armed)
        #expect(c.activeTamperSource == nil)
        _ = c.disarmWithPin("2468")
    }

    @Test("Notifier retries transient failures with backoff and reports success")
    @MainActor
    func notifierRetries() async {
        var calls = 0
        var sleeps: [Double] = []
        let notifier = AlertNotifier(
            backoffSeconds: [1, 3],
            transport: { _ in calls += 1; return calls < 3 ? .retryableFailure("timeout") : .delivered },
            sleep: { sleeps.append($0) }
        )
        var results: [AlertResult] = []
        notifier.onResult = { _, r in results.append(r) }
        notifier.send(AlertMessage(title: "t", body: "b", tag: "x"))
        await notifier.waitUntilIdle()
        #expect(calls == 3)
        #expect(sleeps == [1, 3])
        #expect(results == [.delivered(attempts: 3)])
    }

    @Test("Notifier gives up on permanent failures without retrying, and after the retry budget")
    @MainActor
    func notifierGivesUp() async {
        var calls = 0
        let notifier = AlertNotifier(backoffSeconds: [0, 0], transport: { _ in calls += 1; return .permanentFailure("410") }, sleep: { _ in })
        var results: [AlertResult] = []
        notifier.onResult = { _, r in results.append(r) }
        notifier.send(AlertMessage(title: "t", body: "b", tag: "x"))
        await notifier.waitUntilIdle()
        #expect(calls == 1)
        #expect(results == [.failed(attempts: 1, reason: "410")])

        calls = 0
        results = []
        let flaky = AlertNotifier(backoffSeconds: [0, 0], transport: { _ in calls += 1; return .retryableFailure("503") }, sleep: { _ in })
        flaky.onResult = { _, r in results.append(r) }
        flaky.send(AlertMessage(title: "t", body: "b", tag: "x"))
        await flaky.waitUntilIdle()
        #expect(calls == 3)
        #expect(results == [.failed(attempts: 3, reason: "503")])
    }

    @Test("Notifier sends in order and drops a stale countdown push once the alarm push is queued")
    @MainActor
    func notifierOrderingAndSupersede() async {
        var sent: [String] = []
        let notifier = AlertNotifier(backoffSeconds: [], transport: { m in sent.append(m.tag); return .delivered }, sleep: { _ in })
        notifier.send(AlertMessage(title: "first", body: "", tag: "pupil-input-lock"))
        notifier.send(AlertMessage(title: "countdown", body: "", severity: "high", tag: "pupil-tamper"))
        notifier.send(AlertMessage(title: "alarm", body: "", severity: "critical", tag: "pupil-alarm"))
        await notifier.waitUntilIdle()
        #expect(sent == ["pupil-input-lock", "pupil-alarm"])
    }

    @Test("Notifier preempts in-flight retries of countdown push when critical alarm push arrives")
    @MainActor
    func notifierPreemptsInFlightRetries() async {
        var sent: [String] = []
        var attempts = 0
        let notifier = AlertNotifier(
            backoffSeconds: [0.01, 0.01],
            transport: { m in
                sent.append(m.tag)
                if m.tag == "pupil-tamper" {
                    attempts += 1
                    return .retryableFailure("busy")
                }
                return .delivered
            },
            sleep: { _ in }
        )
        notifier.send(AlertMessage(title: "countdown", body: "", severity: "high", tag: "pupil-tamper"))
        // Send critical alarm immediately to supersede in-flight countdown retry
        notifier.send(AlertMessage(title: "alarm", body: "", severity: "critical", tag: "pupil-alarm"))
        await notifier.waitUntilIdle()
        #expect(sent.contains("pupil-alarm"))
        #expect(attempts < 3)
    }

    @Test("HTTP status classification")
    func classification() {
        #expect(WebPushManager.classify(statusCode: 503, detail: "") == .retryableFailure(""))
        #expect(WebPushManager.classify(statusCode: 429, detail: "") == .retryableFailure(""))
        #expect(WebPushManager.classify(statusCode: 410, detail: "") == .permanentFailure(""))
    }

    @Test("Automatic room noise floor calibration during arming exit countdown")
    @MainActor
    func armingExitDelayProfilesRoomNoise() throws {
        let c = try armedCoordinator(pin: "2468")
        _ = c.disarmWithPin("2468")
        c.settings.exitDelaySeconds = 10
        c.settings.isSpatialMotionEnabled = true
        c.startArming(immediate: false)
        #expect(c.state == .arming)
        #expect(c.activeRoomProfile == nil)

        // Feed motion samples during exit delay
        c.ingestMotionSample(MotionSample(timestamp: 100, translationMagnitude: 0.05, meanLuminance: 0.50))
        c.ingestMotionSample(MotionSample(timestamp: 101, translationMagnitude: 0.08, meanLuminance: 0.48))
        c.ingestMotionSample(MotionSample(timestamp: 102, translationMagnitude: 0.06, meanLuminance: 0.52))

        c.completeArming()
        #expect(c.state == .armed)
        let profile = try #require(c.activeRoomProfile)
        #expect(profile.sampleCount == 3)
        #expect(profile.noiseFloorScore >= 0.08)
        #expect(c.events.contains { $0.title == "Room Calibrated" })
        _ = c.disarmWithPin("2468")
    }

    @Test("Alarm state disarm sends resolving notification")
    @MainActor
    func alarmDisarmSendsResolvingPush() async throws {
        var sentMessages: [AlertMessage] = []
        let notifier = AlertNotifier(backoffSeconds: [], transport: { msg in
            sentMessages.append(msg)
            return .delivered
        }, sleep: { _ in })
        try KeychainManager.enrollPin("2468")
        let c = SecurityCoordinator(alertNotifier: notifier)
        c.settings.gazeDetectionEnabled = false
        c.startArming(immediate: true)
        c.enterAlarm(source: .chargerUnplugged)
        #expect(c.state == .alarm)
        await notifier.waitUntilIdle()
        #expect(sentMessages.contains { $0.title == "Pupil Siren Alarm Active" })

        _ = c.disarmWithPin("2468")
        #expect(c.state == .disarmed)
        await notifier.waitUntilIdle()
        #expect(sentMessages.contains { $0.title == "Pupil Disarmed" })
    }

    @Test("On-demand live calibration test profiles room noise and publishes active profile")
    @MainActor
    func liveCalibrationTestLifecycle() throws {
        let c = try armedCoordinator(pin: "2468")
        _ = c.disarmWithPin("2468")

        #expect(c.isLiveCalibrating == false)
        #expect(c.liveCalibrationReport == nil)

        c.startLiveCalibrationTest(durationSeconds: 3.0)
        #expect(c.isLiveCalibrating == true)
        #expect(c.liveCalibrationSecondsRemaining == 3)
        #expect(c.isCameraPreviewRequested == true)

        // Feed motion samples during live test
        c.ingestMotionSample(MotionSample(timestamp: 200, translationMagnitude: 0.04, meanLuminance: 0.45, textureEnergy: 0.025))
        c.ingestMotionSample(MotionSample(timestamp: 201, translationMagnitude: 0.07, meanLuminance: 0.46, textureEnergy: 0.022))
        c.ingestMotionSample(MotionSample(timestamp: 202, translationMagnitude: 0.05, meanLuminance: 0.44, textureEnergy: 0.024))

        c.completeLiveCalibrationTest()
        #expect(c.isLiveCalibrating == false)
        let report = try #require(c.liveCalibrationReport)
        #expect(report.sampleCount == 3)
        #expect(report.noiseFloorScore == 0.07)
        #expect(report.averageTextureEnergy >= 0.020)
        #expect(report.textureHealthDescription == "Rich Texture (Optimal)")
        #expect(report.noiseLevelDescription == "Clean (Low Jitter)")
        #expect(c.activeRoomProfile == report)
        #expect(c.events.contains { $0.title == "Calibration Test Complete" })
    }

    @Test("Face bounding boxes and background texture energy are published for spatial focus inspection")
    @MainActor
    func previewSpatialFocusTelemetry() throws {
        let c = try armedCoordinator(pin: "2468")
        _ = c.disarmWithPin("2468")
        c.setCameraPreviewRequested(true)

        let testBox = CGRect(x: 0.25, y: 0.30, width: 0.50, height: 0.40)
        let gazeSample = GazeSample(
            timestamp: 300,
            faceCount: 1,
            faceInsideROI: true,
            faceCentroid: CGPoint(x: 0.5, y: 0.5),
            towardScreenScore: 0.85,
            yawRadians: 0,
            pitchRadians: 0,
            irisHorizontalRatio: 0.5,
            trackingConfidence: 0.95,
            faceBoundingBoxes: [testBox]
        )
        c.ingestGazeSample(gazeSample)
        #expect(c.latestFaceBoundingBoxes.count == 1)
        #expect(c.latestFaceBoundingBoxes.first == testBox)

        let motionSample = MotionSample(
            timestamp: 300,
            translationMagnitude: 0.02,
            isRegistrationReliable: true,
            textureEnergy: 0.028
        )
        c.ingestMotionSample(motionSample)
        #expect(c.latestTextureEnergy == 0.028)
        #expect(c.isTextureAdequate == true)

        c.setCameraPreviewRequested(false)
        #expect(c.latestFaceBoundingBoxes.isEmpty)
        #expect(c.latestTextureEnergy == 0)
    }

    @Test("RoomNoiseProfiler calculates jitter noise floor, texture energy, and recommended sensitivity")
    func testRoomNoiseProfilerMetrics() {
        var profiler = RoomNoiseProfiler()
        #expect(profiler.finalizeCalibration() == nil)

        // Anchor frame is ignored during profiling
        profiler.ingest(.anchor(at: 100))
        #expect(profiler.finalizeCalibration() == nil)

        profiler.ingest(MotionSample(
            timestamp: 101,
            translationMagnitude: 0.04,
            homographyWarpMagnitude: 0.02,
            meanLuminance: 0.45,
            interFrameTranslation: 0.03,
            textureEnergy: 0.025
        ))
        profiler.ingest(MotionSample(
            timestamp: 102,
            translationMagnitude: 0.07,
            homographyWarpMagnitude: 0.05,
            meanLuminance: 0.49,
            interFrameTranslation: 0.06,
            textureEnergy: 0.027
        ))

        let profile = try! #require(profiler.finalizeCalibration())
        #expect(profile.sampleCount == 2)
        #expect(profile.noiseFloorScore == 0.07)
        #expect(profile.averageTextureEnergy > 0.02)
        #expect(profile.noiseLevelDescription == "Clean (Low Jitter)")
        #expect(profile.textureHealthDescription == "Rich Texture (Optimal)")
        #expect(profile.luminanceDescription == "Good Lighting")
        #expect(profile.recommendedSensitivity == .high)
    }

    @Test("On-demand live calibration test runs in preview, captures room profile, and applies baseline")
    @MainActor
    func testLiveCalibrationOnDemand() throws {
        let c = try armedCoordinator(pin: "2468")
        _ = c.disarmWithPin("2468")
        #expect(c.state == .disarmed)
        #expect(c.isLiveCalibrating == false)
        #expect(c.liveCalibrationReport == nil)

        c.startLiveCalibrationTest(durationSeconds: 3.0)
        #expect(c.isLiveCalibrating == true)
        #expect(c.isCameraPreviewRequested == true)
        #expect(c.liveCalibrationSecondsRemaining == 3)

        // Ingest motion samples during live test
        c.ingestMotionSample(MotionSample(
            timestamp: 200,
            translationMagnitude: 0.03,
            homographyWarpMagnitude: 0.01,
            meanLuminance: 0.50,
            textureEnergy: 0.024
        ))
        c.ingestMotionSample(MotionSample(
            timestamp: 201,
            translationMagnitude: 0.05,
            homographyWarpMagnitude: 0.02,
            meanLuminance: 0.52,
            textureEnergy: 0.026
        ))

        c.completeLiveCalibrationTest()
        #expect(c.isLiveCalibrating == false)
        #expect(c.liveCalibrationSecondsRemaining == 0)

        let report = try #require(c.liveCalibrationReport)
        #expect(report.sampleCount == 2)
        #expect(report.noiseFloorScore == 0.05)
        #expect(c.activeRoomProfile == report)
        #expect(c.events.contains { $0.title == "Calibration Test Complete" })

        // Apply baseline explicitly
        c.applyLiveCalibrationAsBaseline()
        #expect(c.events.contains { $0.title == "Room Baseline Applied" })

        // Cancellation test
        c.startLiveCalibrationTest(durationSeconds: 3.0)
        #expect(c.isLiveCalibrating == true)
        c.cancelLiveCalibrationTest()
        #expect(c.isLiveCalibrating == false)
    }

    @Test("Spatial focus publishes face bounding boxes and texture energy for overlay inspection")
    @MainActor
    func testSpatialFocusPublication() throws {
        let c = try armedCoordinator(pin: "2468")
        _ = c.disarmWithPin("2468")
        c.setCameraPreviewRequested(true)
        #expect(c.latestFaceBoundingBoxes.isEmpty)

        // Gaze sample with detected face
        let faceBox = CGRect(x: 0.35, y: 0.40, width: 0.30, height: 0.40)
        let gaze = GazeSample(
            timestamp: 300,
            faceCount: 1,
            faceInsideROI: true,
            faceCentroid: CGPoint(x: 0.5, y: 0.6),
            towardScreenScore: 0.8,
            yawRadians: 0,
            pitchRadians: 0,
            irisHorizontalRatio: 0.5,
            trackingConfidence: 0.9,
            faceBoundingBoxes: [faceBox]
        )
        c.ingestGazeSample(gaze)
        #expect(c.latestFaceBoundingBoxes == [faceBox])
        #expect(c.activeFaceCount == 1)

        // Motion sample with high texture energy
        let motion = MotionSample(
            timestamp: 301,
            translationMagnitude: 0.01,
            textureEnergy: 0.035
        )
        c.ingestMotionSample(motion)
        #expect(c.latestTextureEnergy == 0.035)
        #expect(c.isTextureAdequate == true)

        // Turning preview off clears face bounding boxes and resets live calibration
        c.setCameraPreviewRequested(false)
        #expect(c.latestFaceBoundingBoxes.isEmpty)
    }

    @Test("Displacement diagnostics: stationary laptop with person in front")
    func testDisplacementDiagnostics() {
        // Create a realistic webcam scene:
        // Room background (walls, picture) + person (shoulders + head)
        func makeWebcamImage(dxPerson: Double, dyPerson: Double, dxRoom: Double = 0) -> CGImage {
            let w = 640, h = 480
            let cs = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            
            // Stationary room background
            ctx.setFillColor(red: 0.85, green: 0.85, blue: 0.82, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            // Wall picture & textured bookshelf in background
            for i in 0..<12 {
                let x = Double(20 + i * 48) + dxRoom
                let colorVal = Double((i * 37) % 100) / 100.0
                ctx.setFillColor(red: colorVal, green: 0.3, blue: 0.7 - colorVal * 0.5, alpha: 1)
                ctx.fill(CGRect(x: x, y: 280, width: 38, height: 140))
            }
            
            // Person: shoulders + torso in bottom half
            let px = 320.0 + dxPerson
            let py = 120.0 + dyPerson
            ctx.setFillColor(red: 0.15, green: 0.2, blue: 0.4, alpha: 1) // dark shirt
            ctx.fill(CGRect(x: px - 160, y: 0, width: 320, height: py + 80))
            // Head/face (Vision coords: y around 200..340)
            ctx.setFillColor(red: 0.9, green: 0.7, blue: 0.6, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: px - 60, y: py + 80, width: 120, height: 140))
            
            return ctx.makeImage()!
        }

        let faceBox0 = CGRect(x: 0.40, y: 0.40, width: 0.20, height: 0.30)
        let faceBox1 = CGRect(x: 0.41, y: 0.40, width: 0.20, height: 0.30) // slight 1% micro-movement

        // Subcase A: Frame 0 had NO face detected (startup), Frame 1 acquires face with allowReanchorOnFaceAcquisition
        let dA = VisionMotionDetector()
        _ = dA.analyzeFrame(makeWebcamImage(dxPerson: 0, dyPerson: 0), faceBoundingBoxes: [], allowReanchorOnFaceAcquisition: true)
        let sA1 = dA.analyzeFrame(makeWebcamImage(dxPerson: 0, dyPerson: 0), faceBoundingBoxes: [faceBox0], allowReanchorOnFaceAcquisition: true)
        #expect(sA1.isAnchorFrame)
        #expect(sA1.translationMagnitude == 0)

        let sA2 = dA.analyzeFrame(makeWebcamImage(dxPerson: 0, dyPerson: 0), faceBoundingBoxes: [faceBox0], allowReanchorOnFaceAcquisition: true)
        #expect(sA2.translationMagnitude / 0.040 < 0.10)

        // Subcase B: Frame 0 has face, Frame 1 has face with person swaying 6px (micro-motion)
        let dB = VisionMotionDetector()
        _ = dB.analyzeFrame(makeWebcamImage(dxPerson: 0, dyPerson: 0), faceBoundingBoxes: [faceBox0])
        let sB1 = dB.analyzeFrame(makeWebcamImage(dxPerson: 6, dyPerson: 2), faceBoundingBoxes: [faceBox1])
        #expect(sB1.translationMagnitude / 0.040 < 0.50)

        // Subcase C: Frame 0 has face, Frame 1 person sits totally still
        let dC = VisionMotionDetector()
        _ = dC.analyzeFrame(makeWebcamImage(dxPerson: 0, dyPerson: 0), faceBoundingBoxes: [faceBox0])
        let sC1 = dC.analyzeFrame(makeWebcamImage(dxPerson: 0, dyPerson: 0), faceBoundingBoxes: [faceBox0])
        #expect(sC1.translationMagnitude / 0.040 < 0.05)

        // Subcase D: Laptop actually moves / tilts (room moves by 20px)
        let sC2 = dC.analyzeFrame(makeWebcamImage(dxPerson: 0, dyPerson: 0, dxRoom: 20), faceBoundingBoxes: [faceBox0])
        #expect(sC2.translationMagnitude / 0.040 > 0.60)
    }
}
