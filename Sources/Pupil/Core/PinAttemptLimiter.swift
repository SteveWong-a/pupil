//
//  PinAttemptLimiter.swift
//  Pupil
//
//  Deterministic exponential backoff rate-limiter for failed PIN disarm attempts.
//

import Foundation

public enum PinAttemptStatus: Sendable, Equatable {
    case allowed
    case lockedOut(remainingSeconds: Int)
    case escalateToAlarm(remainingSeconds: Int)

    public var isLockedOut: Bool {
        switch self {
        case .allowed:
            return false
        case .lockedOut, .escalateToAlarm:
            return true
        }
    }

    public var remainingSeconds: Int {
        switch self {
        case .allowed:
            return 0
        case .lockedOut(let seconds), .escalateToAlarm(let seconds):
            return seconds
        }
    }
}

public struct PinAttemptLimiter: Sendable, Equatable {
    public static let tier1FailureThreshold = 5
    public static let tier1LockoutSeconds: TimeInterval = 15

    public static let tier2FailureThreshold = 8
    public static let tier2LockoutSeconds: TimeInterval = 60

    public static let alarmEscalationFailureThreshold = 10
    public static let alarmEscalationLockoutSeconds: TimeInterval = 300

    public private(set) var failedAttemptCount: Int = 0
    public private(set) var lockoutDeadline: TimeInterval?

    public init() {}

    /// Evaluates whether a PIN attempt is currently permitted at `now` (epoch seconds).
    public func status(at now: TimeInterval) -> PinAttemptStatus {
        guard let deadline = lockoutDeadline, now < deadline else {
            return .allowed
        }
        let remaining = max(1, Int(ceil(deadline - now)))
        return .lockedOut(remainingSeconds: remaining)
    }

    /// Convenience overload accepting `Date`.
    public func status(at date: Date) -> PinAttemptStatus {
        status(at: date.timeIntervalSince1970)
    }

    /// Records a failed PIN attempt at `now` (epoch seconds) and returns the resulting policy decision.
    /// If already locked out at `now`, does not advance the failure counter and returns the active lockout status.
    @discardableResult
    public mutating func recordFailure(at now: TimeInterval) -> PinAttemptStatus {
        let current = status(at: now)
        if current.isLockedOut {
            return current
        }

        failedAttemptCount += 1

        if failedAttemptCount >= Self.alarmEscalationFailureThreshold {
            let duration = Self.alarmEscalationLockoutSeconds
            lockoutDeadline = now + duration
            return .escalateToAlarm(remainingSeconds: Int(duration))
        } else if failedAttemptCount >= Self.tier2FailureThreshold {
            let duration = Self.tier2LockoutSeconds
            lockoutDeadline = now + duration
            return .lockedOut(remainingSeconds: Int(duration))
        } else if failedAttemptCount >= Self.tier1FailureThreshold {
            let duration = Self.tier1LockoutSeconds
            lockoutDeadline = now + duration
            return .lockedOut(remainingSeconds: Int(duration))
        } else {
            lockoutDeadline = nil
            return .allowed
        }
    }

    /// Convenience overload accepting `Date`.
    @discardableResult
    public mutating func recordFailure(at date: Date) -> PinAttemptStatus {
        recordFailure(at: date.timeIntervalSince1970)
    }

    /// Clears all failed attempt history and active lockouts upon valid authentication.
    public mutating func recordSuccess() {
        failedAttemptCount = 0
        lockoutDeadline = nil
    }
}
