//
//  CameraManager.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/2/2026.
//

import AVFoundation
import CoreVideo
import CoreImage
import Combine
import IOSurface
import OSLog
import os

private final class SendablePixelBufferBox: @unchecked Sendable {
    nonisolated(unsafe) let pixelBuffer: CVPixelBuffer

    nonisolated init(_ pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

/// Carries the capture session to its channel's serial session executor.
/// AVCaptureSession's start/stop are documented as callable from any thread;
/// each channel only ever touches its session from one serial queue there.
private final class CaptureSessionBox: @unchecked Sendable {
    nonisolated(unsafe) let value: AVCaptureSession
    nonisolated init(_ value: AVCaptureSession) { self.value = value }
}

nonisolated final class CaptureFrameProcessingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeLease: UInt64?
    private var leaseSequence: UInt64 = 0
    private var droppedFrames: UInt64 = 0

    // Windowed throughput diagnostics. The delivered rate here is the ceiling on
    // what reaches the program output: if it sags below the show standard the
    // picture goes choppy. Logged once per second under the existing lock so it
    // stays thread-safe and cheap.
    private static let logger = Logger(subsystem: "com.alfie", category: "CaptureThroughput")
    private var windowStart: CFTimeInterval = CACurrentMediaTime()
    private var windowDelivered: UInt64 = 0
    private var windowDropped: UInt64 = 0

    init() {}

    func begin() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard activeLease == nil else {
            droppedFrames &+= 1
            windowDropped &+= 1
            logThroughputIfDueLocked()
            return nil
        }
        leaseSequence &+= 1
        activeLease = leaseSequence
        windowDelivered &+= 1
        logThroughputIfDueLocked()
        return leaseSequence
    }

    /// Caller must hold `lock`. Emits a delivered/dropped FPS summary once the
    /// current 1-second window closes, then opens a new window.
    private func logThroughputIfDueLocked() {
        let now = CACurrentMediaTime()
        let elapsed = now - windowStart
        guard elapsed >= 1.0 else { return }
        let deliveredFPS = Double(windowDelivered) / elapsed
        let droppedFPS = Double(windowDropped) / elapsed
        let total = windowDelivered + windowDropped
        let dropPercent = total > 0 ? Double(windowDropped) / Double(total) * 100.0 : 0
        let targetRate = ShowStandard.activeOrCurrent.frameRate
        Self.logger.notice(
            "Capture throughput: \(deliveredFPS, format: .fixed(precision: 1)) fps delivered to pipeline (target \(targetRate, format: .fixed(precision: 0))), dropped \(droppedFPS, format: .fixed(precision: 1)) fps (\(dropPercent, format: .fixed(precision: 1))% of frames)"
        )
        windowStart = now
        windowDelivered = 0
        windowDropped = 0
    }

    func isCurrent(_ lease: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeLease == lease
    }

    func finish(_ lease: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if activeLease == lease { activeLease = nil }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        activeLease = nil
        droppedFrames = 0
        windowStart = CACurrentMediaTime()
        windowDelivered = 0
        windowDropped = 0
    }

    var droppedFrameCount: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return droppedFrames
    }
}

enum CameraError: LocalizedError {
    case noCameraAvailable
    case sessionConfigurationFailed
    case unsupportedFormat
    case authorizationDenied
    case noValidationClipSelected
    case invalidValidationClip
    case validationClipPlaybackFailed(String)
    /// The selected camera belongs to another channel.
    case deviceInUse(ChannelID)
    /// The selected camera is not connected. Alfie does not substitute another.
    case deviceMissing
    /// No camera chosen for a channel that may not auto-select one.
    case noDeviceSelected

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return "No camera device found"
        case .sessionConfigurationFailed:
            return "Failed to configure capture session"
        case .unsupportedFormat:
            return "Camera has no capture format compatible with the selected show frame rate"
        case .authorizationDenied:
            return "Camera access denied"
        case .noValidationClipSelected:
            return "Choose a validation clip before starting clip playback"
        case .invalidValidationClip:
            return "The selected validation clip does not contain a readable video track"
        case .validationClipPlaybackFailed(let message):
            return "Validation clip playback failed: \(message)"
        case .deviceInUse(let owner):
            return "This camera is already used by \(owner.cameraLabel)"
        case .deviceMissing:
            return "The selected camera is not connected. Reconnect it or choose another camera."
        case .noDeviceSelected:
            return "Choose a camera for this input"
        }
    }
}

/// Manages the AVCaptureSession pipeline for 4K video capture
/// Ticket: APP-01 - AVCaptureSession Pipeline
@MainActor
final class CameraManager: NSObject, ObservableObject {
    private nonisolated static let logger = Logger(subsystem: "com.alfie", category: "Camera")
    private nonisolated static let signposter = OSSignposter(logger: logger)
    private nonisolated static let firstFrameLogged = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// One-shot log of the delivered pixel buffer dimensions. The activeFormat
    /// is set to 4K, but BMD's CMIO driver has been known to ignore that and
    /// serve 1080p — if this prints anything below 3840x2160 we're cropping a
    /// 1080p source, which would dwarf every other quality fix.
    private nonisolated static func logFirstFrameResolution(_ pixelBuffer: CVPixelBuffer) {
        let shouldLog = firstFrameLogged.withLock { logged -> Bool in
            guard !logged else { return false }
            logged = true
            return true
        }
        guard shouldLog else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        logger.notice("First frame delivered: \(width)x\(height), pixelFormat=\(format, format: .hex, privacy: .public)")
    }
    
    // MARK: - Published Properties
    
    /// Raw camera frame for the wide (left) operator pane, published as its
    /// backing `CVPixelBuffer` so the display path can be a zero-copy IOSurface
    /// layer assignment (see `PixelBufferPreviewView`). Retaining this property
    /// retains the buffer's IOSurface, which the capture side owns for its
    /// lifetime; that is what keeps it on screen safely.
    @Published private(set) var currentFrameBuffer: CVPixelBuffer?
    
    /// Capture session status
    @Published private(set) var isRunning: Bool = false
    
    /// Error state
    @Published private(set) var error: CameraError?
    
    /// Available camera devices  
    @Published private(set) var availableCameras: [CameraDevice] = []
    
    /// Currently selected camera
    @Published var selectedCamera: CameraDevice?

    /// Preferred frame source for the next session start.
    @Published var preferredInputSource: InputSource = .liveCamera

    /// Source currently driving the pipeline.
    @Published private(set) var activeInputSource: InputSource = .liveCamera

    /// Local validation clip selected for Gate 5 playback.
    @Published private(set) var validationClipURL: URL?

    /// When true, the validation clip repeats until the session is stopped.
    @Published var loopValidationClip: Bool = true

    /// Operator-facing summary of the current playback harness state.
    @Published private(set) var validationClipStatus: String = "Select a validation clip to route file playback through Alfie's camera pipeline."
    
    /// Person detector (Task 2.1)
    let personDetector = PersonDetector()
    
    /// Crop engine (Task 2.2 - GFX-01)
    let cropEngine: CropEngine?

    /// Shot composer (Task 2.3 - LOGIC-01)
    let shotComposer = ShotComposer()

    /// RL-trained CoreML agent (Task APP-02)
    let cinematicAgent = CinematicAgent()

    /// When true, the cinematic agent drives the crop instead of ShotComposer.
    @Published var useMLAgent: Bool = false {
        didSet {
            if useMLAgent {
                cinematicAgent.ensureModelLoaded()
            }

            if useMLAgent, cinematicAgent.isModelLoaded, let crop = cropEngine?.currentCrop {
                cinematicAgent.initialize(from: crop)
            }
        }
    }

    /// Training data recorder (Task 3.1 - RL-01)
    let trainingDataRecorder = TrainingDataRecorder()

    /// Routes the processed program feed to the currently active output sink.
    /// Program Display is a fullscreen clean feed on a selected display (e.g.
    /// for an HDMI→SDI converter into an ATEM).
    /// The show's single program output. Owned by ShowCoordinator and shared;
    /// a channel never creates its own. UI reads show-level output status here.
    let programOutput: ProgramOutputManager

    /// This channel's identity and its seam to the show: the routed channel's
    /// port is `programOutput` itself; any other channel's port is unrouted and
    /// cannot touch the output (see CameraChannel.swift).
    let channelID: ChannelID
    let outputPort: any ChannelOutputPort

    /// Discrete shot-intent revision (see ChannelFrame.swift). Increments on
    /// admitted shot-changing commands and lock-phase transitions; ordinary
    /// tracking motion does not change it.
    private(set) var shotRevision: UInt64 = 0
    private var lastShotPhase: RecoveryState.Phase = .inactive

    /// The most recent program frame this channel rendered, with the
    /// revisions it was made under. Plain storage (not published): written
    /// once per frame, read by routing / Take.
    private(set) var latestRenderedFrame: RenderedChannelFrame?

    /// Program frames this channel produced (new renders and repeats) since
    /// launch. Plain counter, sampled per diagnostics window by admission to
    /// measure a Preview channel whose telemetry is not in the show log.
    private(set) var renderedFrameCount: UInt64 = 0

    /// Capture rate configured on the device (nil before configuration or
    /// for a validation clip).
    private(set) var configuredCaptureFPS: Double?

    /// This channel's part of an admission fingerprint.
    var admissionInput: AdmissionFingerprint.Input {
        let mode: String
        switch activeMode {
        case .wide: mode = "wide"
        case .autoTracking: mode = "track"
        case .manualCrop: mode = "manual"
        case .autoPan: mode = "pan"
        }
        return AdmissionFingerprint.Input(
            channel: channelID.letter,
            deviceModelID: selectedCamera?.modelID,
            deliveredWidth: sourcePixelWidth > 0 ? sourcePixelWidth : nil,
            deliveredHeight: sourcePixelHeight > 0 ? sourcePixelHeight : nil,
            captureFPS: configuredCaptureFPS,
            captureProfile: shotComposer.config.cinematicFormat == .webcam ? "webcam" : "stage",
            mode: mode)
    }
    private(set) var repeatedFrameCount: UInt64 = 0

    // MARK: Device ownership (DEVICES)

    /// Show-owned leases. nil for a standalone single-camera manager (tests,
    /// previews), which keeps the historical auto-select behaviour.
    weak var deviceRegistry: CaptureDeviceRegistry?

    /// Show-owned fair admission for render and perception work (SCHEDULER).
    /// nil for a standalone manager, which renders as before.
    weak var workScheduler: FrameWorkScheduler?
    private(set) var deviceLease: CaptureDeviceRegistry.Lease?

    /// The claimed device disappeared mid-session. The generation is retired
    /// and frames stop (the router holds, then sends standby); recovery needs
    /// an explicit `reconnectSource()`. Changes rarely, so it is published.
    @Published private(set) var sourceMissing = false
    private var disconnectObserver: NSObjectProtocol?

    /// Per-channel serial executor for blocking session calls, so starting or
    /// stopping one camera never blocks the MainActor or the other channel.
    private let sessionQueue: DispatchQueue

    var revisions: ChannelRevisions {
        ChannelRevisions(sourceGeneration: captureGeneration,
                         controlEpoch: commands.epoch,
                         shotRevision: shotRevision)
    }

    /// Single-camera setup check (PREFLIGHT). Observes programOutput's closed
    /// diagnostics windows only; owned here so it outlives the inspector.
    let setupCheck = SetupCheck()

    /// Processed program frame for the program (right) operator pane, published
    /// as the crop pool's output `CVPixelBuffer`. Same zero-copy IOSurface
    /// display path as `currentFrameBuffer`. Retaining this property retains the
    /// pool surface so the CropEngine's `CVPixelBufferPool` will not re-vend it
    /// while it is still on screen (this codebase has been bitten by exactly
    /// that surface-recycling bug before).
    @Published private(set) var croppedFrameBuffer: CVPixelBuffer?



    /// Operation modes for crop control
    enum OperationMode {
        case wide
        case autoTracking
        case manualCrop
        case autoPan
    }

    /// Current operation mode for the crop engine
    @Published private(set) var activeMode: OperationMode = .wide

    /// Vertical pixel height of the most recent delivered source frame. Drives
    /// the operator-facing output-resolution readout. 0 until the first frame.
    @Published private(set) var sourcePixelHeight: Int = 0
    @Published private(set) var sourcePixelWidth: Int = 0

    /// What capture asked for, and what the driver actually delivered. The
    /// latter is authoritative for crop quality and may differ from the format.
    @Published private(set) var captureProfileStatus: String = "Starts with the next live session."

    /// Estimated resampling for the current crop, using delivered source pixels.
    /// This measures pixel geometry, not perceived sharpness or tracking quality.
    var framingCapability: FramingCapability? {
        guard sourcePixelWidth > 0, sourcePixelHeight > 0, let engine = cropEngine else { return nil }
        return FramingCapability.evaluate(
            sourceSize: CGSize(width: sourcePixelWidth, height: sourcePixelHeight),
            requestedCrop: lastGoodProgramCrop ?? engine.currentCrop,
            outputSize: engine.config.outputSize
        )
    }

    /// The center point for the manual crop (normalized 0-1)
    @Published var manualCropPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    // MARK: - Passive subject discovery
    //
    // Detection is off by default. The operator taps "Detect" to enter the
    // tap-a-subject state; tapping a point seeds a one-shot ROI scan that finds
    // and acquires that single person. No full-frame multi-person scan ever runs.

    /// True after the operator taps Detect and before a subject is selected.
    /// Drives the `.awaitingTap` detection mode and the preview tap affordance.
    @Published var detectionDiscoveryActive: Bool = false

    /// A tapped point (normalized Vision coords) awaiting its one-shot ROI scan
    /// on the next frame. Cleared once consumed.
    private var pendingTapPoint: CGPoint?

