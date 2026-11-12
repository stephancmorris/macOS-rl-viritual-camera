//
//  FrameMailboxes.swift
//  CinematicCoreMacOS
//
//  The two one-slot mailboxes between a camera's capture queue and the main
//  thread (D-02 path 2).
//
//  - `MotionTargetMailbox`: main thread → capture queue. What the picture
//    should aim at. The newest directive replaces the one before it.
//  - `ChannelFrameMailbox`: capture queue → main thread. The newest finished
//    frame, with the revisions it was made under, and the last good frame a
//    failed render repeats. It also holds the values the capture queue needs
//    to stamp and admit a frame (source generation, command epoch, shot
//    revision), so a frame from a retired generation is refused in the same
//    locked step that would have stored or held it.
//
//  Neither side waits for the other.
//

import CoreGraphics
import CoreVideo
import Foundation

/// What the capture-queue loop steps toward. Written by the main thread
/// whenever the mode, a command, a setting or a composed target changes.
nonisolated struct MotionDirective: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        /// Spring toward the wide view.
        case wide(target: CropEngine.CropRect)
        /// Spring toward `trackingTarget`, applied once per `trackingSerial`.
        case tracking
        /// Spring toward a crop centred on the operator's point.
        case manual(center: CGPoint)
        /// Deterministic sweep; `speed` is the phase rate, `height` the pan line.
        case autoPan(speed: Double, height: CGFloat, eased: Bool)
    }

    struct Boost: Sendable, Equatable {
        var smoothing: Float
        var until: TimeInterval
    }

    var mode: Mode = .wide(target: .fullFrame)
    /// This frame's spring smoothing. Nil leaves the core's value alone (pan).
    var smoothing: Float?
    /// Faster smoothing until a host time (preset change, band exit).
    var boost: Boost?
    /// Normalised crop aspect (width / height), for zoom and manual sizes.
    var aspect: CGFloat = 1
    /// Crop height of the selected shot when no shot move owns the size.
    var fixedHeight: CGFloat = 1
    var zoomUsesTopAnchor = false
    /// The composed tracking target and a serial that changes with each
    /// compose. The loop applies a target once, as the frame path did when it
    /// set a target only on frames the composer returned one.
    var trackingTarget: CropEngine.CropRect?
    var trackingSerial: UInt64 = 0

    /// Size of a manual or pan crop: the shot move's height when one is in
    /// flight, else the selected shot's.
    func cropSize(adjustedHeight: CGFloat?) -> CGSize {
        let height = min(1, 1 / aspect, adjustedHeight ?? fixedHeight)
        return CGSize(width: height * aspect, height: height)
    }
}

/// One slot, newest wins. Main thread writes, capture queue reads.
nonisolated final class MotionTargetMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var directive = MotionDirective()

    func write(_ newValue: MotionDirective) {
        lock.lock()
        directive = newValue
        lock.unlock()
    }

    func read() -> MotionDirective {
        lock.lock()
        defer { lock.unlock() }
        return directive
    }
}

