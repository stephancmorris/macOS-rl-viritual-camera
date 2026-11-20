//
//  MotionDirectivePublisher.swift
//  CinematicCoreMacOS
//
//  G-01 stage 6. Owns the main-thread side of what the capture queue reads
//  (D-02 path 2), which used to be private stored properties of
//  CameraManager: the composed tracking target and its serial, the last
//  published directive, the coalesced refresh flag and the motion
//  transaction with its staged directive. CameraManager still builds each
//  directive from its own state.
//

import Foundation

@MainActor
final class MotionDirectivePublisher {
    private let targets: MotionTargetMailbox
    private var lastPublished: MotionDirective?
    private var refreshScheduled = false
    private var transactionDepth = 0
    private var staged: MotionDirective?

    /// The composed tracking target and its serial, published to the capture
    /// queue in the motion directive.
    private(set) var trackingTarget: CropEngine.CropRect?
    private(set) var trackingSerial: UInt64 = 0

    init(targets: MotionTargetMailbox) {
        self.targets = targets
    }

    func setTrackingTarget(_ crop: CropEngine.CropRect) {
        trackingTarget = crop
        trackingSerial &+= 1
    }

    /// A command set the target itself. A composed target the capture queue
    /// has not applied yet is older than that command and must not follow it.
    func retireTrackingTarget() {
        trackingTarget = nil
        trackingSerial &+= 1
    }

    /// Publish `directive` unless it is the one already published. Inside a
    /// transaction it is staged and published with the commit.
    func publish(_ directive: MotionDirective) {
        guard directive != lastPublished else { return }
        lastPublished = directive
        if transactionDepth > 0 { staged = directive } else { targets.write(directive) }
    }

    /// True when the caller should schedule a refresh on the next main turn.
    /// Coalesced; a transaction republishes when it ends, so none is needed.
    func claimRefresh() -> Bool {
        guard !refreshScheduled, transactionDepth == 0 else { return false }
        refreshScheduled = true
        return true
    }

    /// The scheduled refresh is running.
    func refreshStarted() {
        refreshScheduled = false
    }

    /// Stage this camera's writes to the motion core.
    func beginTransaction(core: CropMotionCore?) {
        transactionDepth += 1
        core?.beginTransaction()
    }

    /// Commit: the staged core state and the staged directive reach the
    /// capture queue in one locked step. The caller republishes first.
    func endTransaction(core: CropMotionCore?) {
        transactionDepth -= 1
        guard let core else { return }
        if transactionDepth == 0, let directive = staged {
            staged = nil
            let targets = targets
            core.endTransaction { targets.write(directive) }
        } else {
            core.endTransaction()
        }
    }
}

/// One control pump at a time, and the waiters that test seams park until
/// the main thread has taken every loop message. Used to be private stored
/// properties of CameraManager (G-01 stage 6).
@MainActor
final class ControlPumpGate {
    private(set) var isActive = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Start pumping. False when a pump is already running.
    func enter() -> Bool {
        guard !isActive else { return false }
        isActive = true
        return true
    }

    /// The pump finished; wake the waiters.
    func leave() {
        isActive = false
        resumeWaiters()
    }

    /// Park until the next `resumeWaiters`.
    func waitForNextSettle() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    func resumeWaiters() {
        guard !waiters.isEmpty else { return }
        let parked = waiters
        waiters.removeAll()
        for waiter in parked { waiter.resume() }
    }
}