    /// True from the instant the operator taps until that tap has been resolved
    /// (a subject bound, or the scan found no one). Drives an immediate "tap
    /// pending" acknowledgment in the UI so the operator knows the tap landed
    /// even before acquisition begins.
    @Published private(set) var tapPending: Bool = false

    /// Wall-clock deadline after which an unfulfilled discovery auto-cancels
    /// back to `.off` so we don't sit in `.awaitingTap` forever.
    private var discoveryTimeoutAt: TimeInterval = 0
    private static let discoveryTimeout: TimeInterval = 12.0

    /// Padding multiplier applied to the locked subject's last box to form the
    /// tracking ROI, so a moving subject stays inside the scanned region.
    private static let lockedROIPadding: CGFloat = 1.8

    /// Last detected bounding box of the acquiring/locked subject. Updated
    /// every frame from detections and used to seed the next frame's ROI. This
    /// works even during `.acquiring` (before `currentTrackedBounds` is set by
    /// the composer) so ROI scanning stays tight throughout acquisition.
    private var lastSubjectROIBox: CGRect?

    // MARK: - Off-critical-path detection
    //
    // Detection used to be awaited inline, so every frame waited for Vision
    // before the crop could run. Measured 26 July: Vision 16.4 ms + ~17 ms of
    // crop/compose/output against a 20 ms budget at 50 Hz — the capture gate
    // then rejected 4 frames in 10 and the program feed ran at 30 fps.
    //
    // Detection now runs alongside the picture. Each frame composes from the
    // most recent completed detection (20–40 ms old at interval 2) and never
    // waits, so the frame path costs only the ~17 ms it always did.

    /// Most recent completed detection set. Read every frame; written only when
    /// a detection finishes.
    private let detectionFrames = DetectionFrameStore()
    /// TEST-ONLY: allows lifecycle tests to prove pre-Pan observations are retired.
    var detectionGenerationForTesting: UInt64 { detectionFrames.generation }

    /// One detection at a time. Without this, a pipeline that falls behind would
    /// queue detections faster than they complete and spawn unbounded work.
    private var detectionInFlight = false

    /// Bumped whenever a detection completes. Comparing against
    /// `consumedDetectionRevision` tells a frame whether its detections are new
    /// or a repeat of the previous frame's — which matters because several
    /// framing rules count *consecutive frames* and a repeat is not evidence.
    private var captureGeneration: UInt64 = 0

    /// Frame counter driving `DeveloperFlags.detectionFrameInterval`.
    private var detectionFrameCounter: UInt64 = 0

    /// Wall-clock of the last Core Image cache flush.
    private var lastImageCacheFlush: TimeInterval = 0

    /// Diagnostic A/B hook: drop both Core Image contexts' caches on a fixed
    /// schedule. NOT the memory fix — the autorelease drains and
    /// `cacheIntermediates: false` contexts are the fix (July 2026); this hook
    /// only exists so a soak can A/B the flush back in via
    /// `DeveloperFlags.imageCacheFlushInterval`. One cheap comparison per
    /// frame; the flush itself runs at most every `interval` seconds.
    private func flushImageCachesIfDue(now: TimeInterval) {
        let interval = DeveloperFlags.imageCacheFlushInterval
        guard interval > 0 else { return }
        guard lastImageCacheFlush > 0 else {
            lastImageCacheFlush = now
            return
        }
        guard now - lastImageCacheFlush >= interval else { return }
        lastImageCacheFlush = now
        cropEngine?.flushImageCaches()
        personDetector.flushImageCaches()
        // Marked in the diagnostics CSV so a flush can be lined up against the
        // heap and frame-rate columns when reviewing a session.
        outputPort.noteDiagnostics("image cache flush")
    }

    /// Start a detection if none is running and `due` says this frame holds a
    /// cadence slot. Slot accounting happens once per frame in `processFrame`
    /// (so the detection plan knows whether Vision will run); this function
    /// only re-checks and arms the work. Returns immediately either way — the
    /// caller never awaits.
    private func invalidateDetection(clearTracks: Bool = true) {
        detectionFrames.invalidate()
        personDetector.invalidatePendingWork(clearTracks: clearTracks)
        detectionFrameCounter = 0
        if clearTracks { lastSubjectROIBox = nil }
        // Leave detectionInFlight armed until the old job actually completes.
    }

    private func scheduleDetectionIfDue(
        pixelBuffer: CVPixelBuffer,
        sourceTimestamp: Double,
        plan: PersonDetector.DetectionRequestPlan,
        due: Bool
    ) {
        guard due, !detectionInFlight else { return }
        detectionInFlight = true
        let generation = detectionFrames.generation
        let id = detectionFrames.nextObservationID()
        let capturedAt = CACurrentMediaTime()
        let box = SendablePixelBufferBox(pixelBuffer)
        Task { [weak self] in
            guard let self else { return }
            defer { self.detectionInFlight = false }
            // The task may sit behind other MainActor work after it was
            // scheduled. Do not let it begin Vision under a newer
            // session/target generation and mutate the detector before the
            // frame store gets its post-work rejection chance.
            guard self.detectionFrames.generation == generation else { return }
            // Vision is admitted fairly across tracking channels. A superseded
            // or cancelled request skips this detection slot (latest-only).
            let scheduler = self.workScheduler
            var permit: FrameWorkScheduler.Permit?
            if let scheduler {
                guard let granted = await scheduler.acquire(.perception, for: self.channelID) else { return }
                permit = granted
            }
            defer { if let permit { scheduler?.release(permit) } }
            guard self.detectionFrames.generation == generation else { return }
            let persons = await self.personDetector.processFrame(box.pixelBuffer, plan: plan)
            let frame = DetectionFrame(observationID: id, capturedAt: capturedAt,
                sourceTimestamp: sourceTimestamp, pixelBuffer: box.pixelBuffer, persons: persons,
                queueWait: self.personDetector.stats.lastQueueWait,
                detectionDuration: self.personDetector.stats.lastDetectionTime)
            guard self.detectionFrames.publish(frame, generation: generation) else { return }
            self.outputPort.recordDetectionTiming(queueWait: frame.queueWait, visionWall: frame.detectionDuration)
            self.outputPort.recordLatency(stage: .detection, duration: frame.detectionDuration)
        }
    }

    /// Pure cadence rule: does the Nth eligible frame (every captured frame
    /// where no detection is in flight — counting starts at 1) carry a
    /// detection slot?
    ///
    /// REGRESSION NOTE (Aug 2026): an intermediate version of this gate tested
    /// `(counter + 1) % interval == 0` but only advanced the counter on frames
    /// that were already due. From counter 0 with interval 2 that predicate is
    /// false forever, scheduled detection dead-locked, and tracking froze on
    /// the single tap-time detection — the "tracking box doesn't move" bug.
    /// The rule below is the original, correct accounting: EVERY eligible
    /// frame advances the count; slots land on multiples of the interval. Unit
    /// tested in `DetectionCadenceTests`.
    nonisolated static func detectionSlotIsDue(eligibleFrameCount: UInt64, interval: Int) -> Bool {
        let interval = UInt64(max(1, interval))
        return eligibleFrameCount % interval == 0
    }

    // State for Auto Pan
    private var autoPanPhase: CGFloat = 0.5
    private var autoPanDirection: CGFloat = 1.0
    private var autoPanPauseUntil: Double = 0
    private var autoPanLastTick: Double = 0

    private static let autoPanPauseDuration: Double = 1.5

    // Briefly boost crop smoothing after an operator-driven shot-preset change
    // (and after a Steady Follow band exit) so the camera reaches the new
    // framing quickly instead of crawling there with the default
    // subject-tracking stiffness.
    private var fastFramingUntil: Double = 0
    private static let fastFramingDuration: Double = 0.5
    private static let fastFramingSmoothing: Float = 0.25

    /// Last frame's Steady Follow band, observed to detect band exit (the
    /// moment holding → following) and open the fast catch-up window.
    private var lastObservedSteadyBand: ShotComposer.SteadyBand?

    /// Call after changing `shotComposer.config.shotPreset` so the crop animates
    /// faster to the newly-chosen framing for the next ~0.5s.
    func boostFramingTransition() {
        fastFramingUntil = CACurrentMediaTime() + Self.fastFramingDuration
    }


    
    // MARK: - Camera Device Model
    
    struct CameraDevice: Identifiable, Hashable {
        let id: String
        let name: String
        let modelID: String
        let uniqueID: String
        let maxResolution: String
        let supports4K: Bool
        let formatCount: Int
        
        var displayName: String {
            "\(name) - \(maxResolution)"
        }
    }

    enum InputSource: String, CaseIterable, Identifiable {
        case liveCamera
        case validationClip

        var id: String { rawValue }

        var title: String {
            switch self {
            case .liveCamera:
                return "Live Camera"
            case .validationClip:
                return "Validation Clip"
            }
        }

