//
//  CropMotionCore.swift
//  CinematicCoreMacOS
//
//  The crop's motion state, as a plain class (D-02 path 2): the target, the
//  spring, the zoom move, the pan placement and the quality floor. It has no
//  actor and publishes nothing. A camera's capture queue steps it once per
//  frame; the main thread writes commands into it.
//
//  The state is one value (`State`). Every call takes a short lock around a
//  read or a write of that value, never around other work.
//
//  A main-thread transaction (`beginTransaction` / `endTransaction`) is
//  staged: it works on a copy, and the copy replaces the live state in one
//  locked assignment when the transaction ends. While it is open the capture
//  queue keeps stepping the live state, so a slow command handler, lock-
//  machine tick or composer never delays a frame, and the capture queue never
//  sees half of a command. The steps it took meanwhile are replaced by the
//  staged state; the spring and the zoom are stepped by elapsed time, so the
//  next step covers that time again from the new state.
//
//  `CropEngine` is the main-thread wrapper: settings, published mirrors and
//  the renderer. Tests keep calling the wrapper synchronously.
//

import CoreGraphics
import Foundation

nonisolated final class CropMotionCore: @unchecked Sendable {
    typealias CropRect = CropEngine.CropRect
    typealias QualityFloor = CropEngine.QualityFloor

    /// What the main-thread wrapper mirrors for the interface.
    struct Flags: Equatable, Sendable {
        var hasZoomAdjustment = false
        var isZoomLimited = false
        var zoomDirection: OperatorCommand.ZoomDirection?
        var isInterpolating = false
    }

    /// What a render needs from one step.
    struct Snapshot: Sendable {
        let crop: CropRect
        let outputSize: CGSize
        let smoothingFactor: Float
        let highQuality: Bool
    }

    /// All of the motion state, as one value: plain data and the rules that
    /// step it. No lock in here; the class below guards the copies.
    struct State: Sendable {
        // MARK: Settings (written by the wrapper)

        var settings = CropEngine.Config()
        /// Smoothing for the current frame; nil uses the operator's setting.
        var liveSmoothing: Float?
        private var effectiveSmoothing: Float { liveSmoothing ?? settings.transitionSmoothing }

        // MARK: Crop state

        private(set) var currentCrop: CropRect = .fullFrame {
            didSet { revision &+= 1 }
        }
        var targetCrop: CropRect = .fullFrame {
            didSet {
                revision &+= 1
                if !flags.isInterpolating { flags.isInterpolating = true }
            }
        }
        /// Bumped on every crop write; the wrapper republishes its mirror
        /// only when this moved.
        private(set) var revision: UInt64 = 0
        private(set) var flags = Flags()
        var qualityFloor: QualityFloor = .unconstrained

        /// Serial of the composed tracking target last applied (see
        /// `MotionDirective.trackingSerial`). Kept with the state, so a
        /// target the capture queue applied to a state that a transaction
        /// then replaced is applied again.
        var appliedTargetSerial: UInt64 = 0

        // MARK: Zoom state

        private var zoomHeight: CGFloat?
        private var zoomDestination: CGFloat = 1
        private var zoomVelocity: CGFloat = 0
        private var zoomLastTick: TimeInterval?
        private var zoomAspect: CGFloat = 1
        private var zoomAnchorCrop: CropRect?
        private var directorZoom: (trajectory: DirectorShotMoveTrajectory, elapsed: TimeInterval, aspect: CGFloat, floor: CGFloat)?
        private var deterministicPan = false
        var zoomUsesTopAnchor = false
        var adjustedHeight: CGFloat? { zoomHeight }
        var zoomHasLanded: Bool { zoomHeight != nil && flags.zoomDirection == nil && !flags.hasZoomAdjustment }

        // MARK: Spring state

        private var velocityOrigin: CGPoint = .zero
        private var velocitySize: CGSize = .zero
        private var lastInterpolationTime: TimeInterval = 0

        // MARK: Target

        /// Assign the target with the quality floor applied, so no caller can ask
        /// for a crop tighter than the floor. Identical targets are dropped: the
        /// frame path re-sends the same crop, and re-assigning it would restart
        /// interpolation bookkeeping for no motion.
        mutating func setTargetCrop(_ crop: CropRect) {
            zoomAnchorCrop = crop
            let sized = zoomHeight.map { resized(crop, height: $0) } ?? crop
            let floored = sized.clampedToQualityFloor(qualityFloor).clamped()
            if zoomHeight == nil {
                let limited = crop.size.height <= qualityFloor.minCropHeightFraction
                if flags.isZoomLimited != limited { flags.isZoomLimited = limited }
            }
            guard floored != targetCrop else { return }
            targetCrop = floored
        }

        mutating func resetToFullFrame(aspect: CGFloat? = nil) {
            if let aspect {
                targetCrop = .widest(aspect: aspect)
            } else {
                targetCrop = .fullFrame
            }
        }

        /// Jump to the target immediately (no smooth transition).
        mutating func jumpToTarget() {
            currentCrop = targetCrop
            velocityOrigin = .zero
            velocitySize = .zero
            if flags.isInterpolating { flags.isInterpolating = false }
            lastInterpolationTime = 0
        }

        // MARK: Zoom

        // Size has its own critically damped, rate-limited log-space motion.
        // Tracking catch-up stiffness never changes the speed of a shot move.

        mutating func adoptVisibleSize(from visible: CropRect? = nil) {
            directorZoom = nil
            if let visible { currentCrop = visible }
            zoomHeight = currentCrop.size.height
            zoomDestination = currentCrop.size.height
            zoomAspect = currentCrop.size.width / currentCrop.size.height
            zoomAnchorCrop = currentCrop
            targetCrop = currentCrop
            zoomVelocity = 0
            velocitySize = .zero
            zoomLastTick = nil
            flags.hasZoomAdjustment = true
        }

        mutating func beginZoom(_ direction: OperatorCommand.ZoomDirection, to height: CGFloat,
                       visibleCrop: CropRect? = nil) {
            adoptVisibleSize(from: visibleCrop)
            flags.zoomDirection = direction
            let upper = min(1, 1 / zoomAspect)
            let lower = min(upper, max(0.001, qualityFloor.minCropHeightFraction))
            zoomDestination = min(upper, max(lower, height))
            flags.isZoomLimited = height < lower || (direction == .pushIn && zoomDestination <= lower)
        }

        /// A separate explicit Director path: one adjacent rung, paced in ladder
        /// steps per second over its actual visible/clamped log-height distance.
        /// Operator zoom retains its existing velocity and acceleration limits.
        @discardableResult
        mutating func beginDirectorZoom(_ direction: OperatorCommand.ZoomDirection, to height: CGFloat,
                               maximumRate: Double, visibleCrop: CropRect) -> Bool {
            let aspect = visibleCrop.size.width / visibleCrop.size.height
            guard aspect.isFinite, aspect > 0, height.isFinite else { return false }
            let upper = min(1, 1 / aspect)
            let lower = min(upper, max(0.001, qualityFloor.minCropHeightFraction))
            let destination = min(upper, max(lower, height))
            guard visibleCrop.size.height >= lower, visibleCrop.size.height <= upper,
                  let trajectory = DirectorShotMoveTrajectory(originHeight: Double(visibleCrop.size.height),
                      destinationHeight: Double(destination), maximumRate: maximumRate),
                  (direction == .pushIn ? destination < visibleCrop.size.height : destination > visibleCrop.size.height) else { return false }
            adoptVisibleSize(from: visibleCrop)
            flags.zoomDirection = direction
            zoomDestination = destination
            directorZoom = (trajectory, 0, aspect, qualityFloor.minCropHeightFraction)
            flags.isZoomLimited = height < lower
            return true
        }

        /// Stop at the visible size; a later push/pull starts a fresh shot move.
        mutating func endZoom() {
            directorZoom = nil
            guard flags.zoomDirection != nil else { return }
            flags.zoomDirection = nil
            zoomDestination = zoomHeight ?? currentCrop.size.height
            zoomVelocity = 0
        }

        mutating func clearZoomAdjustment() {
            directorZoom = nil
            zoomHeight = nil
            flags.zoomDirection = nil
            zoomVelocity = 0
            zoomLastTick = nil
            zoomAnchorCrop = nil
            flags.hasZoomAdjustment = false
            flags.isZoomLimited = false
        }

        private func resized(_ crop: CropRect, height: CGFloat) -> CropRect {
            let size = CGSize(width: height * zoomAspect, height: height)
            var center = crop.center
            if zoomUsesTopAnchor { center.y = crop.origin.y + crop.size.height - height / 2 }
            return CropRect(center: center, size: size).clamped()
        }

        mutating func advanceZoom(now: TimeInterval, aspect: CGFloat) {
            deterministicPan = false
            if var move = directorZoom {
                // A geometry change retires this trajectory at its visible size.
                // It cannot silently turn a quality-floor update into a fast move.
                guard now.isFinite, now >= 0, aspect == move.aspect,
                      qualityFloor.minCropHeightFraction == move.floor,
                      zoomLastTick.map({ now >= $0 }) ?? true else { endZoom(); return }
                let delta = min(0.1, max(0, now - (zoomLastTick ?? now)))
                zoomLastTick = now
                move.elapsed += delta
                let height = CGFloat(move.trajectory.height(at: move.elapsed))
                zoomHeight = height
                currentCrop = resized(currentCrop, height: height)
                targetCrop = resized(zoomAnchorCrop ?? targetCrop, height: height)
                if move.elapsed >= move.trajectory.duration {
                    directorZoom = nil
                    flags.zoomDirection = nil
                    flags.hasZoomAdjustment = false
                } else { directorZoom = move }
                return
            }
            zoomAspect = max(0.001, aspect)
            guard var height = zoomHeight else { return }
            let upper = min(1, 1 / zoomAspect)
            let lower = min(upper, max(0.001, qualityFloor.minCropHeightFraction))
            zoomDestination = min(upper, max(lower, zoomDestination))
            height = min(upper, max(lower, height))
            var remaining = CGFloat(min(0.1, max(0, now - (zoomLastTick ?? now))))
            zoomLastTick = now
            while remaining > 0, flags.zoomDirection != nil {
                let dt = min(remaining, 1 / 240)
                let error = log(zoomDestination / height)
                let acceleration = min(0.36, max(-0.36, error * 100 - zoomVelocity * 20))
                zoomVelocity = min(0.12, max(-0.12, zoomVelocity + acceleration * dt))
                let next = min(upper, max(lower, height * exp(zoomVelocity * dt)))
                if (zoomDestination - height) * (zoomDestination - next) <= 0 ||
                    (abs(error) < 0.00001 && abs(zoomVelocity) < 0.0001) {
                    height = zoomDestination
                    zoomVelocity = 0
                    flags.zoomDirection = nil
                    flags.hasZoomAdjustment = false
                } else { height = next }
                remaining -= dt
            }
            zoomHeight = height
            currentCrop = resized(currentCrop, height: height)
            targetCrop = resized(zoomAnchorCrop ?? targetCrop, height: height)
        }

        // MARK: Pan

        /// Pan position is deterministic; size is advanced separately above.
        mutating func placePan(center: CGPoint, baseSize: CGSize) {
            if zoomHeight == nil {
                let limited = baseSize.height <= qualityFloor.minCropHeightFraction
                if flags.isZoomLimited != limited { flags.isZoomLimited = limited }
            }
            let size = zoomHeight.map { CGSize(width: $0 * zoomAspect, height: $0) } ?? baseSize
            let crop = CropRect(center: center, size: size).clampedToQualityFloor(qualityFloor).clamped()
            targetCrop = crop
            currentCrop = crop
            velocityOrigin = .zero
            deterministicPan = true
        }

        // MARK: Spring

        /// Advance the spring toward the target and return what a render needs.
        mutating func tick(now: TimeInterval) -> Snapshot {
            updateInterpolation(now: now)
            return Snapshot(crop: currentCrop, outputSize: settings.outputSize,
                            smoothingFactor: effectiveSmoothing, highQuality: settings.useHighQuality)
        }

        private mutating func updateInterpolation(now: TimeInterval) {
            if deterministicPan { lastInterpolationTime = 0; return }
            guard flags.isInterpolating else {
                lastInterpolationTime = 0
                return
            }

            if lastInterpolationTime == 0 {
                lastInterpolationTime = now
                return // Skip first frame to get a valid delta time
            }

            let dt = CGFloat(min(now - lastInterpolationTime, 0.1)) // Cap dt at 100ms
            lastInterpolationTime = now

            // Map transitionSmoothing (0.05 to 0.30) to a spring stiffness.
            // Higher value = stiffer spring = faster snap.
            //
            // ×600 (July 2026, was ×300): the old default (0.10 → k=30, ω≈5.5)
            // trailed a walking speaker by ≈0.37 s of ramp lag and needed ~0.7–1.1
            // s to converge after a band exit — the dominant "tracking feels late"
            // term after the Steady Follow band itself. ×600 (0.10 → k=60, ω≈7.7)
            // roughly halves both (≈0.26 s ramp lag, ≈0.5 s step convergence),
            // which fits the spring term inside the 100–150 ms motion-lag budget
            // at walking speeds, while still attenuating bbox jitter: a ±0.3%
            // Vision box wobble at ~3 Hz passes through at <20% amplitude, well
            // under a visible pixel at output scale. The preset hierarchy is
            // unchanged (Locked Down 0.06 → k=36 smoothest, Fast Follow 0.20 →
            // k=120 snappiest); band exits additionally run the
            // fastFramingTransition window (see CameraManager).
            let stiffness = CGFloat(effectiveSmoothing) * 600.0
            let omega = sqrt(stiffness)
            let decay = exp(-omega * dt)
            // Exact critical-spring step: unlike Euler integration, a long frame
            // cannot invert/amplify the damping term. Zoom tracking uses this too.
            func spring(_ x: CGFloat, _ target: CGFloat, _ velocity: inout CGFloat) -> CGFloat {
                let offset = x - target
                let c = velocity + omega * offset
                velocity = (velocity - omega * c * dt) * decay
                return target + (offset + c * dt) * decay
            }

            let newX = spring(currentCrop.origin.x, targetCrop.origin.x, &velocityOrigin.x)
            let newY = spring(currentCrop.origin.y, targetCrop.origin.y, &velocityOrigin.y)
            if zoomHeight != nil {
                currentCrop = CropRect(origin: CGPoint(x: newX, y: newY), size: currentCrop.size).clamped()
                return
            }
            let newW = spring(currentCrop.size.width, targetCrop.size.width, &velocitySize.width)
            let newH = spring(currentCrop.size.height, targetCrop.size.height, &velocitySize.height)

            currentCrop = CropRect(
                origin: CGPoint(x: newX, y: newY),
                size: CGSize(width: newW, height: newH)
            ).clampedToQualityFloor(qualityFloor).clamped()

            // Check if we're close enough and moving slow enough to stop interpolating
            let distanceThreshold: CGFloat = 0.001
            let velocityThreshold: CGFloat = 0.005

            if abs(currentCrop.origin.x - targetCrop.origin.x) < distanceThreshold &&
               abs(currentCrop.origin.y - targetCrop.origin.y) < distanceThreshold &&
               abs(currentCrop.size.width - targetCrop.size.width) < distanceThreshold &&
               abs(currentCrop.size.height - targetCrop.size.height) < distanceThreshold &&
               abs(velocityOrigin.x) < velocityThreshold &&
               abs(velocityOrigin.y) < velocityThreshold &&
               abs(velocitySize.width) < velocityThreshold &&
               abs(velocitySize.height) < velocityThreshold {

                currentCrop = targetCrop
                velocityOrigin = .zero
                velocitySize = .zero
                flags.isInterpolating = false
                lastInterpolationTime = 0
            }
        }
    }

    // MARK: Storage

    private let lock = NSLock()
    /// What the capture queue steps and renders from.
    private var live = State()
    /// The main thread's working copy while a transaction is open.
    private var staged: State?
    private var transactionDepth = 0
    private var statsAccumulator = CropEngine.Stats()

    private func read<T>(_ body: (State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(staged ?? live)
    }

    /// A write from outside the frame loop: the staged copy while a
    /// transaction is open, else the live state.
    private func write<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        if staged != nil { return body(&staged!) }
        return body(&live)
    }

    /// The capture queue's step: always the live state, never a staged copy,
    /// and never waiting on a transaction. `body` should read the motion
    /// directive in here, so the directive and the state it steps belong to
    /// the same side of any transaction.
    func step<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&live)
    }

    /// Open a main-thread transaction. Until the matching `endTransaction`,
    /// every call below reads and writes a staged copy. Nests.
    func beginTransaction() {
        lock.lock()
        if transactionDepth == 0 { staged = live }
        transactionDepth += 1
        lock.unlock()
    }

    /// Close a transaction. When the outermost one closes, the staged copy
    /// becomes the live state and `publish` runs in that same locked step,
    /// so the capture queue sees the new state and whatever `publish` wrote
    /// (the motion directive) together.
    func endTransaction(publish: (() -> Void)? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard transactionDepth > 0 else { return }
        transactionDepth -= 1
        guard transactionDepth == 0, let committed = staged else { return }
        live = committed
        staged = nil
        publish?()
    }

    var isInTransaction: Bool {
        lock.lock()
        defer { lock.unlock() }
        return transactionDepth > 0
    }

    // MARK: Reads

    var settings: CropEngine.Config {
        get { read { $0.settings } }
        set { write { $0.settings = newValue } }
    }
    var liveSmoothing: Float? {
        get { read { $0.liveSmoothing } }
        set { write { $0.liveSmoothing = newValue } }
    }
    var currentCrop: CropRect { read { $0.currentCrop } }
    var targetCrop: CropRect {
        get { read { $0.targetCrop } }
        set { write { $0.targetCrop = newValue } }
    }
    var revision: UInt64 { read { $0.revision } }
    var currentFlags: Flags { read { $0.flags } }
    var qualityFloor: QualityFloor {
        get { read { $0.qualityFloor } }
        set { write { $0.qualityFloor = newValue } }
    }
    var zoomUsesTopAnchor: Bool {
        get { read { $0.zoomUsesTopAnchor } }
        set { write { $0.zoomUsesTopAnchor = newValue } }
    }
    var adjustedHeight: CGFloat? { read { $0.adjustedHeight } }
    var zoomHasLanded: Bool { read { $0.zoomHasLanded } }

    /// The capture queue learned the delivered size. Written to the live
    /// state and to any staged copy, so a transaction open at that moment
    /// cannot put the old floor back.
    func setDeliveredQualityFloor(_ floor: QualityFloor) {
        lock.lock()
        live.qualityFloor = floor
        staged?.qualityFloor = floor
        lock.unlock()
    }

    // MARK: Render statistics (not part of the motion state)

    var renderStats: CropEngine.Stats {
        lock.lock()
        defer { lock.unlock() }
        return statsAccumulator
    }

    func recordRender(renderTime: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        statsAccumulator.lastRenderTime = renderTime
        statsAccumulator.totalFramesRendered += 1
        let alpha: TimeInterval = 0.1
        statsAccumulator.averageRenderTime = (alpha * renderTime) + ((1 - alpha) * statsAccumulator.averageRenderTime)
    }

    // MARK: Writes (see `State` for each rule)

    func setTargetCrop(_ crop: CropRect) { write { $0.setTargetCrop(crop) } }
    func resetToFullFrame(aspect: CGFloat? = nil) { write { $0.resetToFullFrame(aspect: aspect) } }
    func jumpToTarget() { write { $0.jumpToTarget() } }
    func adoptVisibleSize(from visible: CropRect? = nil) { write { $0.adoptVisibleSize(from: visible) } }
    func beginZoom(_ direction: OperatorCommand.ZoomDirection, to height: CGFloat, visibleCrop: CropRect? = nil) {
        write { $0.beginZoom(direction, to: height, visibleCrop: visibleCrop) }
    }
    @discardableResult
    func beginDirectorZoom(_ direction: OperatorCommand.ZoomDirection, to height: CGFloat,
                           maximumRate: Double, visibleCrop: CropRect) -> Bool {
        write { $0.beginDirectorZoom(direction, to: height, maximumRate: maximumRate, visibleCrop: visibleCrop) }
    }
    func endZoom() { write { $0.endZoom() } }
    func clearZoomAdjustment() { write { $0.clearZoomAdjustment() } }
    func advanceZoom(now: TimeInterval, aspect: CGFloat) { write { $0.advanceZoom(now: now, aspect: aspect) } }
    func placePan(center: CGPoint, baseSize: CGSize) { write { $0.placePan(center: center, baseSize: baseSize) } }
    func tick(now: TimeInterval) -> Snapshot { write { $0.tick(now: now) } }
}