/// The newest finished frame of one camera, and what admits a frame.
nonisolated final class ChannelFrameMailbox: @unchecked Sendable {
    /// Main-thread state the capture queue reads at the start and end of each
    /// frame. Written only by the main thread.
    struct Admission: Sendable, Equatable {
        var sourceGeneration: UInt64 = 0
        var controlEpoch: UInt64 = 0
        var shotRevision: UInt64 = 0
        var detectionGeneration: UInt64 = 0
        var isRunning = false
        var sourceMissing = false
        /// The main thread has per-frame work for this camera (detection, the
        /// lock machine, a shot move). False: the loop posts it nothing.
        var controlWanted = false
        /// The delivered frame size the controller has applied (aspect, wide
        /// target, composer floor) and published a directive for. The loop
        /// renders nothing from frames of any other size: a frame stepped
        /// with the previous size's directive would have the wrong aspect.
        var formatWidth = 0
        var formatHeight = 0

        var revisions: ChannelRevisions {
            ChannelRevisions(sourceGeneration: sourceGeneration, controlEpoch: controlEpoch, shotRevision: shotRevision)
        }
    }

    private let lock = NSLock()
    private var state = Admission()
    private var rendered: RenderedChannelFrame?
    private var source: CVPixelBuffer?
    private var program: CVPixelBuffer?
    private var renderedCount: UInt64 = 0
    private var repeatedCount: UInt64 = 0
    // The last good program frame, repeated when a render fails. Kept under
    // the same lock as the source generation, so a retired frame can never
    // refill it after the reset that retired it.
    private var heldBuffer: CVPixelBuffer?
    private var heldCrop: CropEngine.CropRect?
    private var holding = false

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var admission: Admission { locked { state } }

    /// Main thread only. A new source generation forgets the held frame and
    /// the finished frame in the same locked step.
    func update(_ change: (inout Admission) -> Void) {
        locked {
            let generation = state.sourceGeneration
            change(&state)
            if state.sourceGeneration != generation {
                heldBuffer = nil
                heldCrop = nil
                rendered = nil
            }
        }
    }

    // MARK: Hold-frame selection

    struct Selection {
        /// The frame to show: the new render, or the held one. Nil when a
        /// render failed and nothing was ever rendered.
        let buffer: CVPixelBuffer?
        let crop: CropEngine.CropRect?
        let isHolding: Bool
        let holdingChanged: Bool
    }

    /// A new render replaces the held frame; a failed one (nil) repeats it.
    /// Returns nil, and changes nothing, when `sourceGeneration` has retired.
    func selectProgram(rendered newBuffer: CVPixelBuffer?, crop newCrop: CropEngine.CropRect?,
                       sourceGeneration: UInt64) -> Selection? {
        locked {
            guard state.sourceGeneration == sourceGeneration else { return nil }
            if let newBuffer { heldBuffer = newBuffer; heldCrop = newCrop }
            let wasHolding = holding
            holding = newBuffer == nil
            return Selection(buffer: heldBuffer, crop: heldCrop, isHolding: holding, holdingChanged: holding != wasHolding)
        }
    }

    var isHolding: Bool { locked { holding } }
    var lastGoodCrop: CropEngine.CropRect? { locked { heldCrop } }

    /// Forget the held frame. `clearHolding` also drops the holding flag
    /// (session start and stop); a source loss keeps it.
    func resetHold(clearHolding: Bool) {
        locked {
            heldBuffer = nil
            heldCrop = nil
            if clearHolding { holding = false }
        }
    }

    // MARK: Capture queue → main thread

    /// The raw frame for the wide pane. Refused once its generation retired.
    @discardableResult
    func storeSource(_ buffer: CVPixelBuffer, sourceGeneration: UInt64) -> Bool {
        locked {
            guard state.isRunning, !state.sourceMissing, state.sourceGeneration == sourceGeneration else { return false }
            source = buffer
            return true
        }
    }

    /// Store a finished frame. Refused, in the same locked step, when the
    /// source generation it was rendered under has retired or the session
    /// stopped: a retired frame can never follow the clear that retired it.
    @discardableResult
    func store(_ frame: RenderedChannelFrame) -> Bool {
        locked {
            guard state.isRunning, !state.sourceMissing,
                  frame.revisions.sourceGeneration == state.sourceGeneration else { return false }
            rendered = frame
            program = frame.pixelBuffer
            renderedCount &+= 1
            if frame.isRepeat { repeatedCount &+= 1 }
            return true
        }
    }

    // MARK: Main-thread reads

    var latestRendered: RenderedChannelFrame? { locked { rendered } }
    var sourceBuffer: CVPixelBuffer? { locked { source } }
    var programBuffer: CVPixelBuffer? { locked { program } }
    var renderedFrameCount: UInt64 { locked { renderedCount } }
    var repeatedFrameCount: UInt64 { locked { repeatedCount } }

    func clearRendered() { locked { rendered = nil } }
    func clearProgramBuffer() { locked { program = nil } }
    func clearSourceBuffer() { locked { source = nil } }

    /// Test seam: a frame as if the loop had stored it, without admission.
    func setRenderedForTesting(_ frame: RenderedChannelFrame?) { locked { rendered = frame } }
}
