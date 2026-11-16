//
//  DisplayTopologyEvaluator.swift
//  Pupil
//
//  Pure Sendable evaluator tracking external display topology transitions.
//  Ignores built-in MacBook displays and display attachments; triggers only when
//  one or more tracked external displays are physically disconnected.
//

import CoreGraphics
import Foundation

public enum DisplayTopologyEvent: Sendable, Equatable {
    case unchanged
    case externalDisplayAttached(addedCount: Int)
    case externalDisplayDisconnected(removedCount: Int)
}

public struct DisplayTopologySnapshot: Sendable, Equatable {
    public let externalDisplayIDs: Set<CGDirectDisplayID>
    public let builtInDisplayIDs: Set<CGDirectDisplayID>

    public init(
        externalDisplayIDs: Set<CGDirectDisplayID>,
        builtInDisplayIDs: Set<CGDirectDisplayID> = []
    ) {
        self.externalDisplayIDs = externalDisplayIDs
        self.builtInDisplayIDs = builtInDisplayIDs
    }

    /// Partitions raw `CGDirectDisplayID` values using a predicate (defaults to `CGDisplayIsBuiltin(id) != 0`).
    public init(
        allDisplayIDs: [CGDirectDisplayID],
        isBuiltIn: (CGDirectDisplayID) -> Bool = { CGDisplayIsBuiltin($0) != 0 }
    ) {
        var external = Set<CGDirectDisplayID>()
        var builtIn = Set<CGDirectDisplayID>()
        for id in allDisplayIDs {
            if isBuiltIn(id) {
                builtIn.insert(id)
            } else {
                external.insert(id)
            }
        }
        self.externalDisplayIDs = external
        self.builtInDisplayIDs = builtIn
    }
}

public struct DisplayTopologyEvaluator: Sendable, Equatable {
    public private(set) var baselineExternalIDs: Set<CGDirectDisplayID> = []
    public private(set) var hasBaseline: Bool = false

    public init() {}

    /// Latches the current external display set as the armed baseline.
    public mutating func latchBaseline(_ snapshot: DisplayTopologySnapshot) {
        baselineExternalIDs = snapshot.externalDisplayIDs
        hasBaseline = true
    }

    /// Clears the baseline when disarmed.
    public mutating func reset() {
        baselineExternalIDs.removeAll()
        hasBaseline = false
    }

    /// Evaluates a new topology snapshot against the tracked external display IDs.
    /// - Built-in display sleep/wake/dimming changes (`builtInDisplayIDs`) are completely ignored.
    /// - Newly attached external displays expand `baselineExternalIDs` so unplugging them later while still armed is also caught, and returns `.externalDisplayAttached(addedCount:)`.
    /// - Any previously tracked external display ID missing from `snapshot.externalDisplayIDs` updates the baseline to the remaining set and returns `.externalDisplayDisconnected(removedCount:)`.
    public mutating func evaluate(_ snapshot: DisplayTopologySnapshot) -> DisplayTopologyEvent {
        if !hasBaseline {
            latchBaseline(snapshot)
            return .unchanged
        }

        let currentExternal = snapshot.externalDisplayIDs
        let removed = baselineExternalIDs.subtracting(currentExternal)
        let added = currentExternal.subtracting(baselineExternalIDs)

        baselineExternalIDs = currentExternal

        if !removed.isEmpty {
            return .externalDisplayDisconnected(removedCount: removed.count)
        }
        if !added.isEmpty {
            return .externalDisplayAttached(addedCount: added.count)
        }
        return .unchanged
    }
}
