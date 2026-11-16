//
//  IdleInactivityEvaluator.swift
//  Pupil
//
//  Pure Sendable evaluator for auto-arming after sustained HID user inactivity,
//  with streak suppression so cancelling or disarming requires fresh user input
//  before another idle auto-arm can fire.
//

import Foundation

public struct IdleInactivityEvaluator: Sendable, Equatable {
    /// True after auto-arm has triggered (or been manually suppressed) during the current idle streak.
    /// Cleared automatically as soon as `idleSeconds < thresholdSeconds` (new user input detected).
    public private(set) var isSuppressedForCurrentStreak: Bool = false

    public init() {}

    /// Evaluates whether Pupil should automatically start arming based on current HID idle time.
    /// - Parameters:
    ///   - idleSeconds: Seconds elapsed since the last system-wide HID event (keyboard/mouse/trackpad).
    ///   - thresholdMinutes: Configured inactivity threshold in minutes (e.g. 5, 10, 15, 30).
    ///   - state: Current `SecurityState` of `SecurityCoordinator`.
    ///   - featureEnabled: Whether `settings.idleAutoArmEnabled` is `true`.
    /// - Returns: `true` if and only if the system should transition from `.disarmed` into arming now.
    public mutating func evaluate(
        idleSeconds: Double,
        thresholdMinutes: Int,
        state: SecurityState,
        featureEnabled: Bool
    ) -> Bool {
        guard featureEnabled else {
            isSuppressedForCurrentStreak = false
            return false
        }

        let thresholdSeconds = Double(max(1, thresholdMinutes) * 60)

        // Fresh user input lowered idleSeconds below threshold: clear streak suppression
        if idleSeconds < thresholdSeconds {
            isSuppressedForCurrentStreak = false
            return false
        }

        // Only auto-arm when currently disarmed and not already suppressed for this idle streak
        guard state == .disarmed, !isSuppressedForCurrentStreak else {
            return false
        }

        isSuppressedForCurrentStreak = true
        return true
    }

    /// Explicitly suppresses re-arming for the remainder of the current idle streak
    /// (e.g. when the user cancels during exit delay or disarms without generating a below-threshold HID sample yet).
    public mutating func suppressCurrentStreak() {
        isSuppressedForCurrentStreak = true
    }

    /// Resets evaluator state completely.
    public mutating func reset() {
        isSuppressedForCurrentStreak = false
    }
}
