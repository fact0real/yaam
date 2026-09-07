//
//  DigitalTargetQueueEngine.swift
//  YAAM
//
//  Smart Target Auto-Sequence Queue & 15-second TX Synchronization Engine
//  Allows hands-free queuing of wanted DX entities / grids, synchronizing
//  dispatch with exact FT8/FT4 period boundaries.
//

import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Queue Item Model

public enum TargetQueueStatus: String, Sendable, Equatable {
    case queued = "Queued"
    case calling = "Calling"
    case awaitingReport = "Awaiting Report"
    case qsoInProgress = "In Progress"
    case completed = "Completed"
    case expired = "Expired"
}

public struct QueuedTarget: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let callsign: String
    public let grid: String
    public let deltaFrequencyHz: UInt32
    public let snr: Int32
    public let mode: String
    public var attempts: Int
    public var maxAttempts: Int
    public var status: TargetQueueStatus
    public let enqueuedAt: Date

    public init(
        id: UUID = UUID(),
        callsign: String,
        grid: String,
        deltaFrequencyHz: UInt32,
        snr: Int32,
        mode: String = "FT8",
        attempts: Int = 0,
        maxAttempts: Int = 3,
        status: TargetQueueStatus = .queued,
        enqueuedAt: Date = Date()
    ) {
        self.id = id
        self.callsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.grid = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.deltaFrequencyHz = deltaFrequencyHz
        self.snr = snr
        self.mode = mode
        self.attempts = attempts
        self.maxAttempts = maxAttempts
        self.status = status
        self.enqueuedAt = enqueuedAt
    }
}

// MARK: - Smart Target Queue Engine

@MainActor
public final class DigitalTargetQueueEngine: ObservableObject {
    public static let shared = DigitalTargetQueueEngine()

    @Published public var queue: [QueuedTarget] = []
    @Published public var activeTarget: QueuedTarget? = nil
    @Published public var isAutoPilotActive: Bool = false
    @Published public var secondsRemainingInCycle: Double = 15.0
    @Published public var lastDispatchMessage: String = ""

    private var syncTimer: DispatchSourceTimer?
    private let queueLock = NSLock()

    private init() {
        startPrecisionCycleTimer()
    }

    deinit {
        syncTimer?.cancel()
    }

    // MARK: - Queue Management

    public func enqueue(callsign: String, grid: String, deltaFrequencyHz: UInt32, snr: Int32, mode: String = "FT8") {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCall.isEmpty else { return }

        // Prevent duplicate queueing
        if queue.contains(where: { $0.callsign == cleanCall }) || activeTarget?.callsign == cleanCall {
            return
        }

        let newTarget = QueuedTarget(
            callsign: cleanCall,
            grid: grid,
            deltaFrequencyHz: deltaFrequencyHz,
            snr: snr,
            mode: mode
        )

        queue.append(newTarget)
        if activeTarget == nil {
            advanceToNextTarget()
        }
    }

    public func remove(id: UUID) {
        queue.removeAll(where: { $0.id == id })
        if activeTarget?.id == id {
            advanceToNextTarget()
        }
    }

    public func clear() {
        queue.removeAll()
        activeTarget = nil
        isAutoPilotActive = false
    }

    public func toggleAutoPilot() {
        isAutoPilotActive.toggle()
        if isAutoPilotActive && activeTarget == nil && !queue.isEmpty {
            advanceToNextTarget()
        }
    }

    public func advanceToNextTarget() {
        if let current = activeTarget, current.status == .calling || current.status == .qsoInProgress {
            // Completed or canceled
        }

        if !queue.isEmpty {
            activeTarget = queue.removeFirst()
            activeTarget?.status = .queued
        } else {
            activeTarget = nil
        }
    }

    // MARK: - Cycle Synchronization & Automatic Dispatch

    private func startPrecisionCycleTimer() {
        syncTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            let now = Date().timeIntervalSince1970
            let period = 15.0 // FT8 cycle
            let remainder = now.truncatingRemainder(dividingBy: period)
            let remaining = period - remainder

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.secondsRemainingInCycle = remaining

                // Fire dispatch 250ms before period boundary (:00, :15, :30, :45)
                if remaining <= 0.35 && remaining >= 0.15 && self.isAutoPilotActive {
                    self.executeCycleDispatch()
                }
            }
        }
        timer.resume()
        self.syncTimer = timer
    }

    private func executeCycleDispatch() {
        guard var target = activeTarget else { return }

        target.attempts += 1
        target.status = .calling
        self.activeTarget = target

        lastDispatchMessage = "Dispatched ⚡️ \(target.callsign) [Try \(target.attempts)/\(target.maxAttempts)]"

        // Ingest into WSJT-X Reply via appState if available
        NotificationCenter.default.post(
            name: .init("DigitalTargetQueueDidTriggerCall"),
            object: nil,
            userInfo: [
                "callsign": target.callsign,
                "deltaHz": target.deltaFrequencyHz,
                "mode": target.mode
            ]
        )

        // Check max attempts
        if target.attempts >= target.maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 14.5) { [weak self] in
                guard let self = self else { return }
                if self.activeTarget?.id == target.id {
                    self.advanceToNextTarget()
                }
            }
        }
    }

    // Called when a QSO is logged or RR73/73 received
    public func notifyQSOCompleted(callsign: String) {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if activeTarget?.callsign == clean {
            activeTarget?.status = .completed
            advanceToNextTarget()
        }
    }
}