        var systemImage: String {
            switch self {
            case .liveCamera:
                return "camera"
            case .validationClip:
                return "film.stack"
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoOutputQueue = DispatchQueue(
        label: "com.cinematiccore.videoOutput",
        qos: .userInteractive,
        // `.workItem` drains the autorelease pool after every job. Without it
        // the queue inherits its thread's pool, so objects created per frame
        // stay alive until the thread happens to be recycled — measured 26 July
        // as ~40 retained allocations per frame, released in irregular bulk
        // drops minutes apart, each drop restoring 50 fps instantly.
        autoreleaseFrequency: .workItem
    )
    private var cancellables = Set<AnyCancellable>()
    private var clipPlaybackTask: Task<Void, Never>?
    private nonisolated let frameProcessingGate = CaptureFrameProcessingGate()

    /// Last source pixel aspect (width/height) forwarded to the shot composer.
    /// Used to skip the per-frame update when aspect is unchanged.
    private var lastAppliedSourceAspect: CGFloat = 0

    /// Last delivered source pixel height used to set the crop quality floor.
    /// Skips the per-frame floor update when the resolution is unchanged.
    private var lastFloorSourceHeight: Int = 0

    private nonisolated func frameLog(_ message: @autoclosure () -> String) {
        guard DeveloperFlags.verboseFrameLogging else { return }
        let resolvedMessage = message()
        Self.logger.debug("\(resolvedMessage, privacy: .public)")
    }

    private nonisolated func latencyLog(_ message: @autoclosure () -> String) {
        guard DeveloperFlags.latencyConsoleLogging else { return }
        let resolved = message()
        Self.logger.notice("[LATENCY] \(resolved, privacy: .public)")
    }

    // MARK: - Configuration Constants
    
    private enum Config {
        static let targetWidth: Int32 = 3840
        static let targetHeight: Int32 = 2160
        // Capture format preference and the playout clock must come from the same
        // selection, so this reads the persisted show standard rather than a
        // constant. Defaults to 1080p50 (50.0) when nothing is persisted.
        static var targetFrameRate: Double { ShowStandard.activeOrCurrent.frameRate }
        static let pixelFormat = kCVPixelFormatType_32BGRA
    }
    
    // MARK: - Initialization
    
    /// Single-camera convenience: channel A, routed, with its own output.
    /// Used by tests and previews; the app builds channels via ShowCoordinator.
    override convenience init() {
        let output = ProgramOutputManager(sinks: [VirtualCameraOutputSink(), DisplayOutputSink()])
        self.init(channelID: .a, programOutput: output, outputPort: output)
    }

    /// - Parameters:
    ///   - programOutput: the show's single output, shared by every channel.
    ///   - routed: true for a channel feeding the output directly; false
    ///     channels get an unrouted port and cannot start, stop or send to it.
    convenience init(channelID: ChannelID, programOutput: ProgramOutputManager, routed: Bool) {
        self.init(channelID: channelID, programOutput: programOutput,
                  outputPort: routed ? programOutput : UnroutedChannelOutput(channelID: channelID))
    }

    /// Designated: the show (ShowCoordinator / ProgramRouter) supplies the port.
    init(channelID: ChannelID, programOutput: ProgramOutputManager, outputPort: any ChannelOutputPort) {
        self.channelID = channelID
        self.programOutput = programOutput
        self.outputPort = outputPort
        self.commands = CommandDispatcher(channelID: channelID)
        self.sessionQueue = DispatchQueue(label: "com.alfie.capture-session.\(channelID.letter)", qos: .userInitiated)
        // Initialize crop engine (Task 2.2 - GFX-01)
        self.cropEngine = CropEngine()
        
        super.init()
        
        if cropEngine == nil {
            Self.logger.warning("CropEngine failed to initialize - Metal may not be available")
        } else {
            Self.logger.notice("CropEngine initialized successfully")
        }

        // Restore the persisted cinematic format (Stage/Webcam) before wiring
        // bindings so the initial state matches the operator's last choice.
        if let raw = UserDefaults.standard.string(forKey: "cinematicFormat"),
           let fmt = ShotComposer.Config.CinematicFormat(rawValue: raw) {
            shotComposer.config.cinematicFormat = fmt
        }
        shotComposer.config.restoreStageHeadroom()

        configureFramingBindings()
        applyFrameProfile(shotComposer.config.frameProfile)

        // Discover cameras on initialization
        discoverCameras()
    }
    
    // MARK: - Public Methods
    
    /// Discover and list all available cameras
    func discoverCameras() {
        Self.logger.notice("Discovering cameras")
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        
        // TEMP Testing: Filter out Cameras for debugging
        let allDevices = discoverySession.devices
        let devices = allDevices.filter { device in
            !device.localizedName.lowercased().contains("Test")
        }
//        
//        print("   Found \(devices.count) camera(s) (excluding MacBook Pro for testing)")
//        if devices.count != allDevices.count {
//            print("   ⚠️ Filtered out: \(allDevices.count - devices.count) camera(s)")
//        }
        
        if devices.isEmpty {
            availableCameras = []
            return
        }
        
        var cameraDevices: [CameraDevice] = []
        
        for device in devices {
            // Get resolutions
            let resolutions = device.formats.map { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return (width: dims.width, height: dims.height)
            }
            
            // Check 4K support
            let supports4K = device.formats.contains { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dims.width == Config.targetWidth && dims.height == Config.targetHeight
            }
            
            // Get max resolution
            let maxRes = resolutions.max { res1, res2 in
                res1.width * res1.height < res2.width * res2.height
            }
            let maxResString = maxRes.map { "\($0.width)x\($0.height)" } ?? "Unknown"
            
            Self.logger.debug("Camera discovered: \(device.localizedName, privacy: .public) \(maxResString, privacy: .public)\(supports4K ? " (4K)" : "")")
            
            let cameraDevice = CameraDevice(
                id: device.uniqueID,
                name: device.localizedName,
                modelID: device.modelID,
                uniqueID: device.uniqueID,
                maxResolution: maxResString,
                supports4K: supports4K,
                formatCount: device.formats.count
            )
            cameraDevices.append(cameraDevice)
        }
        
        availableCameras = cameraDevices
        
        // Auto-select first 4K camera, or first available — channel A only.
        // Any other input needs an explicit camera choice (DEVICES).
        if selectedCamera == nil, channelID == .a {
            selectedCamera = cameraDevices.first { $0.supports4K } ?? cameraDevices.first
            if let selected = selectedCamera {
                Self.logger.notice("Selected camera: \(selected.name, privacy: .public)")
            }
        }
    }
    
    /// Request camera permissions and start the capture session
    let commands: CommandDispatcher
    @Published private(set) var controlStatus: String?
    @Published private(set) var isStartingSession = false
    @Published private(set) var isProgramHolding = false
    @Published private(set) var zoomMoveDirection: OperatorCommand.ZoomDirection?
    private var sessionStartTask: Task<Void, Never>?
    private var lastGoodProgramBuffer: CVPixelBuffer?
    private var lastGoodProgramCrop: CropEngine.CropRect?
    private var lastTrackingCrop: CropEngine.CropRect?
    private struct ShotMove {
        var origin: OperatorCommand.Preset
        var destination: OperatorCommand.Preset
        var originHeight: CGFloat
        var destinationHeight: CGFloat
        var direction: OperatorCommand.ZoomDirection
        var originIsUncropped = false
        var destinationIsUncropped = false
    }
    private var shotMove: ShotMove?

    var isZoomLimited: Bool {
        activeMode != .wide && (cropEngine?.isZoomLimited == true ||
            (activeMode == .autoTracking && cropEngine?.hasZoomAdjustment != true && shotComposer.isZoomLimitedByQuality))
    }
    var framingTitle: String {
        shotComposer.config.activeFramingTitle + (cropEngine?.hasZoomAdjustment == true ? " · Adjusted" : "")
    }
    private var selectedShot: OperatorCommand.Preset {
        shotComposer.config.cinematicFormat == .webcam ? .webcam(shotComposer.config.webcamPreset) : .stage(shotComposer.config.shotPreset)
    }
    private var shotLadder: [OperatorCommand.Preset] {
        shotComposer.config.cinematicFormat == .webcam ? [.webcam(.wide), .webcam(.tight)] :
            [.stage(.wide), .stage(.fullBody), .stage(.waistUp)]
    }
    func canBeginZoom(_ direction: OperatorCommand.ZoomDirection) -> Bool {
        if let move = shotMove { return direction != move.direction }
        if activeMode == .wide { return direction == .pushIn }
        guard let index = shotLadder.firstIndex(of: selectedShot) else { return false }
        return direction == .pushIn ? index < shotLadder.count - 1 : index > 0
    }
    private func fixedHeight(for preset: OperatorCommand.Preset) -> CGFloat {
        switch preset {
        case .stage(.wide), .webcam(.wide): return 1
        case .stage(.fullBody): return 0.8
        case .stage(.waistUp), .webcam(.tight): return 0.5
        }
    }
    private func choosePreset(_ preset: OperatorCommand.Preset) {
        switch preset {
        case .stage(let shot): shotComposer.config.shotPreset = shot
        case .webcam(let shot): shotComposer.config.webcamPreset = shot
        }
        shotComposer.reapplyFraming()
    }
    func selectPreset(_ preset: OperatorCommand.Preset) {
        cancelOperatorMotion()
        cropEngine?.clearZoomAdjustment()
        choosePreset(preset)
        boostFramingTransition()
    }

    /// A tap owns exactly one destination, not an unbounded held velocity.
    func beginZoom(_ direction: OperatorCommand.ZoomDirection) {
        guard canBeginZoom(direction), let engine = cropEngine else { return }
        let visible = lastGoodProgramCrop ?? engine.currentCrop
        let move: ShotMove
        if let prior = shotMove {
            move = ShotMove(origin: prior.destination, destination: prior.origin,
                            originHeight: prior.destinationHeight, destinationHeight: prior.originHeight,
                            direction: direction, originIsUncropped: prior.destinationIsUncropped,
                            destinationIsUncropped: prior.originIsUncropped)
        } else {
            let origin = selectedShot
            let ladder = shotLadder
            let index = ladder.firstIndex(of: origin) ?? 0
            let next = min(ladder.count - 1, max(0, index + (direction == .pushIn ? 1 : -1)))
            let destination = ladder[next]
            let height = activeMode == .autoTracking
                ? shotComposer.destinationHeight(for: destination) : fixedHeight(for: destination)
            // No known subject geometry: retain the shot rather than inventing a tracked crop.
            guard let height else { return }
            let originHeight = activeMode == .wide ? widestSafeCrop().size.height :
                (activeMode == .autoTracking ? shotComposer.destinationHeight(for: origin) : fixedHeight(for: origin))
            move = ShotMove(origin: origin, destination: destination,
                            originHeight: originHeight ?? visible.size.height, destinationHeight: height,
                            direction: direction, originIsUncropped: activeMode == .wide)
        }
        if activeMode == .wide {
            setOperationMode(.manualCrop)
        }
        if activeMode == .manualCrop { manualCropPoint = visible.center }
        shotMove = move
        zoomMoveDirection = direction
        engine.beginZoom(direction, to: move.destinationHeight, visibleCrop: visible)
    }

    func advanceShotMove(now: TimeInterval) {
        guard let engine = cropEngine else { return }
        engine.zoomUsesTopAnchor = activeMode == .autoTracking &&
            (shotComposer.config.cinematicFormat == .webcam || shotComposer.config.shotPreset == .waistUp)
        engine.advanceZoom(now: now, aspect: shotComposer.normalizedAspect)
        shotComposer.setVisibleZoomHeight(engine.adjustedHeight)
        if let move = shotMove, engine.zoomHasLanded {
            choosePreset(move.destination)
            if let anchor = lastTrackingCrop {
                lastTrackingCrop = .init(center: anchor.center, size: engine.currentCrop.size)
            }
            engine.clearZoomAdjustment()
            shotMove = nil
            zoomMoveDirection = nil
            // Reversing a move that began uncropped returns to that view,
            // never silently re-applying a selected crop on the next frame.
            if move.destinationIsUncropped { returnToWide() }
        }
    }

    func makeCommand(_ action: OperatorCommand.Action) -> OperatorCommand {
        let target: OperatorCommand.Target
        switch action { case .startSession, .stopSession: target = .session; default: target = .channel(channelID) }
        return .init(target: target, epoch: commands.epoch, expiry: CACurrentMediaTime() + 2, action: action)
    }

    @discardableResult
    func dispatch(_ command: OperatorCommand) -> CommandResult {
        if let reason = commands.rejection(for: command, now: CACurrentMediaTime()) { return .rejected(reason) }
        switch command.action {
        case .startSession, .stopSession: break
        default: guard isRunning else { return .rejected("Session is stopped") }
        }
        if case .beginZoom(let direction) = command.action {
            guard canBeginZoom(direction) else { return .rejected("Shot limit") }
            if activeMode == .autoTracking, shotComposer.destinationHeight(for: selectedShot) == nil {
                return .rejected("Waiting for subject framing")
            }
        }
        if case .setMode(.autoTracking) = command.action, manualLockedTargetID == nil { return .rejected("Select a subject first") }
        if case .resumeTracking = command.action, !recoveryState.canResume { return .rejected("Pick subject") }
        if activeMode == .autoPan || activeMode == .manualCrop {
            switch command.action {
            case .detect, .selectSubject:
                return .rejected("Switch to Crop or Wide before selecting a subject")
            default: break
            }
        }
        commands.accept(command)
        switch command.action {
        case .selectSubject, .unlock, .resumeTracking, .setMode, .selectPreset,
             .beginZoom, .moveManualCenter, .returnToWide:
            shotRevision &+= 1
        case .detect, .cancelDetect, .endZoom, .startSession, .stopSession:
            break
        }
        switch command.action {
        case .beginZoom: break
        default:
            cropEngine?.endZoom()
            shotMove = nil
            zoomMoveDirection = nil
        }
        controlStatus = nil
        switch command.action {
        case .detect: beginDetection()
        case .cancelDetect: cancelDetection()
        case .selectSubject(let point, let retarget):
            if retarget { retargetSubject(at: point) } else { selectSubject(at: point) }
        case .unlock: clearManualTargetLock()
        case .resumeTracking: resumeTracking()
        case .setMode(let mode): setOperationMode(mode)
        case .selectPreset(let preset): selectPreset(preset)
        case .beginZoom(let direction): beginZoom(direction)
        case .endZoom: break
        case .moveManualCenter(let point):
            manualCropPoint = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
        case .returnToWide: returnToWide()
        case .startSession:
            guard !isRunning, !isStartingSession else { return .completed }
            isStartingSession = true
            sessionStartTask = Task { [weak self] in
                guard let self else { return }
                defer { self.isStartingSession = false }
                do { try await self.startCapture() }
                catch is CancellationError { }
                catch { self.error = error as? CameraError; self.controlStatus = error.localizedDescription }
            }
        case .stopSession: stopCapture()
        }
        return .accepted
    }

    /// Drop UI gestures that have not been admitted yet (armed Detect, a tap
    /// waiting for its ROI scan). Called when the control target moves away
    /// from this channel. Already-admitted moves and running work continue.
    func cancelPendingOperatorGestures() {
        detectionDiscoveryActive = false
        pendingTapPoint = nil
        pendingTapIsRetarget = false
        tapPending = false
    }

    #if DEBUG
    /// Test seam: lets unit tests exercise command admission without a camera.
    func setRunningForTesting(_ running: Bool) { isRunning = running }
    /// Test seam: a rendered frame as if processFrame had produced it.
    func setLatestRenderedFrameForTesting(_ frame: RenderedChannelFrame?) { latestRenderedFrame = frame }
    /// Test seam: mark the source missing as a hot unplug would.
    func setSourceMissingForTesting(_ missing: Bool) { sourceMissing = missing }
    /// Test seam: the identity a configured source would have recorded.
    func setSourceIdentityForTesting(_ source: DiagnosticsSessionIdentity.Source) { recordSourceIdentity(source) }
    #endif

    /// This channel's source as last configured, kept even while it is not
    /// Program (the output port drops identity from non-Program channels).
    private(set) var sourceIdentity: DiagnosticsSessionIdentity.Source?

    private func recordSourceIdentity(_ source: DiagnosticsSessionIdentity.Source) {
        sourceIdentity = source
        outputPort.recordSourceIdentity(source)
    }

    /// Called when this channel becomes Program (Take): diagnostics from here
    /// on name this camera, not the one that was Program at capture start.
    func publishSourceIdentityToProgramOutput() {
        guard let sourceIdentity else { return }
        programOutput.recordSourceIdentity(sourceIdentity)
    }

    func cancelOperatorMotion() {
        commands.invalidateMotion()
        cropEngine?.endZoom()
        shotMove = nil
        zoomMoveDirection = nil
    }

    func setOperationMode(_ mode: OperationMode) {
        // Direct callers obey the same eligibility rule as dispatched commands.
        // Pan/Manual may preserve an old lock, but cannot invent one on exit.
        guard mode != .autoTracking || manualLockedTargetID != nil else { return }
        cancelOperatorMotion()
        if mode == .wide { returnToWide(); return }
        commands.setTrackingOwnership(mode == .autoTracking)
        if mode != .autoTracking { cancelDetection() }
        if mode == .autoPan || mode == .manualCrop {
            // Pending Vision and face-gallery jobs belong to the previous
            // tracking mode. The program now follows operator geometry only.
            personDetector.clearForInactiveMode()
            shotComposer.suspendIdentityWork()
            lastSubjectROIBox = nil
        }
        if mode == .manualCrop {
            let visible = lastGoodProgramCrop ?? cropEngine?.currentCrop
            if let visible { manualCropPoint = visible.center; cropEngine?.adoptVisibleSize(from: visible) }
        }
        if mode == .autoTracking { shotComposer.reapplyFraming() }
        if mode == .autoPan { autoPanLastTick = 0 }
        activeMode = mode
    }

    func applyLockOutcome(_ outcome: ShotComposer.TickOutcome) {
        guard commands.admitRecovery(outcome) else { return }
        cropEngine?.endZoom()
        shotMove = nil
        zoomMoveDirection = nil
        switch outcome {
        case .noChange: break
        case .pullBackToWide:
            cropEngine?.clearZoomAdjustment()
            shotComposer.setVisibleZoomHeight(nil)
            activeMode = .wide
            controlStatus = "Subject lost · widening"
            boostFramingTransition()
        case .resumeTracking, .acquired:
            activeMode = .autoTracking
            controlStatus = nil
            boostFramingTransition()
        }
    }

    func manualCropSize() -> CGSize {
        let aspect = shotComposer.normalizedAspect
        let height = min(1, 1 / aspect, cropEngine?.adjustedHeight ?? fixedHeight(for: selectedShot))
        return CGSize(width: height * aspect, height: height)
    }

    func advanceAutoPan(now: TimeInterval, width: CGFloat) -> CGFloat {
        let dt = autoPanLastTick > 0 ? min(0.1, max(0, now - autoPanLastTick)) : 0
        autoPanLastTick = now
        let width = min(1, max(0, width))
        let travel = 1 - width
        if travel > 0.0001, now > autoPanPauseUntil {
            autoPanPhase += CGFloat(shotComposer.config.autoPanSpeed) * 3 * autoPanDirection * CGFloat(dt)
            if autoPanPhase >= 1 {
                autoPanPhase = 1; autoPanDirection = -1; autoPanPauseUntil = now + Self.autoPanPauseDuration
            } else if autoPanPhase <= 0 {
                autoPanPhase = 0; autoPanDirection = 1; autoPanPauseUntil = now + Self.autoPanPauseDuration
            }
        }
        return width / 2 + autoPanPhase * travel
    }

    func selectProgramBuffer(rendered: CVPixelBuffer?, crop: CropEngine.CropRect? = nil) -> CVPixelBuffer? {
        if let rendered { lastGoodProgramBuffer = rendered; lastGoodProgramCrop = crop }
        if isProgramHolding != (rendered == nil) { isProgramHolding = rendered == nil }
        return lastGoodProgramBuffer
    }

    func renderProgramFrame(crop: CropEngine.CropRect, timestamp: Double,
                            render: () async throws -> CVPixelBuffer) async -> CVPixelBuffer? {
        let generation = captureGeneration
        let detectionGeneration = detectionFrames.generation
        let epoch = commands.epoch
        let running = isRunning
        let result: Result<CVPixelBuffer, Error>
        do { result = .success(try await render()) } catch { result = .failure(error) }
        guard generation == captureGeneration, detectionGeneration == detectionFrames.generation,
              epoch == commands.epoch, running == isRunning else { return nil }
        switch result {
        case .success(let buffer): return selectProgramBuffer(rendered: buffer, crop: crop)
        case .failure(let error):
            cancelOperatorMotion()
            outputPort.recordDroppedFrame(timestamp: timestamp, reason: "Crop processing failed: \(error.localizedDescription)", stage: .renderFailed)
            return selectProgramBuffer(rendered: nil)
        }
    }

    func startCapture() async throws {
        try Task.checkCancellation()
        cancelOperatorMotion()
        commands.setTrackingOwnership(false)
        lastGoodProgramBuffer = nil
        lastGoodProgramCrop = nil
        croppedFrameBuffer = nil
        isProgramHolding = false
        let sourceTitle = preferredInputSource.title
        Self.logger.notice("Starting capture from \(sourceTitle, privacy: .public)")
        captureGeneration &+= 1
        latestRenderedFrame = nil
        invalidateDetection()
        frameProcessingGate.reset()
        outputPort.start()
        sourcePixelWidth = 0
        sourcePixelHeight = 0
        captureProfileStatus = "Configuring capture…"

        if preferredInputSource == .validationClip {
            do {
                try await startValidationClipPlayback()
            } catch {
                outputPort.stop()
                throw error
            }
            return
        }
        
        // Check authorization
        let generation = captureGeneration
        let authorized = await checkAuthorization()
        try Task.checkCancellation()
        guard generation == captureGeneration else { throw CancellationError() }
        guard authorized else {
            Self.logger.error("Camera authorization denied")
            error = .authorizationDenied
            outputPort.stop()
            throw CameraError.authorizationDenied
        }
        Self.logger.notice("Camera authorized")
        
        // Refresh camera list if no camera selected
        if selectedCamera == nil {
            Self.logger.debug("No selected camera; rediscovering cameras")
            discoverCameras()
        }
        
        // Configure session
        Self.logger.notice("Configuring capture session")
        do {
            try await configureSession()
        } catch {
            releaseDevice()
            outputPort.stop()
            throw error
        }
        try Task.checkCancellation()
        guard generation == captureGeneration else { throw CancellationError() }
        Self.logger.notice("Capture session configured")
        
        // Start running on this channel's session executor: startRunning()
        // blocks, and must never block the MainActor or the other channel.
        let session = CaptureSessionBox(captureSession)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { @Sendable in
                session.value.startRunning()
                continuation.resume()
            }
        }
        // A Stop during startup retired this generation: the late start must
        // not revive it.
        guard generation == captureGeneration else {
            sessionQueue.async { @Sendable in session.value.stopRunning() }
            throw CancellationError()
        }
        do {
            // macOS has no .inputPriority preset, and the session's default
            // .high preset re-configures the device's activeFormat (4K →
            // 1080p) DURING startRunning(), silently discarding the format
            // configureCameraDevice() chose — verified empirically with the
            // Elgato 4K X. Re-asserting the format after start is the
            // supported macOS pattern; the session honors it while running.
            reassertConfiguredFormatIfNeeded()
            isRunning = captureSession.isRunning
            activeInputSource = .liveCamera
            if isRunning {
                Self.logger.notice("Capture started successfully")
                sourceMissing = false
                observeDisconnect()
                outputPort.updateCaptureStatus(isRunning: true)
            } else {
                Self.logger.warning("Session not running after startRunning()")
                releaseDevice()
                outputPort.stop()
            }
        }
    }
    
    /// Stop the capture session
    func stopCapture() {
        sessionStartTask?.cancel()
        sessionStartTask = nil
        isStartingSession = false
        cancelOperatorMotion()
        commands.setTrackingOwnership(false)
        cropEngine?.clearZoomAdjustment()
        lastTrackingCrop = nil
        lastGoodProgramBuffer = nil
        lastGoodProgramCrop = nil
        croppedFrameBuffer = nil
        isProgramHolding = false
        Self.logger.notice("Stopping capture")
        captureGeneration &+= 1
        latestRenderedFrame = nil
        invalidateDetection()
        cancelDetection()
        clipPlaybackTask?.cancel()
        clipPlaybackTask = nil
        frameProcessingGate.reset()
        if trainingDataRecorder.isRecording {
            Task { await trainingDataRecorder.stopRecording() }
        }
        outputPort.updateCaptureStatus(isRunning: false)
        workScheduler?.cancelWaiting(for: channelID)
        stopSessionAsync()
        stopObservingDisconnect()
        releaseDevice()
        sourceMissing = false
        configuredCaptureDevice = nil
        configuredCaptureFormat = nil
        configuredCaptureSize = nil
        outputPort.stop()
        isRunning = false
        activeInputSource = preferredInputSource
        activeMode = .wide
        shotComposer.reset(clearManualLock: true)
        cinematicAgent.reset()
        if validationClipURL != nil, preferredInputSource == .validationClip {
            validationClipStatus = "Validation clip stopped."
        }
        Self.logger.notice("Capture stopped")
    }

    /// Hold a wide safety shot while keeping the output path active.
    func returnToWide() {
        cancelOperatorMotion()
        commands.setTrackingOwnership(false)
        cropEngine?.clearZoomAdjustment()
        lastTrackingCrop = nil
        controlStatus = nil
        guard let cropEngine else { return }
        cancelDetection()
        invalidateDetection()

        activeMode = .wide
        shotComposer.reset(clearManualLock: true)
        cinematicAgent.reset()
        cropEngine.setTargetCrop(widestSafeCrop())
        cropEngine.jumpToTarget()
    }

    /// Crop target for "wide" as a *view*: the entire camera picture — truly
    /// uncropped — when the delivered source already matches the output shape
    /// (the common 16:9 rig). On an odd-shaped source it falls back to the
    /// largest undistorted output-aspect region, because stretching the
    /// program feed would be worse than a minimal crop. This is what
    /// Return to Wide shows; the Wide *preset* remains a capped crop
    /// (`FramingTuning.maximumCropHeight`) so the two stay distinct.
    private func widestSafeCrop() -> CropEngine.CropRect {
        let outputAspect = shotComposer.config.outputAspectRatio
        if lastAppliedSourceAspect > 0,
           abs(lastAppliedSourceAspect - outputAspect) < 0.01 {
            return .fullFrame
        }
        return .widest(aspect: shotComposer.normalizedAspect)
    }

    /// An explicit operator command may restore the retained lock's authority.
    func resumeTracking() {
        guard recoveryState.canResume else { return }
        if commands.trackingOwnsControl && activeMode == .autoTracking { return }
        let wasHolding = shotComposer.isHolding
        cancelOperatorMotion()
        commands.setTrackingOwnership(true)
        activeMode = .autoTracking
        if !wasHolding { cropEngine?.resetToFullFrame(aspect: shotComposer.normalizedAspect) }
        shotComposer.reset()
        cinematicAgent.reset()

        if useMLAgent, let crop = cropEngine?.currentCrop {
            cinematicAgent.initialize(from: crop)
        }
    }

    func lockTarget(personID: UUID) {
        cropEngine?.clearZoomAdjustment()
        lastTrackingCrop = nil
        invalidateDetection(clearTracks: false)
        // Selection made — leave discovery and begin acquisition. Cropping
        // stays wide until the gallery is ready (ShotComposer promotes
        // acquiring → tracking and we get the .acquired tick outcome).
        detectionDiscoveryActive = false
        pendingTapPoint = nil
        pendingTapIsRetarget = false
        tapPending = false
        shotComposer.lockTarget(personID)
    }

    /// Operator tapped the "Detect" button. Arm the tap-a-subject state.
    /// Arming works from idle, HOLD, and WIDE-WAITING — the states where the
    /// operator most needs to grab someone back. While a subject is actively
    /// tracked or mid-acquisition, selection goes through press-and-hold
    /// retarget on the preview instead, so an accidental click can't drop a
    /// healthy lock.
    func beginDetection() {
        guard activeMode != .autoPan && activeMode != .manualCrop else { return }
        if case .tracking = shotComposer.lockState { return }
        if case .acquiring = shotComposer.lockState { return }
        detectionDiscoveryActive = true
        pendingTapPoint = nil
        discoveryTimeoutAt = CACurrentMediaTime() + Self.discoveryTimeout
    }

    /// Cancel discovery and return to the passive (off) state.
    func cancelDetection() {
        invalidateDetection(clearTracks: false)
        detectionDiscoveryActive = false
        pendingTapPoint = nil
        pendingTapIsRetarget = false
        tapPending = false
    }

    /// True when a plain preview tap should acquire whoever is under the
    /// finger WITHOUT first pressing Detect: HOLD and WIDE-WAITING are the
    /// "I lost my green box" states (amber recovering / cyan idle after an
    /// acquire timeout), and a volunteer must be able to tap themselves to
    /// regain the lock in one gesture.
    var recoveryState: RecoveryState {
        let phase: RecoveryState.Phase
        let galleryReady: Bool
        switch shotComposer.lockState {
        case .inactive:
            phase = .inactive; galleryReady = false
        case .acquiring(_, let gallery, _):
            phase = .acquiring; galleryReady = gallery.isReady
        case .tracking(_, let gallery):
            phase = .tracking; galleryReady = gallery.isReady
        case .hold(_, let gallery, _):
            phase = .hold; galleryReady = gallery.isReady
        case .wideWaiting(let gallery):
            phase = .wideWaiting; galleryReady = gallery.isReady
        }
        return RecoveryState(phase: phase, galleryReady: galleryReady,
                             trackingOwnsControl: commands.trackingOwnsControl)
    }

    var canDirectlyReacquire: Bool { recoveryState.allowsDirectSelection }

    /// Operator tapped a point on the preview to pick a subject. Stored for a
    /// one-shot ROI scan on the next frame; the scan finds the single person
    /// at that point and starts acquisition. Accepted while discovery is
    /// armed (Detect flow) or while directly re-acquiring from HOLD /
    /// WIDE-WAITING.
    func selectSubject(at point: CGPoint) {
        guard activeMode != .autoPan && activeMode != .manualCrop else { return }
        guard detectionDiscoveryActive || canDirectlyReacquire else { return }
        commands.setTrackingOwnership(true)
        invalidateDetection(clearTracks: false)
        pendingTapPoint = point
        pendingTapIsRetarget = false
        tapPending = true
    }

    /// True while the pending tap is a re-target of an existing lock rather
    /// than a first-time selection. It changes what a miss means: a re-target
    /// that finds nobody must leave the current subject locked and on air,
    /// where a first selection falls back to discovery.
    private var pendingTapIsRetarget = false

    /// Operator pressed and held on the preview while a subject is already
    /// locked — switch to whoever is at that point.
    ///
    /// Reuses the ordinary one-shot ROI scan: `currentDetectionPlan()` gives a
    /// pending tap priority over the lock state, so the next frame scans around
    /// the held point exactly as a first selection would.
    func retargetSubject(at point: CGPoint) {
        guard activeMode != .autoPan && activeMode != .manualCrop else { return }
        guard shotComposer.manualLockedTargetID != nil else { return }
        commands.setTrackingOwnership(true)
        invalidateDetection(clearTracks: false)
        pendingTapPoint = point
        pendingTapIsRetarget = true
        tapPending = true
    }

    /// Smoothly release the operator's lock and zoom back out to a wide shot.
    /// Differs from `returnToWide()` which snaps — this animates so the
    /// operator gets a soft pull-back when tapping "unlock" on the lock pill.
    func clearManualTargetLock() {
        cancelOperatorMotion()
        commands.setTrackingOwnership(false)
        cropEngine?.clearZoomAdjustment()
        invalidateDetection()
        activeMode = .wide
        detectionDiscoveryActive = false
        pendingTapPoint = nil
        tapPending = false
        shotComposer.clearManualLock()
        boostFramingTransition()
    }

    /// Compute this frame's detection plan from the discovery flag + lock FSM.
    /// This is the single place that decides whether and where Vision runs.
    ///
    /// - Parameter detectionRunsThisFrame: whether the cadence gate will
    ///   actually run Vision this frame. Plan decisions that consume a
    ///   one-shot opportunity (the throttled gallery refresh scan) must only
    ///   fire when the answer is true, or the opportunity would burn on a
    ///   frame whose detection is skipped by `scheduleDetectionIfDue`.
    func currentDetectionPlan(detectionRunsThisFrame: Bool) -> PersonDetector.DetectionRequestPlan {
        // Pan and Manual are deterministic picture modes. A retained lock is
        // only eligibility for an explicit future Track command, not a reason
        // to keep scanning its last ROI or running identity recovery now.
        if activeMode == .autoPan || activeMode == .manualCrop { return .off }
        // A pending tap takes priority: scan a ROI around it to acquire.
        if let tap = pendingTapPoint {
            return PersonDetector.DetectionRequestPlan(
                mode: .acquiring,
                roi: tapROI(around: tap)
            )
        }

        switch shotComposer.lockState {
        case .acquiring:
            // Acquisition needs the FACE request to fill the gallery, so use
            // `.acquiring` mode (not `.lockedROI`, which drops face). Scan the
            // padded body box so the head is included even when the operator
            // tapped the torso.
            return PersonDetector.DetectionRequestPlan(
                mode: .acquiring,
                roi: lockedROI()
            )
        case .tracking:
            // Locked ROI scopes every request to the padded box and drops the
            // per-frame face request — a real latency/load win that stays the
            // default. The one exception is the throttled gallery refresh:
            // roughly once per capture spacing (0.4 s), the plan upgrades to
            // a face-including ROI scan so the gallery keeps adapting to new
            // head poses after lock. Without it the gallery stays frozen at
            // the 3 acquisition signatures and re-acquisition is stuck with
            // lectern-frontals only.
            if detectionRunsThisFrame,
               shotComposer.shouldRunGalleryRefreshScan() {
                return PersonDetector.DetectionRequestPlan(
                    mode: .acquiring,
                    roi: lockedROI()
                )
            }
            return PersonDetector.DetectionRequestPlan(
                mode: .lockedROI,
                roi: lockedROI()
            )
        case .hold, .wideWaiting:
            return PersonDetector.DetectionRequestPlan(mode: .reacquiring, roi: nil)
        case .inactive:
            return detectionDiscoveryActive
                ? PersonDetector.DetectionRequestPlan(mode: .awaitingTap, roi: nil)
                : .off
        }
    }

    /// ROI for the one-shot SELECTION scan around the operator's tap. The
    /// human-rectangles model needs to see most of a body to fire, so this is
    /// deliberately generous: a near-full-height vertical column centered on
    /// the tap's x. That reliably captures the whole standing/seated person
    /// (head included) while still excluding people to the left/right — which
    /// is what keeps the scan cheap in a crowd. Subsequent acquiring frames
    /// narrow to the detected body box via `lockedROI()`.
    private func tapROI(around point: CGPoint) -> CGRect {
        let halfW: CGFloat = 0.28   // ~56% of frame width, centered on the tap
        return CGRect(
            x: point.x - halfW,
            y: 0,
            width: halfW * 2,
            height: 1
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Padded ROI around the locked subject's last known box. Falls back to a
    /// generous centered region if no tracked bounds are available yet.
    private func lockedROI() -> CGRect {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        // Prefer the subject's last raw detected box (available during
        // acquiring too); fall back to the composer's tracked bounds.
        guard let box = lastSubjectROIBox ?? shotComposer.currentTrackedBounds,
              !box.isEmpty else {
            return unit
        }
        let p = Self.lockedROIPadding
        let w = min(box.width * p, 1)
        let hgt = min(box.height * p, 1)
        return CGRect(
            x: box.midX - w / 2, y: box.midY - hgt / 2,
            width: w, height: hgt
        ).intersection(unit)
    }

    /// Pick the detected person whose box contains the tapped point; if none
    /// contains it (the tap landed just off the body), fall back to the person
    /// whose box center is closest to the tap.
    private func personNearest(
        to point: CGPoint,
        in persons: [PersonDetector.DetectedPerson]
    ) -> PersonDetector.DetectedPerson? {
        if let hit = persons.first(where: { $0.boundingBox.contains(point) }) {
            return hit
        }
        return persons.min { a, b in
            let da = hypot(a.boundingBox.midX - point.x, a.boundingBox.midY - point.y)
            let db = hypot(b.boundingBox.midX - point.x, b.boundingBox.midY - point.y)
            return da < db
        }
    }
    
    /// Restart capture with a different camera
    func restartWithCamera(_ cameraDevice: CameraDevice) async throws {
        Self.logger.notice("Switching to camera: \(cameraDevice.name, privacy: .public)")
        
        // Stop current session
        let wasRunning = isRunning && activeInputSource == .liveCamera
        if wasRunning {
            Self.logger.debug("Stopping current session before camera switch")
            stopCapture()
            // Give the session time to fully stop
            try await Task.sleep(for: .milliseconds(500))
        }
        
        // Update selected camera
        selectedCamera = cameraDevice
        Self.logger.notice("Selected camera updated")
        
        // Start new session if it was running before
        if wasRunning {
            Self.logger.debug("Restarting capture after camera switch")
            try await startCapture()
        }
    }

    func setValidationClipURL(_ url: URL?) {
        validationClipURL = url
        if let url {
            validationClipStatus = "Ready to play \(url.lastPathComponent). Start Session to route it through the live pipeline."
        } else {
            validationClipStatus = "Select a validation clip to route file playback through Alfie's camera pipeline."
        }
    }

    var selectedValidationClipName: String {
        validationClipURL?.lastPathComponent ?? "No Clip Selected"
    }

    var shouldPreflightVirtualCameraInstallation: Bool {
        preferredInputSource == .liveCamera
    }
    
    // MARK: - Private Methods
    
    private func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureFramingBindings() {
        cropEngine?.$hasZoomAdjustment.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        cropEngine?.$isZoomLimited.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

        shotComposer.$config
            .map(\.frameProfile)
            .removeDuplicates()
            .sink { [weak self] profile in
                self?.applyFrameProfile(profile)
            }
            .store(in: &cancellables)

        // Webcam format hides Manual Crop / Auto Pan; if the operator is in one
        // of those modes when switching to Webcam, fall back to a valid mode.
        shotComposer.$config
            .map(\.cinematicFormat)
            .removeDuplicates()
            .sink { [weak self] format in
                guard let self else { return }
                if self.isRunning && self.activeInputSource == .liveCamera {
                    self.captureProfileStatus = "\(format == .webcam ? "Webcam" : "Stage") capture profile applies on the next session start."
                }
                if format == .webcam,
                   self.activeMode == .manualCrop || self.activeMode == .autoPan {
                    self.setOperationMode((self.manualLockedTargetID != nil) ? .autoTracking : .wide)
                }
            }
            .store(in: &cancellables)
    }

    private func applyFrameProfile(_ profile: ShotComposer.Config.FrameProfile) {
        guard let cropEngine else { return }

        let desiredSize: CGSize
        switch profile {
        case .livestream:
            desiredSize = CGSize(width: 1920, height: 1080)
        case .portrait:
            desiredSize = profile.defaultOutputSize
        }
        if cropEngine.config.outputSize != desiredSize {
            cropEngine.config.outputSize = desiredSize
        }
    }

    private func startValidationClipPlayback() async throws {
        guard let validationClipURL else {
            error = .noValidationClipSelected
            throw CameraError.noValidationClipSelected
        }

        if captureSession.isRunning {
            stopSessionAsync()
        }

        error = nil
        isRunning = true
        recordSourceIdentity(DiagnosticsSessionIdentity.Source(
            inputKind: "Validation clip",
            deviceName: validationClipURL.lastPathComponent,
            belowShowRate: false))
        activeInputSource = .validationClip
        activeMode = .wide
        shotComposer.reset(clearManualLock: true)
        cinematicAgent.reset()
        currentFrameBuffer = nil
        croppedFrameBuffer = nil
        validationClipStatus = "Preparing \(validationClipURL.lastPathComponent)…"
        outputPort.updateCaptureStatus(isRunning: true)

        clipPlaybackTask?.cancel()
        let playbackGeneration = captureGeneration
        clipPlaybackTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            do {
                repeat {
                    try await Self.playValidationClip(from: validationClipURL) { pixelBufferBox, timestampSeconds in
                        await self.processValidationFrame(
                            pixelBufferBox,
                            timestampSeconds: timestampSeconds,
                            generation: playbackGeneration
                        )
                    }

                    let shouldLoop = await self.loopValidationClip
                    if !shouldLoop || Task.isCancelled {
                        break
                    }

                    await self.updateValidationClipStatus(
                        "Looping \(validationClipURL.lastPathComponent)…"
                    )
                } while !Task.isCancelled

                await self.finishValidationClipPlayback(cancelled: Task.isCancelled, generation: playbackGeneration)
            } catch is CancellationError {
                await self.finishValidationClipPlayback(cancelled: true, generation: playbackGeneration)
            } catch {
                await self.handleValidationClipFailure(error, generation: playbackGeneration)
            }
        }
    }

    private func processFrame(pixelBuffer: CVPixelBuffer, timestampSeconds: Double) async {
        let sessionGeneration = captureGeneration
        guard isRunning else { return }
        // NOTE: a `CIImage(cvPixelBuffer:)` used to be built here and never
        // used — one wasted image object per frame on the exact path the memory
        // investigation is looking at. Removed so it cannot muddy attribution.
        let bufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let captureInterval = Self.signposter.beginInterval("captureFrame")
        let captureStart = CACurrentMediaTime()
        // Stamp the route generation now: if roles change while this frame
        // renders, the router refuses it on arrival.
        let frameRouteGeneration = outputPort.routeGeneration
        var mainActiveTime: TimeInterval = 0
        var mainSegmentStart = captureStart
        flushImageCachesIfDue(now: captureStart)

        outputPort.recordInputFrame(timestamp: timestampSeconds)

        // Publish the wide (left) pane's raw pixels *before* any processing so
        // the operator sees the live frame at the earliest possible instant,
        // rather than inheriting the full detection→compose→crop latency. This
        // is a zero-copy IOSurface handoff (see PixelBufferPreviewView), so it
        // costs a pointer assignment. Detection overlays are still published
        // post-detection below, so during fast motion the boxes may trail the
        // raw pixels by a frame — that is accepted for a monitoring pane. The
        // program (right) pane still publishes post-crop; it must show output.
        currentFrameBuffer = pixelBuffer

        if bufferHeight > 0 {
            let bufferAspect = bufferWidth / bufferHeight
            if abs(bufferAspect - lastAppliedSourceAspect) > 0.001 {
                lastAppliedSourceAspect = bufferAspect
                shotComposer.updateSourcePixelAspect(bufferAspect)
            }

            // Drive the crop quality floor from the *actual delivered*
            // resolution, not the advertised capture format — some drivers
            // (e.g. BMD CMIO) advertise 4K but deliver 1080p, which would
            // otherwise permit an unsafe 2× zoom. This single update covers
            // all crop modes (the floor is applied in CropEngine.setTargetCrop)
            // and corrects the ML agent's internal clamp to the same numbers.
            let sourceHeight = Int(bufferHeight)
            let sourceWidth = Int(bufferWidth)
            if sourceWidth != sourcePixelWidth || sourceHeight != sourcePixelHeight {
                sourcePixelWidth = sourceWidth
                sourcePixelHeight = sourceHeight
                sourceIdentity?.deliveredWidth = sourceWidth
                sourceIdentity?.deliveredHeight = sourceHeight
                outputPort.recordDeliveredDimensions(width: sourceWidth, height: sourceHeight)
                if activeInputSource == .liveCamera, let expected = configuredCaptureSize {
                    let requested = "\(expected.width)×\(expected.height)"
                    let actual = "\(sourceWidth)×\(sourceHeight)"
                    if sourceWidth == expected.width && sourceHeight == expected.height {
                        captureProfileStatus = "Delivered \(actual) at \(configuredCaptureRateLabel). \(configuredCaptureReason?.description ?? "")"
                    } else {
                        captureProfileStatus = "Driver delivered \(actual) after \(requested) was requested; crop quality follows delivered pixels."
                        Self.logger.warning("Capture delivery mismatch: requested \(requested, privacy: .public), delivered \(actual, privacy: .public)")
                    }
                }
            }
            if sourceHeight != lastFloorSourceHeight {
                lastFloorSourceHeight = sourceHeight
                let floor = CropEngine.QualityFloor.forSource(height: sourceHeight)
                cropEngine?.qualityFloor = floor
                // The composer needs the same number so it can floor the crop
                // at the top anchor instead of letting setTargetCrop's
                // center-preserving clamp re-expand tight presets symmetrically.
                shotComposer.qualityFloorHeightFraction = floor.minCropHeightFraction
                cinematicAgent.updateSourceResolution(
                    width: Int(bufferWidth),
                    height: sourceHeight
                )
            }
        }

        let detectionInterval = Self.signposter.beginInterval("detection")
        // Auto-cancel a stale discovery (operator tapped Detect but never
        // picked anyone) so we fall back to the passive off state.
        if detectionDiscoveryActive,
           pendingTapPoint == nil,
           !shotComposer.isManualLockActive,
           CACurrentMediaTime() > discoveryTimeoutAt {
            detectionDiscoveryActive = false
        }

        // Cadence accounting comes first: every frame with no detection in
        // flight advances the counter, and this frame holds a slot when the
        // new count hits a multiple of the interval (see
        // `detectionSlotIsDue` — the counter MUST advance on non-due frames
        // too, or the gate dead-locks and tracking freezes). Knowing `due`
        // before building the plan lets one-shot plan decisions (the throttled
        // gallery refresh scan) fire only on frames where Vision actually runs.
        var detectionDue = false
        if !detectionInFlight {
            detectionFrameCounter &+= 1
            detectionDue = Self.detectionSlotIsDue(
                eligibleFrameCount: detectionFrameCounter,
                interval: DeveloperFlags.detectionFrameInterval
            )
        }
        let detectionPlan = currentDetectionPlan(detectionRunsThisFrame: detectionDue)
        // The diagnostics CSV starts on the first processed frame, so runs with
        // detection off (Auto Pan, Manual, an unlocked wide shot) are recorded
        // too — PAN-HITCH compares exactly those against detection-on runs.
        // The first frame that runs Vision is marked with a `detection start`
        // note, so time under detection load can still be read from the CSV.
        if outputPort.diagnosticsFileName == nil {
            let bundle = Bundle.main
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let recordedFingerprint = bundle.object(forInfoDictionaryKey: "AlfieSourceFingerprint") as? String
            let fingerprint = recordedFingerprint.flatMap { $0.isEmpty ? nil : $0 } ?? "unrecorded"
            outputPort.beginDiagnosticsSessionIfNeeded(note:
                "capture start; app=\(version)(\(build)); source_fingerprint=\(fingerprint); input=\(activeInputSource.title); pixels=\(Int(bufferWidth))x\(Int(bufferHeight)); show_fps=\(ShowStandard.activeOrCurrent.frameRate); detection_interval=\(DeveloperFlags.detectionFrameInterval); smoothing=\(shotComposer.config.smoothingFactor); band=\(shotComposer.config.steadyBandWidth)")
        }
        if detectionPlan.runsVision {
            outputPort.noteDetectionStartIfNeeded()
        }
        // Hand the matcher the current operator lock so it can bind that track
        // first with a relaxed threshold (PersonDetector.swift assignTracks).
        personDetector.lockedTargetID = shotComposer.manualLockedTargetID

        if !detectionPlan.runsVision {
            // Release the retained source pixels immediately and reject any
            // scheduled detection that has not entered Vision yet. Without
            // this, an organic transition to off (for example discovery or
            // acquisition timeout) can leave the latest observation buffer
            // retained until the next explicit operator action.
            detectionFrames.invalidate()
            personDetector.clearForInactiveMode()
        } else if pendingTapPoint != nil {
            let generation = detectionFrames.generation
            let id = detectionFrames.nextObservationID()
            let capturedAt = CACurrentMediaTime()
            mainActiveTime += CACurrentMediaTime() - mainSegmentStart
            let persons = await personDetector.processFrame(pixelBuffer, plan: detectionPlan)
            mainSegmentStart = CACurrentMediaTime()
            guard generation == detectionFrames.generation, sessionGeneration == captureGeneration else {
                Self.signposter.endInterval("detection", detectionInterval)
                Self.signposter.endInterval("captureFrame", captureInterval)
                return
            }
            let frame = DetectionFrame(observationID: id, capturedAt: capturedAt,
                sourceTimestamp: timestampSeconds, pixelBuffer: pixelBuffer, persons: persons,
                queueWait: personDetector.stats.lastQueueWait, detectionDuration: personDetector.stats.lastDetectionTime)
            detectionFrames.publish(frame, generation: generation)
            outputPort.recordDetectionTiming(queueWait: frame.queueWait, visionWall: frame.detectionDuration)
            outputPort.recordLatency(stage: .detection, duration: frame.detectionDuration)
        } else {
            scheduleDetectionIfDue(pixelBuffer: pixelBuffer, sourceTimestamp: timestampSeconds,
                plan: detectionPlan, due: detectionDue)
        }
        let observation = detectionPlan.runsVision ? detectionFrames.consume(at: CACurrentMediaTime()) : (frame: nil, isFresh: false)
        let detectedPersons = observation.frame?.persons ?? []
        let detectionIsFresh = observation.isFresh

        // The pending tap drove exactly one ROI scan. Bind acquisition to the
        // detected person nearest the tap point. If nothing was found, keep
        // discovery armed so the operator can tap again.
        if let tap = pendingTapPoint {
            let wasRetarget = pendingTapIsRetarget
            pendingTapPoint = nil
            pendingTapIsRetarget = false
            tapPending = false
            if let picked = personNearest(to: tap, in: detectedPersons) {
                lockTarget(personID: picked.id)   // → .acquiring, leaves discovery
                lastSubjectROIBox = picked.boundingBox
                if wasRetarget {
                    outputPort.noteDiagnostics("operator re-targeted subject")
                }
            } else if !wasRetarget {
                // Scan found no one at the tap — re-arm discovery so the
                // operator can try again, and surface that nothing was found.
                detectionDiscoveryActive = true
                discoveryTimeoutAt = CACurrentMediaTime() + Self.discoveryTimeout
            }
            // A re-target that found nobody deliberately does nothing: the
            // current subject stays locked and on air. Dropping the shot
            // because the operator held on an empty patch of stage would be a
            // far worse outcome than the hold appearing to be ignored.
        }

        // Track the acquiring/locked subject's latest box to seed the next
        // frame's ROI. Cleared when no subject is being followed.
        // Only refresh the ROI seed from a real detection. On a repeat frame the
        // box is unchanged anyway, and the `nil` branch could otherwise clear a
        // valid seed using stale state.
        if detectionIsFresh {
            if let subjectID = shotComposer.manualLockedTargetID,
               let box = detectedPersons.first(where: { $0.id == subjectID })?.boundingBox {
                lastSubjectROIBox = box
            } else if shotComposer.manualLockedTargetID == nil {
                lastSubjectROIBox = nil
            }
        }
        Self.signposter.endInterval("detection", detectionInterval)
        if let observation = observation.frame {
            outputPort.recordObservationAge(CACurrentMediaTime() - observation.capturedAt)
        }

        let composeInterval = Self.signposter.beginInterval("compose")
        let composeStart = CACurrentMediaTime()

        // Advance the lock state machine. tracking → hold when the locked
        // subject goes missing, hold → wideWaiting after holdDuration. The
        // outcome tells us whether to apply a one-shot camera effect
        // (pull-back to wide on hold expiry; resume tracking on re-acq).
        // pixelBuffer is passed so the composer can capture face signatures
        // for re-acquisition.
        if activeMode != .autoPan && activeMode != .manualCrop {
            let lockOutcome = shotComposer.tick(
                detections: detectedPersons,
                timestamp: CACurrentMediaTime(),
                pixelBuffer: detectionIsFresh ? observation.frame?.pixelBuffer : nil,
                isFresh: detectionIsFresh,
                observationID: observation.frame?.observationID,
                observationTimestamp: observation.frame?.capturedAt
            )
            applyLockOutcome(lockOutcome)
        }

        // Steady Follow band exit: while holding, the composer emits no target
        // and the spring sits at rest. The instant the speaker leaves the band
        // (steadyBand clears while still tracking), give the catch-up the same
        // fast window preset changes get, so re-centering doesn't crawl at the
        // default stiffness. Gated on .tracking so lock loss (which also
        // clears the band on its way to hold/wide) doesn't log a misleading
        // "band exit" or open a boost window nothing will use. Entering the
        // band (nil → non-nil) needs no boost — the final centering target is
        // accepted right there and the camera is already essentially on it.
        if case .tracking = shotComposer.lockState,
           shotComposer.steadyBand == nil,
           lastObservedSteadyBand != nil {
            boostFramingTransition()
            outputPort.noteDiagnostics("steady band exit")
        }
        lastObservedSteadyBand = shotComposer.steadyBand

        let primaryPerson = activeMode != .autoTracking
            ? nil
            : shotComposer.primaryPerson(from: detectedPersons)

        func manualCropRect(center: CGPoint) -> CropEngine.CropRect {
            let size = manualCropSize()
            let originX = center.x - size.width / 2.0
            let originY = center.y - size.height / 2.0

            return CropEngine.CropRect(
                origin: CGPoint(x: originX, y: originY),
                size: size
            ).clamped()
        }

        var outputPixelBuffer: CVPixelBuffer?
        var composeDuration: TimeInterval = 0
        var cropDuration: TimeInterval = 0
        if let cropEngine {
            advanceShotMove(now: CACurrentMediaTime())
            switch activeMode {
            case .wide:
                    // Drive the spring toward the wide VIEW. Return to Wide
                    // snaps there via jumpToTarget(); entering .wide through a
                    // softer path (e.g. unlocking the subject) animates
                    // instead. Honour the framing-boost window so the pull-out
                    // arrives in ~0.5s rather than crawling.
                    let smoothing = CACurrentMediaTime() < fastFramingUntil
                        ? Self.fastFramingSmoothing
                        : shotComposer.config.smoothingFactor
                    cropEngine.config.transitionSmoothing = smoothing
                    cropEngine.setTargetCrop(widestSafeCrop())
                case .autoTracking:
                    if useMLAgent {
                        cropEngine.config.transitionSmoothing = 0.05
                        let newCrop = cinematicAgent.predict(
                            person: primaryPerson,
                            currentCrop: cropEngine.currentCrop
                        )
                        cropEngine.setTargetCrop(newCrop)
                    } else {
                        let smoothing = CACurrentMediaTime() < fastFramingUntil
                            ? Self.fastFramingSmoothing
                            : shotComposer.config.smoothingFactor
                        cropEngine.config.transitionSmoothing = smoothing
                        if let primaryPerson {
                            frameLog("🔍 DEBUG: Composing shot for person at \(primaryPerson.boundingBox)")
                            if let idealCrop = shotComposer.compose(
                                person: primaryPerson,
                                isFresh: detectionIsFresh,
                                observationTimestamp: observation.frame?.capturedAt
                            ) {
                                lastTrackingCrop = idealCrop
                                cropEngine.setTargetCrop(idealCrop)
                            }
                        } else {
                            if let lastTrackingCrop { cropEngine.setTargetCrop(lastTrackingCrop) }
                            frameLog("🔍 DEBUG: No persons detected, holding last position")
                        }
                    }
                case .manualCrop:
                    cropEngine.config.transitionSmoothing = shotComposer.config.smoothingFactor
                    let idealCrop = manualCropRect(center: manualCropPoint)
                    cropEngine.setTargetCrop(idealCrop)
                case .autoPan:
                    let size = manualCropSize()
                    let legal = CropEngine.CropRect(center: .init(x: 0.5, y: 0.5), size: size)
                        .clampedToQualityFloor(cropEngine.qualityFloor).clamped()
                    let centerX = advanceAutoPan(now: CACurrentMediaTime(), width: legal.size.width)
                    cropEngine.placePan(center: CGPoint(x: centerX, y: shotComposer.config.autoPanHeight), baseSize: size)
                }
            composeDuration = CACurrentMediaTime() - composeStart
            Self.signposter.endInterval("compose", composeInterval)
            outputPort.recordLatency(stage: .compose, duration: composeDuration)

            frameLog("🔍 DEBUG: About to call renderCrop...")
            let cropStart = CACurrentMediaTime()
            let snapshot = cropEngine.tickInterpolation()
            mainActiveTime += CACurrentMediaTime() - mainSegmentStart
            let scheduler = workScheduler
            let channel = channelID
            outputPixelBuffer = await renderProgramFrame(crop: snapshot.crop, timestamp: timestampSeconds) {
                // The render slot is shared across channels; wait for this
                // channel's fair turn (immediate with one camera).
                let permit = await scheduler?.acquire(.render, for: channel)
                defer { if let permit { scheduler?.release(permit) } }
                return try await cropEngine.renderCrop(pixelBuffer, crop: snapshot.crop, outputSize: snapshot.outputSize)
            }
            mainSegmentStart = CACurrentMediaTime()
            cropDuration = CACurrentMediaTime() - cropStart
            outputPort.recordLatency(stage: .cropRender, duration: cropDuration)
            cropEngine.publishRenderStats(renderTime: cropDuration)
            frameLog("🔍 DEBUG: Crop processing complete")
        } else {
            composeDuration = CACurrentMediaTime() - composeStart
            Self.signposter.endInterval("compose", composeInterval)
            outputPort.recordLatency(stage: .compose, duration: composeDuration)
        }

        // A retired render is dropped. A failed current render holds the last good program.
        guard sessionGeneration == captureGeneration, isRunning, let outputPixelBuffer else {
            Self.signposter.endInterval("captureFrame", captureInterval)
            return
        }

        // Only real detections are recorded. Logging repeats would teach the
        // agent that an identical observation can demand a different action.
        if trainingDataRecorder.isRecording, detectionIsFresh {
            trainingDataRecorder.recordFrame(
                timestamp: timestampSeconds,
                persons: detectedPersons,
                currentCrop: cropEngine?.currentCrop ?? .fullFrame,
                idealCrop: useMLAgent
                    ? cinematicAgent.lastPredictedCrop
                    : shotComposer.currentComputedCrop,
                isInterpolating: cropEngine?.isInterpolating ?? false
            )
        }

        // Publish the program (right) pane every frame. This is now a zero-copy
        // IOSurface layer assignment (PixelBufferPreviewView) rather than the
        // old per-render CIContext + full-frame createCGImage, so full-rate
        // (50 Hz) publishing is affordable on the MainActor — the earlier
        // half-rate gate (`previewPublishTick`) existed only to amortise that
        // expensive display path, which no longer exists. `outputPixelBuffer`
        // is the crop pool's output surface (every mode renders through
        // processCrop; failures hold the prior rendered surface);
        // holding it in the published property keeps the pool from re-vending it
        // while on screen. The wide pane was already published above, pre-crop.
        croppedFrameBuffer = outputPixelBuffer

        // Acquisition, hold, recovery and unlock transitions are discrete shot
        // changes: a frame rendered before one must not be taken after it.
        let phase = recoveryState.phase
        if phase != lastShotPhase {
            lastShotPhase = phase
            shotRevision &+= 1
        }
        renderedFrameCount &+= 1
        if isProgramHolding { repeatedFrameCount &+= 1 }
        latestRenderedFrame = RenderedChannelFrame(
            channelID: channelID,
            revisions: revisions,
            sourceTimestamp: timestampSeconds,
            processingStartedAt: captureStart,
            renderedAt: CACurrentMediaTime(),
            crop: lastGoodProgramCrop ?? cropEngine?.currentCrop ?? .fullFrame,
            outputSize: cropEngine?.config.outputSize ?? .zero,
            isRepeat: isProgramHolding,
            pixelBuffer: outputPixelBuffer)

        // isProgramHolding is set by selectProgramBuffer for this frame: true
        // means this send repeats the last good render (telemetry only).
        outputPort.submitFrame(outputPixelBuffer, timestamp: timestampSeconds, isRepeat: isProgramHolding,
                               routeGeneration: frameRouteGeneration)

        let detectionDuration = observation.frame?.detectionDuration ?? 0
        let totalDuration = CACurrentMediaTime() - captureStart
        mainActiveTime += CACurrentMediaTime() - mainSegmentStart
        outputPort.recordLatency(stage: .mainActor, duration: mainActiveTime)
        outputPort.recordLatency(stage: .total, duration: totalDuration)
        Self.signposter.endInterval("captureFrame", captureInterval)

        let gateDrops = frameProcessingGate.droppedFrameCount
        outputPort.recordGateDropTotal(gateDrops)
        outputPort.recordFramePathCounts(detectedPersons: detectedPersons.count)
        if let cropEngine {
            outputPort.recordPictureQuality(
                sourceHeight: Int(bufferHeight),
                cropHeightFraction: Double(cropEngine.currentCrop.size.height),
                outputHeight: Int(cropEngine.config.outputSize.height)
            )
        }
        latencyLog(
            "total=\(String(format: "%.1f", totalDuration * 1000))ms " +
            "detect=\(String(format: "%.1f", detectionDuration * 1000))ms " +
            "crop=\(String(format: "%.1f", cropDuration * 1000))ms " +
            "compose=\(String(format: "%.1f", composeDuration * 1000))ms " +
            "gateDrops=\(gateDrops)"
        )
    }

    private func processValidationFrame(
        _ pixelBufferBox: SendablePixelBufferBox,
        timestampSeconds: Double,
        generation: UInt64
    ) async {
        guard generation == captureGeneration else { return }
        await processFrame(
            pixelBuffer: pixelBufferBox.pixelBuffer,
            timestampSeconds: timestampSeconds
        )
    }

    private func updateValidationClipStatus(_ status: String) {
        validationClipStatus = status
    }

    private func handleValidationClipFailure(_ error: Error, generation: UInt64) {
        guard generation == captureGeneration else { return }
        Self.logger.error("Validation clip playback failed: \(error.localizedDescription, privacy: .public)")
        self.error = .validationClipPlaybackFailed(error.localizedDescription)
        validationClipStatus = "Playback failed: \(error.localizedDescription)"
        finishValidationClipPlayback(cancelled: false, generation: generation)
    }

    private func finishValidationClipPlayback(cancelled: Bool, generation: UInt64) {
        guard generation == captureGeneration else { return }
        invalidateDetection()
        guard activeInputSource == .validationClip || isRunning else { return }

        cancelOperatorMotion()
        commands.setTrackingOwnership(false)
        cropEngine?.clearZoomAdjustment()
        clipPlaybackTask = nil
        outputPort.updateCaptureStatus(isRunning: false)
        outputPort.stop()
        isRunning = false
        activeInputSource = preferredInputSource
        activeMode = .wide
        shotComposer.reset(clearManualLock: true)
        cinematicAgent.reset()

        if let validationClipURL {
            validationClipStatus = cancelled
                ? "Stopped \(validationClipURL.lastPathComponent)."
                : "Finished \(validationClipURL.lastPathComponent)."
        } else {
            validationClipStatus = cancelled
                ? "Validation clip stopped."
                : "Validation clip finished."
        }
    }

    nonisolated static func playbackDelay(sourceTimestamp: Double, firstTimestamp: Double,
        playbackStart: Double, now: Double) -> Double {
        max(0, playbackStart + max(0, sourceTimestamp - firstTimestamp) - now)
    }

    private nonisolated static func playValidationClip(
        from url: URL,
        onFrame: @escaping @Sendable (SendablePixelBufferBox, Double) async -> Void
    ) async throws {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw CameraError.invalidValidationClip
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw CameraError.validationClipPlaybackFailed("AVAssetReader could not attach the video output")
        }
        reader.add(output)

        guard reader.startReading() else {
            throw CameraError.validationClipPlaybackFailed(
                reader.error?.localizedDescription ?? "AVAssetReader failed to start"
            )
        }

        var firstTimestamp: Double?
        let playbackStart = CACurrentMediaTime()
        while !Task.isCancelled, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            if firstTimestamp == nil { firstTimestamp = timestampSeconds }
            let delay = Self.playbackDelay(sourceTimestamp: timestampSeconds,
                firstTimestamp: firstTimestamp!, playbackStart: playbackStart, now: CACurrentMediaTime())
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }

            let pixelBufferBox = SendablePixelBufferBox(pixelBuffer)
            await onFrame(pixelBufferBox, timestampSeconds)
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        if reader.status == .failed {
            throw CameraError.validationClipPlaybackFailed(
                reader.error?.localizedDescription ?? "AVAssetReader failed while reading"
            )
        }
    }
    
