import CoreGraphics
import Foundation
import Testing
@testable import Pupil

enum SynthScene {
    /// Deterministic textured scene (blobs + lines), optionally shifted/scaled.
    static func make(w: Int = 640, h: Int = 480, seed: UInt64 = 1, dx: Int = 0, dy: Int = 0, blank: Bool = false, noise: Double = 0, contrast: Double = 1, texMaxFrac: Double = 1) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.55, green: 0.55, blue: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if !blank {
            var s = seed
            func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double((s >> 33) & 0xFFFFFF) / Double(0xFFFFFF) }
            for _ in 0..<120 {
                let x = rnd() * Double(w), y = rnd() * Double(h) * texMaxFrac, r = 6 + rnd() * 40
                ctx.setFillColor(red: 0.55 + (rnd() - 0.5) * contrast, green: 0.55 + (rnd() - 0.5) * contrast, blue: 0.5 + (rnd() - 0.5) * contrast, alpha: 1)
                ctx.fillEllipse(in: CGRect(x: x - r + Double(dx), y: y - r + Double(dy), width: 2 * r, height: 2 * r))
            }
        }
        if noise > 0 {
            var s: UInt64 = 99
            for _ in 0..<4000 {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let v = Double((s >> 33) & 0xFF) / 255
                ctx.setFillColor(red: v, green: v, blue: v, alpha: noise)
                ctx.fill(CGRect(x: Int((s >> 8) % UInt64(w)), y: Int((s >> 20) % UInt64(h)), width: 2, height: 2))
            }
        }
        return ctx.makeImage()!
    }
}

@Suite("Spatial lift detection on synthetic frames")
struct SpatialLiftSyntheticTests {
    private func sample(anchor: CGImage, current: CGImage) -> MotionSample {
        let d = VisionMotionDetector()
        _ = d.analyzeFrame(anchor, timestamp: 0)
        return d.analyzeFrame(current, timestamp: 0.1)
    }

    @Test("Sensor noise on a flat wall is not read as motion (untrusted, not garbage)")
    func flatWallNoiseIsIgnored() {
        let s = sample(anchor: SynthScene.make(blank: true), current: SynthScene.make(blank: true, noise: 0.3))
        #expect(s.isRegistrationReliable == false)
        #expect(s.translationMagnitude == 0)
    }

    @Test("A blank ceiling band no longer hides motion in the rest of the frame")
    func blankCeilingBandStillDetectsShift() {
        let still = sample(anchor: SynthScene.make(texMaxFrac: 0.7), current: SynthScene.make(noise: 0.15, texMaxFrac: 0.7))
        let moved = sample(anchor: SynthScene.make(texMaxFrac: 0.7), current: SynthScene.make(dx: 40, noise: 0.15, texMaxFrac: 0.7))
        #expect(still.translationMagnitude < SpatialMotionSensitivity.medium.translationDeadband)
        #expect(moved.translationMagnitude >= SpatialMotionSensitivity.medium.translationDeadband)
    }

    @Test("Picking the laptop up (scene no longer overlaps anchor) still triggers via frame-to-frame motion")
    func bigMoveTriggers() {
        let d = VisionMotionDetector()
        var agg = MotionTemporalAggregator()
        _ = agg.ingest(d.analyzeFrame(SynthScene.make(), timestamp: 0))
        var triggered = false
        for i in 1...25 {
            let frame = SynthScene.make(seed: UInt64(i + 10), noise: 0.15) // new view every frame
            triggered = agg.ingest(d.analyzeFrame(frame, timestamp: Double(i) * 0.1)).isTamperTriggered || triggered
        }
        #expect(triggered)
    }

    @Test("A noisy score that dips below the deadband mid-lift does not reset the 1.2s clock")
    func dropoutTolerance() {
        var agg = MotionTemporalAggregator()
        _ = agg.ingest(.anchor(at: 0))
        var triggered = false
        for i in 1...20 {
            let dip = (i % 4 == 0)
            let snap = agg.ingest(MotionSample(timestamp: Double(i) * 0.1, translationMagnitude: dip ? 0 : 0.2))
            triggered = triggered || snap.isTamperTriggered
        }
        #expect(triggered)
    }
}
