//
//  AlertNotifier.swift
//  Pupil
//
//  Ordered, retrying outbox for phone alerts. The security state machine only says *what* happened;
//  delivery, retries and result logging live here so transitions never depend on the network.
//

import Foundation

public struct AlertMessage: Sendable, Equatable {
    public let title: String
    public let body: String
    public let severity: String
    public let tag: String
    public let snapshotBase64: String?

    public init(
        title: String,
        body: String,
        severity: String = "high",
        tag: String,
        snapshotBase64: String? = nil
    ) {
        self.title = title
        self.body = body
        self.severity = severity
        self.tag = tag
        self.snapshotBase64 = snapshotBase64
    }
}

public enum PushOutcome: Sendable, Equatable {
    case delivered
    /// No paired phone / relay disabled. Nothing to retry and nothing worth reporting.
    case notConfigured
    /// Timeout, 429 or 5xx: worth trying again.
    case retryableFailure(String)
    /// Bad endpoint or 4xx (e.g. 410 Gone): retrying cannot help.
    case permanentFailure(String)
}

public enum AlertResult: Sendable, Equatable {
    case delivered(attempts: Int)
    case failed(attempts: Int, reason: String)
    case superseded
}

@MainActor
public final class AlertNotifier {
    public typealias Transport = @MainActor (AlertMessage) async -> PushOutcome
    public typealias Sleeper = @MainActor (Double) async -> Void

    public static let defaultBackoffSeconds: [Double] = [1, 3, 8]

    private let transport: Transport
    private let sleep: Sleeper
    private let backoffSeconds: [Double]
    private var pending: [AlertMessage] = []
    private var inFlightMessage: AlertMessage?
    private var cancelInFlight = false
    private var isDraining = false
    private var backoffWakeContinuation: CheckedContinuation<Void, Never>?
    private var backoffSleepTask: Task<Void, Never>?
    private var backoffGeneration: UInt64 = 0

    /// Called once per message with its final result (not for `.notConfigured`).
    public var onResult: ((AlertMessage, AlertResult) -> Void)?

    public init(
        backoffSeconds: [Double] = AlertNotifier.defaultBackoffSeconds,
        transport: @escaping Transport,
        sleep: @escaping Sleeper = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.backoffSeconds = backoffSeconds
        self.transport = transport
        self.sleep = sleep
    }

    public var pendingCount: Int { pending.count }

    /// Immediately wakes or restarts draining of pending messages (e.g., when network interface transitions or recovers).
    public func flushPendingNow() {
        resumeBackoff()
        startDrainingIfNeeded()
    }

    /// Queues a message. Messages are delivered in order, one at a time.
    /// - A newer message with the same tag replaces one still waiting.
    /// - A critical message drops waiting lower-severity tamper countdown messages, which are stale
    ///   once the siren has latched.
    public func send(_ message: AlertMessage) {
        dropSuperseded(by: message)
        pending.append(message)
        startDrainingIfNeeded()
    }

    /// Resolves when everything queued so far has finished. Used by tests.
    public func waitUntilIdle() async {
        while isDraining || !pending.isEmpty {
            await Task.yield()
        }
    }

    private func dropSuperseded(by message: AlertMessage) {
        var kept: [AlertMessage] = []
        for queued in pending {
            let sameTag = queued.tag == message.tag
            let staleCountdown = message.severity == "critical"
                && queued.severity != "critical"
                && queued.tag == "pupil-tamper"
            if sameTag || staleCountdown {
                onResult?(queued, .superseded)
            } else {
                kept.append(queued)
            }
        }
        pending = kept

        if let current = inFlightMessage {
            let sameTag = current.tag == message.tag
            let staleCountdown = message.severity == "critical"
                && current.severity != "critical"
                && current.tag == "pupil-tamper"
            if sameTag || staleCountdown {
                cancelInFlight = true
                resumeBackoff()
                onResult?(current, .superseded)
            }
        }
    }

    private func startDrainingIfNeeded() {
        guard !isDraining else { return }
        isDraining = true
        Task { @MainActor [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !pending.isEmpty {
            let message = pending.removeFirst()
            await deliver(message)
        }
        isDraining = false
    }

    private func deliver(_ message: AlertMessage) async {
        inFlightMessage = message
        cancelInFlight = false
        defer {
            inFlightMessage = nil
            cancelInFlight = false
        }
        var attempts = 0
        var lastReason = "unknown error"
        while true {
            guard !cancelInFlight else { return }
            attempts += 1
            switch await transport(message) {
            case .delivered:
                if !cancelInFlight {
                    onResult?(message, .delivered(attempts: attempts))
                }
                return
            case .notConfigured:
                return
            case .permanentFailure(let reason):
                if !cancelInFlight {
                    onResult?(message, .failed(attempts: attempts, reason: reason))
                }
                return
            case .retryableFailure(let reason):
                lastReason = reason
            }
            guard !cancelInFlight else { return }
            guard attempts <= backoffSeconds.count else {
                onResult?(message, .failed(attempts: attempts, reason: lastReason))
                return
            }
            await waitForBackoff(seconds: backoffSeconds[attempts - 1])
            guard !cancelInFlight else { return }
        }
    }

    private func waitForBackoff(seconds: Double) async {
        backoffGeneration &+= 1
        let generation = backoffGeneration
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                backoffWakeContinuation = continuation
                backoffSleepTask = Task { @MainActor [weak self] in
                    await self?.sleep(seconds)
                    self?.resumeBackoff(generation: generation)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeBackoff(generation: generation)
            }
        }
    }

    private func resumeBackoff(generation: UInt64? = nil) {
        if let generation, generation != backoffGeneration {
            return
        }
        backoffSleepTask?.cancel()
        backoffSleepTask = nil
        if let continuation = backoffWakeContinuation {
            backoffWakeContinuation = nil
            continuation.resume()
        }
    }
}