    private func configureSession() async throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        
        // Remove existing inputs and outputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        
        // Do NOT set a session preset. AVCaptureSessionPresetInputPriority is
        // iOS-only; the macOS equivalent is to leave the session at its default
        // (no preset), which lets configureCameraDevice() own the activeFormat
        // selection. A concrete preset like .high would reconfigure the device
        // to match the preset resolution, clobbering the manually chosen 4K format.
        
        // Find camera to use
        let camera: AVCaptureDevice
        if let registry = deviceRegistry {
            camera = try claimDevice(from: registry)
        } else {
            guard let found = findCameraToUse() else {
                error = .noCameraAvailable
                throw CameraError.noCameraAvailable
            }
            camera = found
        }

        // Add camera input
        let input = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(input) else {
            error = .sessionConfigurationFailed
            throw CameraError.sessionConfigurationFailed
        }
        captureSession.addInput(input)

        // Configure camera format AFTER attaching the input: with the device already
        // in the session and inside this begin/commitConfiguration transaction, the
        // format chosen here dictates the session's quality of service (macOS has no
        // .inputPriority preset), rather than being clobbered when the input is added.
        try configureCameraDevice(camera)
        
        // Configure video output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Config.pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoOutputQueue)
        
        guard captureSession.canAddOutput(output) else {
            error = .sessionConfigurationFailed
            throw CameraError.sessionConfigurationFailed
        }
        captureSession.addOutput(output)
        self.videoOutput = output
    }
    
