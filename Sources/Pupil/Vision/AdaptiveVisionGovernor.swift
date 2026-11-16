//
//  AdaptiveVisionGovernor.swift
//  Pupil
//
//  Deterministic policy engine dynamically adjusting Vision frame analysis FPS
//  based on power source, battery percentage, macOS thermal state, and activity suspicion.
//

import Foundation

public struct AdaptiveVisionGovernor: Sendable, Equatable {
    public static let fullRateFPS: Double = 10.0
    public static let ecoRateFPS: Double = 5.0
    public static let criticalThermalFPS: Double = 2.0
    public static let lowBatteryThresholdPercent: Int = 30

    public init() {}

    /// Pure deterministic policy evaluation returning the target Vision analysis rate in frames per second.
    /// - Parameters:
    ///   - isOnACPower: `true` when MacBook is connected to AC power.
    ///   - batteryPercent: Current battery charge percentage (`0...100`).
    ///   - thermalState: Current `ProcessInfo.ThermalState` (`.nominal`, `.fair`, `.serious`, `.critical`).
    ///   - isActivitySuspected: `true` if a face is visible, gaze dwell is active, motion exceeds baseline, or tamper countdown/alarm is active.
    /// - Returns: Target FPS (`10.0`, `5.0`, or `2.0`).
    public static func evaluateTargetFPS(
        isOnACPower: Bool,
        batteryPercent: Int,
        thermalState: ProcessInfo.ThermalState,
        isActivitySuspected: Bool
    ) -> Double {
        if isActivitySuspected {
            return fullRateFPS
        }
        switch thermalState {
        case .serious, .critical:
            return criticalThermalFPS
        case .fair:
            return ecoRateFPS
        case .nominal:
            if !isOnACPower && batteryPercent < lowBatteryThresholdPercent {
                return ecoRateFPS
            }
            return fullRateFPS
        @unknown default:
            return ecoRateFPS
        }
    }

    /// Instance convenience wrapper forwarding to `Self.evaluateTargetFPS(...)`.
    public func evaluate(
        isOnACPower: Bool,
        batteryPercent: Int,
        thermalState: ProcessInfo.ThermalState,
        isActivitySuspected: Bool
    ) -> Double {
        Self.evaluateTargetFPS(
            isOnACPower: isOnACPower,
            batteryPercent: batteryPercent,
            thermalState: thermalState,
            isActivitySuspected: isActivitySuspected
        )
    }
}
