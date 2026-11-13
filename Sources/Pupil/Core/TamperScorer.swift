//
//  TamperScorer.swift
//  Pupil
//
//  Decides how hard to react to a tamper signal. Strong signals (charger, lid, lock, wake) act on
//  their own. A weak signal (camera motion / lens occlusion, which lighting changes can fake) only
//  warns until it persists or a second signal corroborates it.
//

import Foundation

public enum TamperConfidence: Sendable {
    case strong
    case weak
}

public extension TamperSource {
    var confidence: TamperConfidence {
        switch self {
        case .cameraMotionDetected: return .weak
        case .chargerUnplugged, .lidClosed, .screenLocked, .peripheralDisconnected, .wakeWhileArmed, .manualTest: return .strong
        }
    }
}

public enum TamperDecision: Sendable, Equatable {
    /// Unconfirmed weak signal: log it, do not start the countdown.
    case warn
    /// Start the normal grace countdown.
    case countdown
    /// Two independent signals agree (or one is already counting down): skip the grace period.
    case alarmNow
}

public struct TamperScorer: Sendable {
    /// How long a signal stays available to corroborate another one.
    public static let corroborationWindowSeconds: TimeInterval = 10
    /// A lone weak signal that keeps going this long is treated as real.
    public static let loneLiftEscalationSeconds: Double = 4
    public static let loneOcclusionEscalationSeconds: Double = 8

    private var lastSeen: [TamperSource: TimeInterval] = [:]

    public init() {}

    public mutating func reset() { lastSeen.removeAll() }

    public mutating func record(_ source: TamperSource, at now: TimeInterval) {
        lastSeen[source] = now
    }

    /// True if a different signal was seen inside the corroboration window.
    public func isCorroborated(excluding source: TamperSource, at now: TimeInterval) -> Bool {
        lastSeen.contains { key, time in
            key != source && now - time <= Self.corroborationWindowSeconds
        }
    }

    /// True if any weak signal (e.g. an unconfirmed camera warning) was seen inside the window.
    public func hasRecentWeakSignal(at now: TimeInterval) -> Bool {
        lastSeen.contains { key, time in
            key.confidence == .weak && now - time <= Self.corroborationWindowSeconds
        }
    }

    /// Decision for a weak signal.
    /// - Parameters:
    ///   - persistenceSeconds: how long the weak cue has been continuously present.
    ///   - isOcclusion: lens covered (needs longer before a lone signal counts, since lights going out look the same).
    ///   - alreadyCountingDown: a signal already started the grace countdown.
    public func decideWeak(
        _ source: TamperSource,
        persistenceSeconds: Double,
        isOcclusion: Bool,
        alreadyCountingDown: Bool,
        at now: TimeInterval
    ) -> TamperDecision {
        if alreadyCountingDown {
            // A grace countdown is already running. Never cut the owner's disarm window short
            // simply because camera motion occurs while they reach for the keyboard.
            return .warn
        }
        if isCorroborated(excluding: source, at: now) {
            // Corroborated by another tamper signal within the window: start grace countdown
            // immediately without requiring the full lone-persistence duration.
            return .countdown
        }
        let needed = isOcclusion ? Self.loneOcclusionEscalationSeconds : Self.loneLiftEscalationSeconds
        return persistenceSeconds >= needed ? .countdown : .warn
    }
}