    // MARK: Device leases and session executor (DEVICES)

    /// Resolve and exclusively claim this channel's device. Never substitutes
    /// another camera for a missing selection; only the single-camera first
    /// run (channel A, nothing chosen yet) may auto-select a free device.
    private func claimDevice(from registry: CaptureDeviceRegistry) throws -> AVCaptureDevice {
        let present = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified
        ).devices.sorted { hasAny4KFormat($0) && !hasAny4KFormat($1) }
        let resolution = CaptureDeviceRegistry.resolve(
            selected: selectedCamera?.uniqueID,
            present: present.map(\.uniqueID),
            owner: registry.owner(of:),
            channel: channelID,
            allowAutoSelect: channelID == .a)
        switch resolution {
        case .use(let uniqueID):
            switch registry.claim(uniqueID, for: channelID) {
            case .success(let lease):
                deviceLease = lease
                guard let device = present.first(where: { $0.uniqueID == uniqueID }) else {
                    throw CameraError.deviceMissing
                }
                return device
            case .failure(.inUse(let owner)):
                error = .deviceInUse(owner)
                throw CameraError.deviceInUse(owner)
            case .failure(.missing):
                error = .deviceMissing
                throw CameraError.deviceMissing
            }
        case .missing:
            error = .deviceMissing
            throw CameraError.deviceMissing
        case .inUse(let owner):
            error = .deviceInUse(owner)
            throw CameraError.deviceInUse(owner)
        case .noneSelected:
            error = .noDeviceSelected
            throw CameraError.noDeviceSelected
        }
    }

    private func releaseDevice() {
        if let lease = deviceLease { deviceRegistry?.release(lease) }
        deviceLease = nil
    }

    /// Stop the session on this channel's executor without blocking.
    private func stopSessionAsync() {
        let session = CaptureSessionBox(captureSession)
        sessionQueue.async { @Sendable in
            if session.value.isRunning { session.value.stopRunning() }
        }
    }

    private func observeDisconnect() {
        stopObservingDisconnect()
        guard let device = configuredCaptureDevice else { return }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSourceLost() }
        }
    }

    private func stopObservingDisconnect() {
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
        disconnectObserver = nil
    }

    /// The claimed device vanished (hot unplug). Retire the generation, stop
    /// the session and mark the source missing. The output keeps running: the
    /// router holds the last good frame, then sends standby. The lease is kept
    /// so no other channel can take the device when it returns, and nothing
    /// restarts until the operator asks (`reconnectSource()`).
    func handleSourceLost() {
        guard isRunning, activeInputSource == .liveCamera, !sourceMissing else { return }
        Self.logger.warning("Capture device disconnected on \(self.channelID.cameraLabel, privacy: .public)")
        captureGeneration &+= 1
        latestRenderedFrame = nil
        lastGoodProgramBuffer = nil
        lastGoodProgramCrop = nil
        cancelOperatorMotion()
        invalidateDetection()
        frameProcessingGate.reset()
        stopSessionAsync()
        sourceMissing = true
        outputPort.noteDiagnostics("\(channelID.cameraLabel) source missing")
    }

    /// Explicit Restart / Reclaim after a hot unplug: reconfigure the same
    /// claimed device under a new generation, without restarting the output.
    /// Stays missing (and throws) if the device is still absent.
    func reconnectSource() async throws {
        guard sourceMissing, let lease = deviceLease else { return }
        guard deviceRegistry?.isPresent(lease.uniqueID) ?? true else { throw CameraError.deviceMissing }
        captureGeneration &+= 1
        let generation = captureGeneration
        frameProcessingGate.reset()
        try await configureSession()
        guard generation == captureGeneration else { throw CancellationError() }
        let session = CaptureSessionBox(captureSession)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { @Sendable in
                session.value.startRunning()
                continuation.resume()
            }
        }
        guard generation == captureGeneration else {
            sessionQueue.async { @Sendable in session.value.stopRunning() }
            throw CancellationError()
        }
        reassertConfiguredFormatIfNeeded()
        if captureSession.isRunning {
            sourceMissing = false
            observeDisconnect()
            outputPort.noteDiagnostics("\(channelID.cameraLabel) source reconnected")
        }
    }

    private func findCameraToUse() -> AVCaptureDevice? {
        // Use selected camera if available
        if let selected = selectedCamera,
           let device = AVCaptureDevice(uniqueID: selected.uniqueID) {
            return device
        }
        
        // Otherwise auto-select
        return findBestCamera()
    }
    
    private func findBestCamera() -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        
        let devices = discoverySession.devices
        
        // Prefer 4K capable camera, then any available
        return devices.first(where: { hasAny4KFormat($0) }) ?? devices.first
    }
    
    private func hasAny4KFormat(_ device: AVCaptureDevice) -> Bool {
        device.formats.contains { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == Config.targetWidth && dimensions.height == Config.targetHeight
        }
    }
    
    /// Format explicitly chosen in configureCameraDevice(), re-asserted after
    /// startRunning() because the macOS .high session preset clobbers it
    /// (see reassertConfiguredFormatIfNeeded).
    private var configuredCaptureDevice: AVCaptureDevice?
    private var configuredCaptureFormat: AVCaptureDevice.Format?
    private var configuredCaptureSize: (width: Int, height: Int)?
    private var configuredCaptureReason: CaptureProfilePolicy.Reason?
    /// "1080p50", or "30 fps (show standard 1080p50)" for a Webcam fallback.
    private var configuredCaptureRateLabel = ShowStandard.activeOrCurrent.title
    private var configuredMinFrameDuration: CMTime?
    private var configuredMaxFrameDuration: CMTime?

    private func configureCameraDevice(_ device: AVCaptureDevice) throws {
        Self.logger.notice("Configuring device: \(device.localizedName, privacy: .public)")
        
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        let profile: CaptureProfilePolicy.Profile = shotComposer.config.cinematicFormat == .webcam ? .webcam : .stage
        let candidates = device.formats.map { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return CaptureProfilePolicy.Candidate(
                width: Int(dims.width), height: Int(dims.height),
                frameRateRanges: format.videoSupportedFrameRateRanges.map { $0.minFrameRate...$0.maxFrameRate }
            )
        }
        guard let selection = CaptureProfilePolicy.select(candidates, profile: profile, showRate: Config.targetFrameRate) else {
            error = .unsupportedFormat
            throw CameraError.unsupportedFormat
        }
        let format = device.formats[selection.index]
        
        device.activeFormat = format

        // DEBUG: Print supported frame rates
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        Self.logger.notice("Active format: \(dims.width)x\(dims.height)")

        // Remember the choice so startCapture() can re-assert it after
        // startRunning() — the .high session preset overwrites activeFormat
        // when the session starts (see reassertConfiguredFormatIfNeeded).
        configuredCaptureDevice = device
        configuredCaptureFormat = format
        configuredCaptureSize = (Int(dims.width), Int(dims.height))
        configuredCaptureReason = selection.reason
        configuredCaptureFPS = selection.frameRate
        // Webcam mode may run below the show rate (see CaptureProfilePolicy);
        // say the real capture rate rather than implying the show standard.
        configuredCaptureRateLabel = selection.reason == .webcamBelowShowRate
            ? String(format: "%g fps (show standard %@)", selection.frameRate, ShowStandard.activeOrCurrent.title)
            : ShowStandard.activeOrCurrent.title
        captureProfileStatus = "Requested \(dims.width)×\(dims.height) at \(configuredCaptureRateLabel): \(selection.reason.description). Waiting for delivered frame."
        recordSourceIdentity(DiagnosticsSessionIdentity.Source(
            inputKind: "Live camera",
            deviceName: device.localizedName,
            deviceModelID: device.modelID,
            captureProfile: profile == .webcam ? "webcam" : "stage",
            requestedWidth: Int(dims.width),
            requestedHeight: Int(dims.height),
            configuredCaptureFPS: selection.frameRate,
            captureSelectionReason: selection.reason.description,
            belowShowRate: selection.reason == .webcamBelowShowRate))

        if dims.height > 0 {
            let sourceAspect = CGFloat(dims.width) / CGFloat(dims.height)
            shotComposer.updateSourcePixelAspect(sourceAspect)
            lastAppliedSourceAspect = sourceAspect
            // First-guess clamp from the advertised format. processFrame()
            // overrides this with the *actual delivered* resolution on the
            // first frame (some drivers advertise 4K but deliver 1080p), which
            // is the authoritative source for both the agent clamp and the
            // CropEngine quality floor.
            cinematicAgent.updateSourceResolution(width: Int(dims.width), height: Int(dims.height))
        }

        Self.logger.debug("Supported frame rates follow")
        for range in format.videoSupportedFrameRateRanges {
            Self.logger.debug("\(range.minFrameRate, privacy: .public) to \(range.maxFrameRate, privacy: .public) fps")
        }
        
        // Set both limits to the selected rate's exact duration. Assigning a
        // range's endpoints (for example 30...60) only leaves a rate limit; it
        // does not configure 50/59.94/60 as the active capture cadence. The
        // selected rate is the show rate, except a Webcam-mode fallback.
        let captureRate = selection.frameRate
        guard let rateRange = format.videoSupportedFrameRateRanges.first(where: { range in
            range.minFrameRate <= captureRate && range.maxFrameRate >= captureRate
        }) else {
            Self.logger.error("No frame-rate range supports the selected \(captureRate, privacy: .public) fps capture rate")
            error = .unsupportedFormat
            throw CameraError.unsupportedFormat
        }
        Self.logger.notice("Using frame-rate range supporting \(captureRate, privacy: .public) fps (show standard \(Config.targetFrameRate, privacy: .public) fps)")
        let duration = ShowStandard.captureDuration(target: captureRate,
            minimum: rateRange.minFrameRate, maximum: rateRange.maxFrameRate)
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration

        configuredMinFrameDuration = device.activeVideoMinFrameDuration
        configuredMaxFrameDuration = device.activeVideoMaxFrameDuration
    }

    /// The .high session preset (macOS default; .inputPriority is iOS-only)
    /// re-configures the capture device's activeFormat during startRunning(),
    /// silently replacing the 4K format chosen in configureCameraDevice with
    /// 1080p. Verified empirically with the Elgato 4K X: activeFormat reads
    /// 3840×2160 after commitConfiguration and 1920×1080 immediately after
    /// startRunning. Re-asserting the stored format after start sticks — the
    /// session only performs its preset-driven reconfiguration at start time.
    private func reassertConfiguredFormatIfNeeded() {
        guard let device = configuredCaptureDevice,
              let format = configuredCaptureFormat,
              device.activeFormat != format else { return }
        let clobbered = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let wanted = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        Self.logger.warning(
            "Session preset clobbered activeFormat to \(clobbered.width)x\(clobbered.height); re-asserting \(wanted.width)x\(wanted.height)"
        )
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if let min = configuredMinFrameDuration { device.activeVideoMinFrameDuration = min }
            if let max = configuredMaxFrameDuration { device.activeVideoMaxFrameDuration = max }
            device.unlockForConfiguration()
        } catch {
            Self.logger.error("Failed to re-assert capture format: \(error.localizedDescription, privacy: .public)")
        }
    }
    
}

