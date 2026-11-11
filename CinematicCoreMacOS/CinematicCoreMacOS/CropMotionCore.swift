//
//  CropMotionCore.swift
//  CinematicCoreMacOS
//
//  The crop's motion state, as a plain class (D-02 path 2): the target, the
//  spring, the zoom move, the pan placement and the quality floor. It has no
//  actor and publishes nothing. A camera's capture queue steps it once per
//  frame; the main thread writes commands into it. Each call takes the
//  core's lock, and `withLock` makes a run of calls one step.
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

    private let lock = NSRecursiveLock()

    /// Run several calls as one step. The lock is recursive, so the calls
    /// inside take it again without waiting.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: Settings (written by the wrapper)

    private var _settings = CropEngine.Config()
    var settings: CropEngine.Config {
        get { withLock { _settings } }
        set { withLock { _settings = newValue } }
    }

    private var _liveSmoothing: Float?
    /// Smoothing for the current frame; nil uses the operator's setting.
    var liveSmoothing: Float? {
        get { withLock { _liveSmoothing } }
        set { withLock { _liveSmoothing = newValue } }
    }
    private var effectiveSmoothing: Float { _liveSmoothing ?? _settings.transitionSmoothing }

    // MARK: Crop state

    private var _currentCrop: CropRect = .fullFrame {
        didSet { _revision &+= 1 }
    }
    private var _targetCrop: CropRect = .fullFrame {
        didSet {
            _revision &+= 1
            if !flags.isInterpolating { flags.isInterpolating = true }
        }
    }
    private var _revision: UInt64 = 0
    private var flags = Flags()
    private var _qualityFloor: QualityFloor = .unconstrained

    var currentCrop: CropRect { withLock { _currentCrop } }
    var targetCrop: CropRect {
        get { withLock { _targetCrop } }
        set { withLock { _targetCrop = newValue } }
    }
    /// Bumped on every crop write; the wrapper republishes its mirror only
    /// when this moved.
    var revision: UInt64 { withLock { _revision } }
    var currentFlags: Flags { withLock { flags } }
    var qualityFloor: QualityFloor {
        get { withLock { _qualityFloor } }
        set { withLock { _qualityFloor = newValue } }
    }

    // MARK: Zoom state

    private var zoomHeight: CGFloat?
    private var zoomDestination: CGFloat = 1
    private var zoomVelocity: CGFloat = 0
    private var zoomLastTick: TimeInterval?
    private var zoomAspect: CGFloat = 1
    private var zoomAnchorCrop: CropRect?
    private var directorZoom: (trajectory: DirectorShotMoveTrajectory, elapsed: TimeInterval, aspect: CGFloat, floor: CGFloat)?
    private var deterministicPan = false
    private var _zoomUsesTopAnchor = false
    var zoomUsesTopAnchor: Bool {
        get { withLock { _zoomUsesTopAnchor } }
        set { withLock { _zoomUsesTopAnchor = newValue } }
    }
    var adjustedHeight: CGFloat? { withLock { zoomHeight } }
    var zoomHasLanded: Bool {
        withLock { zoomHeight != nil && flags.zoomDirection == nil && !flags.hasZoomAdjustment }
    }

    // MARK: Spring state

    private var velocityOrigin: CGPoint = .zero
    private var velocitySize: CGSize = .zero
    private var lastInterpolationTime: TimeInterval = 0

    // MARK: Render statistics

    private var statsAccumulator = CropEngine.Stats()
    var renderStats: CropEngine.Stats { withLock { statsAccumulator } }

    func recordRender(renderTime: TimeInterval) {
        withLock {
            statsAccumulator.lastRenderTime = renderTime
            statsAccumulator.totalFramesRendered += 1
            let alpha: TimeInterval = 0.1
            statsAccumulator.averageRenderTime = (alpha * renderTime) + ((1 - alpha) * statsAccumulator.averageRenderTime)
        }
    }

    // MARK: Target

    /// Assign the target with the quality floor applied, so no caller can ask
    /// for a crop tighter than the floor. Identical targets are dropped: the
    /// frame path re-sends the same crop, and re-assigning it would restart
    /// interpolation bookkeeping for no motion.
    func setTargetCrop(_ crop: CropRect) {
        withLock {
            zoomAnchorCrop = crop
            let sized = zoomHeight.map { resized(crop, height: $0) } ?? crop
            let floored = sized.clampedToQualityFloor(_qualityFloor).clamped()
            if zoomHeight == nil {
                let limited = crop.size.height <= _qualityFloor.minCropHeightFraction
                if flags.isZoomLimited != limited { flags.isZoomLimited = limited }
            }
            guard floored != _targetCrop else { return }
            _targetCrop = floored
        }
    }

    func resetToFullFrame(aspect: CGFloat? = nil) {
        withLock {
            if let aspect {
                _targetCrop = .widest(aspect: aspect)
            } else {
                _targetCrop = .fullFrame
            }
        }
    }

    /// Jump to the target immediately (no smooth transition).
    func jumpToTarget() {
        withLock {
            _currentCrop = _targetCrop
            velocityOrigin = .zero
            velocitySize = .zero
            if flags.isInterpolating { flags.isInterpolating = false }
            lastInterpolationTime = 0
        }
    }

    // MARK: Zoom

    // Size has its own critically damped, rate-limited log-space motion.
    // Tracking catch-up stiffness never changes the speed of a shot move.

    func adoptVisibleSize(from visible: CropRect? = nil) {
        withLock {
            directorZoom = nil
            if let visible { _currentCrop = visible }
            zoomHeight = _currentCrop.size.height
            zoomDestination = _currentCrop.size.height
            zoomAspect = _currentCrop.size.width / _currentCrop.size.height
            zoomAnchorCrop = _currentCrop
            _targetCrop = _currentCrop
            zoomVelocity = 0
            velocitySize = .zero
            zoomLastTick = nil
            flags.hasZoomAdjustment = true
        }
    }

    func beginZoom(_ direction: OperatorCommand.ZoomDirection, to height: CGFloat,
                   visibleCrop: CropRect? = nil) {
        withLock {
            adoptVisibleSize(from: visibleCrop)
            flags.zoomDirection = direction
            let upper = min(1, 1 / zoomAspect)
            let lower = min(upper, max(0.001, _qualityFloor.minCropHeightFraction))
            zoomDestination = min(upper, max(lower, height))
            flags.isZoomLimited = height < lower || (direction == .pushIn && zoomDestination <= lower)
        }
    }

    /// A separate explicit Director path: one adjacent rung, paced in ladder
    /// steps per second over its actual visible/clamped log-height distance.
    /// Operator zoom retains its existing velocity and acceleration limits.
    @discardableResult
    func beginDirectorZoom(_ direction: OperatorCommand.ZoomDirection, to height: CGFloat,
                           maximumRate: Double, visibleCrop: CropRect) -> Bool {
        withLock {
            let aspect = visibleCrop.size.width / visibleCrop.size.height
            guard aspect.isFinite, aspect > 0, height.isFinite else { return false }
            let upper = min(1, 1 / aspect)
            let lower = min(upper, max(0.001, _qualityFloor.minCropHeightFraction))
            let destination = min(upper, max(lower, height))
            guard visibleCrop.size.height >= lower, visibleCrop.size.height <= upper,
                  let trajectory = DirectorShotMoveTrajectory(originHeight: Double(visibleCrop.size.height),
                      destinationHeight: Double(destination), maximumRate: maximumRate),
                  (direction == .pushIn ? destination < visibleCrop.size.height : destination > visibleCrop.size.height) else { return false }
            adoptVisibleSize(from: visibleCrop)
            flags.zoomDirection = direction
            zoomDestination = destination
            directorZoom = (trajectory, 0, aspect, _qualityFloor.minCropHeightFraction)
            flags.isZoomLimited = height < lower
            return true
        }
    }

    /// Stop at the visible size; a later push/pull starts a fresh shot move.
    func endZoom() {
        withLock {
            directorZoom = nil
            guard flags.zoomDirection != nil else { return }
            flags.zoomDirection = nil
            zoomDestination = zoomHeight ?? _currentCrop.size.height
            zoomVelocity = 0
        }
    }

    func clearZoomAdjustment() {
        withLock {
            directorZoom = nil
            zoomHeight = nil
            flags.zoomDirection = nil
            zoomVelocity = 0
            zoomLastTick = nil
            zoomAnchorCrop = nil
            flags.hasZoomAdjustment = false
            flags.isZoomLimited = false
        }
    }

    private func resized(_ crop: CropRect, height: CGFloat) -> CropRect {
        let size = CGSize(width: height * zoomAspect, height: height)
        var center = crop.center
        if _zoomUsesTopAnchor { center.y = crop.origin.y + crop.size.height - height / 2 }
        return CropRect(center: center, size: size).clamped()
    }

    func advanceZoom(now: TimeInterval, aspect: CGFloat) {
        withLock {
            deterministicPan = false
            if var move = directorZoom {
                // A geometry change retires this trajectory at its visible size.
                // It cannot silently turn a quality-floor update into a fast move.
                guard now.isFinite, now >= 0, aspect == move.aspect,
                      _qualityFloor.minCropHeightFraction == move.floor,
                      zoomLastTick.map({ now >= $0 }) ?? true else { endZoom(); return }
                let delta = min(0.1, max(0, now - (zoomLastTick ?? now)))
                zoomLastTick = now
                move.elapsed += delta
                let height = CGFloat(move.trajectory.height(at: move.elapsed))
                zoomHeight = height
                _currentCrop = resized(_currentCrop, height: height)
                _targetCrop = resized(zoomAnchorCrop ?? _targetCrop, height: height)
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
            let lower = min(upper, max(0.001, _qualityFloor.minCropHeightFraction))
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
            _currentCrop = resized(_currentCrop, height: height)
            _targetCrop = resized(zoomAnchorCrop ?? _targetCrop, height: height)
        }
    }

    // MARK: Pan

    /// Pan position is deterministic; size is advanced separately above.
    func placePan(center: CGPoint, baseSize: CGSize) {
        withLock {
            if zoomHeight == nil {
                let limited = baseSize.height <= _qualityFloor.minCropHeightFraction
                if flags.isZoomLimited != limited { flags.isZoomLimited = limited }
            }
            let size = zoomHeight.map { CGSize(width: $0 * zoomAspect, height: $0) } ?? baseSize
            let crop = CropRect(center: center, size: size).clampedToQualityFloor(_qualityFloor).clamped()
            _targetCrop = crop
            _currentCrop = crop
            velocityOrigin = .zero
            deterministicPan = true
        }
    }

    // MARK: Spring

    /// Advance the spring toward the target and return what a render needs.
    func tick(now: TimeInterval) -> Snapshot {
        withLock {
            updateInterpolation(now: now)
            return Snapshot(crop: _currentCrop, outputSize: _settings.outputSize,
                            smoothingFactor: effectiveSmoothing, highQuality: _settings.useHighQuality)
        }
    }

    private func updateInterpolation(now: TimeInterval) {
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

        let newX = spring(_currentCrop.origin.x, _targetCrop.origin.x, &velocityOrigin.x)
        let newY = spring(_currentCrop.origin.y, _targetCrop.origin.y, &velocityOrigin.y)
        if zoomHeight != nil {
            _currentCrop = CropRect(origin: CGPoint(x: newX, y: newY), size: _currentCrop.size).clamped()
            return
        }
        let newW = spring(_currentCrop.size.width, _targetCrop.size.width, &velocitySize.width)
        let newH = spring(_currentCrop.size.height, _targetCrop.size.height, &velocitySize.height)

        _currentCrop = CropRect(
            origin: CGPoint(x: newX, y: newY),
            size: CGSize(width: newW, height: newH)
        ).clampedToQualityFloor(_qualityFloor).clamped()

        // Check if we're close enough and moving slow enough to stop interpolating
        let distanceThreshold: CGFloat = 0.001
        let velocityThreshold: CGFloat = 0.005

        if abs(_currentCrop.origin.x - _targetCrop.origin.x) < distanceThreshold &&
           abs(_currentCrop.origin.y - _targetCrop.origin.y) < distanceThreshold &&
           abs(_currentCrop.size.width - _targetCrop.size.width) < distanceThreshold &&
           abs(_currentCrop.size.height - _targetCrop.size.height) < distanceThreshold &&
           abs(velocityOrigin.x) < velocityThreshold &&
           abs(velocityOrigin.y) < velocityThreshold &&
           abs(velocitySize.width) < velocityThreshold &&
           abs(velocitySize.height) < velocityThreshold {

            _currentCrop = _targetCrop
            velocityOrigin = .zero
            velocitySize = .zero
            flags.isInterpolating = false
            lastInterpolationTime = 0
        }
    }
}