extension CameraManager {
    var manualLockedTargetID: UUID? {
        shotComposer.manualLockedTargetID
    }

    var isManualTargetLockActive: Bool {
        shotComposer.isManualLockActive
    }
}

@MainActor
final class VirtualCameraOutputSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .virtualCamera
    private static let logger = Logger(subsystem: "com.alfie", category: "VirtualCameraOutput")
    private static let signposter = OSSignposter(logger: logger)

    private let xpcManager = XPCConnectionManager()
    private(set) var lastFrameSendDuration: TimeInterval?
    private var hasLoggedFirstFrameSend = false
    /// Set once the current session's show standard has been pushed to the
    /// extension, so the drain clock matches what this sink is sending.
    private var playoutHandshake = PlayoutRateHandshake()

    /// The XPC message carries only an IOSurfaceID — nothing on the extension
    /// side retains the backing CVPixelBuffer for us. The extension's frame
    /// queue can hold a frame for one playout interval per queued entry (the
    /// drain clock runs at the show standard, e.g. 10 frames ≈ 200 ms at 50),
    /// while the CropEngine pool recycles a buffer as soon as the app drops
    /// its last reference (~one frame later). Retaining the most recent sends
    /// here keeps a surface alive until the extension has certainly consumed
    /// it; without this, the next render can overwrite a surface the extension
    /// is still reading (visible as tearing).
    private static let retainedFrameDepth = 10
    private var recentlySentBuffers: [CVPixelBuffer] = []
    var onStateChange: (() -> Void)? {
        didSet {
            xpcManager.onStateChange = onStateChange
        }
    }

    var isAvailable: Bool {
        if case .connected = xpcManager.connectionState {
            return true
        }
        return false
    }

    var summary: String {
        switch xpcManager.connectionState {
        case .connected:
            return "CMIO extension is connected and ready."
        case .connecting:
            return "Connecting to the CMIO extension."
        case .disconnected:
            return "Virtual camera route is idle."
        case .error:
            return "Virtual camera route hit a connection problem."
        }
    }

    var detail: String {
        switch xpcManager.connectionState {
        case .connected:
            return "Frames are being sent to the system extension over XPC."
        case .connecting:
            return "Waiting for the extension service to answer the connection check."
        case .disconnected:
            return "Start capture to connect the host app to the virtual camera extension."
        case .error(let message):
            return message
        }
    }

    var lastErrorDescription: String? {
        xpcManager.lastErrorDescription
    }

    /// The extension drains its queue at this rate — the host pushes
    /// `ShowStandard.activeOrCurrent.frameRate` over XPC whenever capture status
    /// changes and before the first frame, so both sides agree by construction.
    /// Reporting it here is what arms the HUD frame-rate-match check for the
    /// virtual-camera route (it used to read nil and never warn).
    var playoutFrameRate: Double? {
        ShowStandard.activeOrCurrent.frameRate
    }

    var canReconnect: Bool {
        xpcManager.canReconnect
    }

    var reconnectStatus: String? {
        xpcManager.reconnectStatusDescription
    }

    var bringUpChecks: [OutputBringUpCheck] {
        [
            OutputBringUpCheck(
                id: "virtual.xpc",
                title: "Virtual Camera · XPC Link",
                status: xpcStatusTitle,
                detail: xpcStatusDetail,
                level: xpcStatusLevel
            ),
            OutputBringUpCheck(
                id: "virtual.frames",
                title: "Virtual Camera · Frame Handoff",
                status: frameHandoffStatusTitle,
                detail: frameHandoffDetail,
                level: frameHandoffLevel
            )
        ]
    }

    func connect() {
        xpcManager.connect()
    }

    func disconnect() {
        xpcManager.disconnect()
        recentlySentBuffers.removeAll()
        playoutHandshake = PlayoutRateHandshake()
    }

    func reconnect() {
        xpcManager.forceReconnect()
    }

    func updateCaptureStatus(isRunning: Bool) {
        if isRunning {
            Self.logger.notice("Sending capture status RUNNING to virtual camera extension")
        } else {
            Self.logger.notice("Sending capture status STOPPED to virtual camera extension")
        }
        if isRunning {
            pushPlayoutRateIfNeeded()
        }
        xpcManager.remoteProxy()?.updateCaptureStatus(isRunning: isRunning)
    }

    /// Tell the extension to drain at the show standard. Idempotent per
    /// connection; re-pushed on every capture-status change so a reconnect
    /// always lands the current rate before frames flow. The show standard is
    /// applied at capture start, so this value matches what processFrame is
    /// producing for the whole session.
    @discardableResult
    private func pushPlayoutRateIfNeeded() -> Bool {
        guard case .connected = xpcManager.connectionState,
              let proxy = xpcManager.remoteProxy() else { return false }
        let rate = ShowStandard.activeOrCurrent.frameRate
        let generation = xpcManager.connectionGeneration
        if playoutHandshake.isReady(rate: rate, generation: generation) { return true }
        if playoutHandshake.begin(rate: rate, generation: generation) {
            proxy.updatePlayoutFrameRate(rate) { [weak self] accepted in
                Task { @MainActor in
                    guard let self else { return }
                    self.playoutHandshake.complete(rate: rate, generation: generation, accepted: accepted)
                    if !accepted { Self.logger.error("Extension rejected the requested show standard") }
                }
            }
        }
        return false
    }

    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        let sendInterval = Self.signposter.beginInterval("xpcSend")
        let sendStart = CACurrentMediaTime()
        guard pushPlayoutRateIfNeeded(),
              let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue(),
              let proxy = xpcManager.remoteProxy() else {
            lastFrameSendDuration = nil
            Self.signposter.endInterval("xpcSend", sendInterval)
            return false
        }

        proxy.sendVideoFrame(
            surfaceID: IOSurfaceGetID(ioSurface),
            timestamp: timestamp,
            width: Int32(CVPixelBufferGetWidth(pixelBuffer)),
            height: Int32(CVPixelBufferGetHeight(pixelBuffer))
        )
        recentlySentBuffers.append(pixelBuffer)
        if recentlySentBuffers.count > Self.retainedFrameDepth {
            recentlySentBuffers.removeFirst()
        }
        if !hasLoggedFirstFrameSend {
            hasLoggedFirstFrameSend = true
            Self.logger.notice(
                "First frame handed to virtual camera extension at \(timestamp, privacy: .public)s"
            )
        }
        lastFrameSendDuration = CACurrentMediaTime() - sendStart
        Self.signposter.endInterval("xpcSend", sendInterval)
        return true
    }

    private var xpcStatusTitle: String {
        switch xpcManager.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Error"
        }
    }

    private var xpcStatusDetail: String {
        switch xpcManager.connectionState {
        case .connected:
            return "Host app can reach the CMIO extension Mach service."
        case .connecting:
            return "Waiting for the extension service to answer the XPC ping."
        case .disconnected:
            return "The CMIO extension is not connected. Check that the system extension is installed and loaded."
        case .error(let message):
            return message
        }
    }

    private var xpcStatusLevel: OutputCheckLevel {
        switch xpcManager.connectionState {
        case .connected:
            return .ok
        case .connecting:
            return .info
        case .disconnected:
            return .warning
        case .error:
            return .error
        }
    }

    private var frameHandoffStatusTitle: String {
        if lastFrameSendDuration != nil {
            return "Sending"
        }
        if case .connected = xpcManager.connectionState {
            return "Connected"
        }
        return "Waiting"
    }

    private var frameHandoffDetail: String {
        if let lastFrameSendDuration {
            return String(
                format: "Frames are being handed to the extension over XPC. Last send: %.2f ms.",
                lastFrameSendDuration * 1000
            )
        }
        if case .connected = xpcManager.connectionState {
            return "XPC is connected, but no program frames have been handed off yet."
        }
        return "No frame handoff is possible until the XPC link is connected."
    }

    private var frameHandoffLevel: OutputCheckLevel {
        if lastFrameSendDuration != nil {
            return .ok
        }
        if case .connected = xpcManager.connectionState {
            return .info
        }
        return .warning
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Drain per frame: this delegate callback allocates a pixel-buffer
        // box and a sample-buffer read on every frame at 50 Hz, and those
        // must not sit waiting for the queue thread to be recycled.
        autoreleasepool {
            // Extract pixel buffer
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
        
            // Verify IOSurface backing (zero-copy requirement)
            guard CVPixelBufferGetIOSurface(pixelBuffer) != nil else {
                assertionFailure("PixelBuffer must be IOSurface-backed for zero-copy operations")
                return
            }

            Self.logFirstFrameResolution(pixelBuffer)

            let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

            // No per-drop logging here. Under overload this fires at frame rate on
            // the capture delegate queue, and the logging itself then contributes to
            // the overload. The gate already emits a delivered/dropped summary once
            // per second (`CaptureThroughput`), and the [SOAK] line carries the
            // running total.
            guard let frameLease = frameProcessingGate.begin() else { return }

            let sendableBuffer = SendablePixelBufferBox(pixelBuffer)

            // Soak diagnostic: how long the frame Task waits for the MainActor.
            // A growing hopLag with flat Vision wall time is the signature of
            // MainActor/SwiftUI accumulation (see the [SOAK] line).
            let enqueueTime = CACurrentMediaTime()

            Task(priority: .userInitiated) { @MainActor in
                defer { self.frameProcessingGate.finish(frameLease) }
                guard self.frameProcessingGate.isCurrent(frameLease) else { return }
                self.outputPort.recordMainActorHop(CACurrentMediaTime() - enqueueTime)
                await self.processFrame(
                    pixelBuffer: sendableBuffer.pixelBuffer,
                    timestampSeconds: timestampSeconds
                )
            }
        }
    }
    
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Performance monitoring: frame drops indicate system overload
        latencyLog("avcapture-drop (system overload upstream of processing gate)")
        let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        Task(priority: .userInitiated) { @MainActor in
            self.outputPort.recordDroppedFrame(
                timestamp: timestampSeconds,
                reason: "AVCapture dropped a frame before processing.",
                stage: .captureUpstream
            )
        }
    }
}
