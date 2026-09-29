//
//  LiveConsole.swift
//  CinematicCoreMacOS
//
//  Wires the Multiview console to the live engine (CONSOLE / TAKE-BAR /
//  NEXT-PANEL / INPUT-STRIP / PILL-TARGET integration). Shown in Stage format
//  while capture runs when DeveloperFlags.useMultiviewConsole is on.
//
//  - The console reads one ConsoleSnapshot, rebuilt from ShowCoordinator at
//    ≤15 Hz by a timer — never per frame.
//  - Pane pictures observe their channel directly and show its RENDERED
//    output (Preview) or the routed channel's output (Program); black while
//    the router is in standby. Source view (control-target pane only) shows
//    the wide source with the legal crop and detection boxes, and taps there
//    go through the show's control-target binding.
//  - Actions go through ShowCoordinator: Take, Edit Live, reconnect, Stop
//    show, adding / removing the second input and measuring the pair.
//

import AppKit
import Combine
import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore
import SwiftUI

// MARK: - Snapshot

enum LiveConsoleSnapshot {
    /// Build the console's snapshot from the live show. `rates` holds the
    /// measured delivered / rendered fps per channel.
    static func make(show: ShowCoordinator, paneView: ConsoleSnapshot.PaneView,
                     rates: [ChannelID: Double], note: String?) -> ConsoleSnapshot {
        let program = show.programChannel
        let preview = show.previewChannel
        let refused: Bool = { if case .refused = show.admissionDecision { return true } else { return false } }()

        let slots = ChannelID.allCases.map { id -> ConsoleSnapshot.Slot in
            guard let channel = show.channel(id) else { return ConsoleSnapshot.Slot(channel: id, input: nil) }
            let role: ConsoleSnapshot.Role = id == program ? .program : (id == preview ? .preview : .idle)
            let health: ConsoleSnapshot.SourceHealth
            if channel.sourceMissing || !channel.isRunning {
                health = .missing
            } else if refused, role == .preview {
                health = .unsupported
            } else {
                health = .running(deliveredRate: rates[id] ?? 0)
            }
            return ConsoleSnapshot.Slot(channel: id, input: .init(
                name: channel.selectedCamera?.name ?? "Camera \(id.letter)",
                shot: channel.framingTitle,
                role: role,
                health: health,
                legalCrop: topLeft(channel.cropEngine?.displayedCrop ?? .fullFrame)))
        }

        let output: ConsoleSnapshot.ProgramOutput
        if let programChannel = show.channel(program), programChannel.sourceMissing,
           show.router.state == .idle || show.router.state == .routed {
            output = .reconnecting
        } else {
            output = show.router.programStatus
        }

        return ConsoleSnapshot(
            slots: slots,
            programChannel: program,
            previewChannel: preview,
            programOutput: output,
            take: show.takeInputs() ?? .ready,
            editLive: show.editLive,
            showStandard: ShowStandard.activeOrCurrent,
            paneView: paneView,
            operatorNote: note)
    }

    /// Vision (bottom-left origin) crop → top-left origin for drawing.
    static func topLeft(_ crop: CropEngine.CropRect) -> CGRect {
        CGRect(x: crop.origin.x, y: 1 - crop.origin.y - crop.size.height,
               width: crop.size.width, height: crop.size.height)
    }
}

// MARK: - Model

final class LiveConsoleModel: ObservableObject, ConsoleActions {
    let show: ShowCoordinator

    @Published private(set) var snapshot: ConsoleSnapshot
    /// Latest operator-facing feedback (a refused Take, a failed start).
    @Published private(set) var message: String?
    @Published private(set) var pairCheckText: String?

    private(set) var paneView: ConsoleSnapshot.PaneView = .shot
    private var timer: Timer?
    private var lastCounts: [ChannelID: (count: UInt64, at: TimeInterval)] = [:]
    private var rates: [ChannelID: Double] = [:]
    private let pairCheck: MultiInputCheck
    private var pairCheckSubscription: AnyCancellable?
    /// Fingerprint key of the last configuration measured automatically, so
    /// a finished or cancelled check is not restarted for the same setup.
    private var autoMeasuredKey: String?

    static let refreshInterval: TimeInterval = 1.0 / 15.0

    init(show: ShowCoordinator, pairCheck: MultiInputCheck? = nil) {
        self.show = show
        self.pairCheck = pairCheck ?? MultiInputCheck()
        self.snapshot = LiveConsoleSnapshot.make(show: show, paneView: .shot, rates: [:], note: nil)
        pairCheckSubscription = self.pairCheck.$phase.sink { [weak self] phase in
            self?.pairCheckText = Self.describe(phase)
        }
    }

    // MARK: Refresh (≤15 Hz)

    func startRefreshing() {
        stopRefreshing()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        updateRates()
        measurePairIfUnmeasured()
        let target = show.channel(show.controlTarget)
        let failure = ChannelID.allCases.compactMap { show.channel($0)?.error?.localizedDescription }.first
        let next = LiveConsoleSnapshot.make(
            show: show, paneView: paneView, rates: rates,
            note: message ?? target?.controlStatus ?? failure)
        if next != snapshot { snapshot = next }
    }

    private func updateRates() {
        let now = CACurrentMediaTime()
        for id in ChannelID.allCases {
            guard let channel = show.channel(id) else { lastCounts[id] = nil; rates[id] = nil; continue }
            if id == show.programChannel {
                rates[id] = show.programOutput.measuredInputFPS
                continue
            }
            let count = channel.renderedFrameCount &- channel.repeatedFrameCount
            if let last = lastCounts[id], now - last.at >= 1 {
                rates[id] = Double(count &- last.count) / (now - last.at)
                lastCounts[id] = (count, now)
            } else if lastCounts[id] == nil {
                lastCounts[id] = (count, now)
            }
        }
    }

    // MARK: ConsoleActions

    func take() {
        switch show.take() {
        case .committed:
            message = nil
        case .rejected(let rejection):
            message = Self.describe(rejection, show: show)
        }
        refresh()
    }

    func setEditLive(_ enabled: Bool) {
        show.setEditLive(enabled)
        paneView = .shot
        refresh()
    }

    /// Two inputs: Preview is always the other channel (CUE is a follow-on).
    func cue(_ channel: ChannelID) {}

    func reconnect(_ id: ChannelID) {
        guard let channel = show.channel(id) else { return }
        Task { [weak self] in
            do { try await channel.reconnectSource() }
            catch { self?.message = error.localizedDescription }
            self?.refresh()
        }
    }

    func setPaneView(_ view: ConsoleSnapshot.PaneView) {
        paneView = view
        refresh()
    }

    // MARK: Show-level

    func stopShow() {
        pairCheck.cancel()
        show.stopShow()
    }

    /// Cameras that could become input B (not already used by A).
    var secondInputCandidates: [CameraManager.CameraDevice] {
        let used = show.channelA.selectedCamera?.uniqueID
        return show.channelA.availableCameras.filter { $0.uniqueID != used }
    }

    var hasSecondInput: Bool { show.channel(.b) != nil }

    func addSecondInput(_ device: CameraManager.CameraDevice) {
        let b = show.addChannel(.b)
        b.selectedCamera = device
        _ = b.dispatch(b.makeCommand(.startSession))
        message = nil
        refresh()
    }

    func removeSecondInput() {
        pairCheck.cancel()
        show.removeChannel(.b)
        refresh()
    }

    func measurePair() {
        guard let preview = show.previewChannel else { return }
        pairCheck.start(show: show, preview: preview) { [weak self] result in
            self?.show.recordAdmission(result)
            self?.refresh()
        }
    }

    /// SHOW-SETUP: an unmeasured pair is measured as soon as the Preview
    /// camera renders, once per configuration. A known result (provisional,
    /// certified or unsupported) is never re-measured automatically.
    private func measurePairIfUnmeasured() {
        guard let previewID = show.previewChannel, let preview = show.channel(previewID),
              preview.isRunning, !preview.sourceMissing, preview.latestRenderedFrame != nil,
              !pairCheck.phase.isRunning, show.admissionStatus == .unknown else { return }
        let key = show.admissionFingerprint().key
        guard key != autoMeasuredKey else { return }
        autoMeasuredKey = key
        measurePair()
    }

    var admissionTitle: String? {
        hasSecondInput ? show.admissionStatus.title : nil
    }

    // MARK: Copy

    static func describe(_ rejection: TakeRejection, show: ShowCoordinator) -> String {
        switch rejection {
        case .noPreview: return "No Preview camera"
        case .superseded: return "Take ignored: roles changed since the click"
        case .tooSoon: return "Take ignored: too soon after the last Take"
        case .outputRefused: return "The output did not accept the frame. Program is unchanged."
        case .notEligible:
            return TakeAvailability.evaluate(
                take: show.takeInputs() ?? .ready, program: show.programChannel,
                preview: show.previewChannel, standard: ShowStandard.activeOrCurrent,
                editLive: show.editLive).reasonText ?? "Preview is not ready"
        }
    }

    static func describe(_ phase: MultiInputCheck.Phase) -> String? {
        switch phase {
        case .idle: return nil
        case .warmingUp: return "Measuring pair · warming up"
        case .sampling(let collected, let needed): return "Measuring pair · \(collected) of \(needed)"
        case .finished(let result): return "Pair: \(result.status.title)"
        case .cancelled(let reason): return reason
        }
    }
}

// MARK: - Views

/// The live Multiview console. Owns the model; refreshes only while visible.
struct LiveMultiviewConsole: View {
    @StateObject private var model: LiveConsoleModel

    init(show: ShowCoordinator) {
        _model = StateObject(wrappedValue: LiveConsoleModel(show: show))
    }

    var body: some View {
        console
            .onAppear { model.startRefreshing() }
            .onDisappear { model.stopRefreshing() }
    }

    private var console: some View {
        let snapshot = model.snapshot
        var view = MultiviewConsoleView(snapshot: snapshot, actions: model) {
            InputStripView(snapshot: snapshot, actions: model,
                           tilePicture: { [model] id in LiveTilePicture.make(id: id, show: model.show) })
        } pill: {
            pill(for: snapshot)
        }
        view.panePicture = { [model] pane in AnyView(LivePanePicture.make(pane: pane, show: model.show)) }
        view.headerTrailing = AnyView(LiveConsoleHeader(model: model))
        return view
    }

    @ViewBuilder
    private func pill(for snapshot: ConsoleSnapshot) -> some View {
        let target = snapshot.controlTarget
        if let channel = model.show.channel(target.channel) {
            let pillTarget: ControlTarget = snapshot.previewChannel == nil
                ? .singleCamera
                : (target.role == .program ? .editingLive(channel: target.channel) : .preview(channel: target.channel))
            OperatorPill(cameraManager: channel, controlTarget: pillTarget, show: model.show)
                .id(target.channel)
        }
    }
}

/// A pane's live picture. Observes only its own channel.
struct LivePanePicture: View {
    @ObservedObject var channel: CameraManager
    let pane: PaneModel
    let show: ShowCoordinator

    @ViewBuilder
    static func make(pane: PaneModel, show: ShowCoordinator) -> some View {
        if pane.role == .program, let sent = heldProgramBuffer(show: show) {
            // Holding or standby: show exactly the frame downstream received.
            // It changes only on state changes, so the 15 Hz rebuild suffices.
            PixelBufferPreviewView(pixelBuffer: sent, aspectFill: true)
        } else if pane.role == .program, show.router.state == .standby {
            Color.black
        } else if let id = pane.channel, let channel = show.channel(id) {
            LivePanePicture(channel: channel, pane: pane, show: show)
        } else {
            Color.black
        }
    }

    /// While the router holds or is in standby the Program channel's own
    /// picture is not what was sent, so Program shows the router's last sent
    /// buffer (the held frame, or standby black). nil while routed: then the
    /// channel's rendered buffer is the one being sent, at full rate.
    static func heldProgramBuffer(show: ShowCoordinator) -> CVPixelBuffer? {
        switch show.router.state {
        case .holding, .standby: return show.router.lastSentBuffer
        case .idle, .routed: return nil
        }
    }

    var body: some View {
        if pane.paneView == .source {
            CameraPreviewView(
                pixelBuffer: channel.currentFrameBuffer,
                detectedPersons: channel.personDetector.displayedPersons,
                showDetections: true,
                activeTargetID: channel.shotComposer.activeTargetID,
                manualLockedTargetID: channel.manualLockedTargetID,
                acquiringTargetID: channel.shotComposer.acquiringTargetID,
                trackedSubjectRect: channel.shotComposer.displayedTrackedBounds,
                onTapPoint: tapHandler,
                onHoldPoint: holdHandler,
                cropIndicator: channel.activeMode != .wide ? channel.cropEngine?.displayedCrop : nil,
                isRecovering: channel.recoveryState.isRecovering,
                isZoomLimited: channel.isZoomLimited,
                framingTitle: channel.framingTitle,
                aspectFill: false)
        } else {
            // Rendered output only — never the raw capture buffer.
            PixelBufferPreviewView(pixelBuffer: channel.croppedFrameBuffer, aspectFill: true)
        }
    }

    /// Mirrors the single-camera tap rules, but every command is bound by
    /// the show to the control target (this pane) at the tap.
    private var tapHandler: ((CGPoint) -> Void)? {
        if channel.activeMode == .autoPan { return nil }
        if channel.detectionDiscoveryActive || channel.recoveryState.allowsDirectSelection {
            return { point in _ = show.dispatch(show.makeCommand(.selectSubject(point))) }
        }
        if channel.activeMode == .manualCrop {
            return { point in _ = show.dispatch(show.makeCommand(.moveManualCenter(point))) }
        }
        return nil
    }

    private var holdHandler: ((CGPoint) -> Void)? {
        guard channel.activeMode != .manualCrop, channel.activeMode != .autoPan,
              channel.manualLockedTargetID != nil else { return nil }
        return { point in _ = show.dispatch(show.makeCommand(.selectSubject(point, retarget: true))) }
    }
}

/// Show-level controls in the console header: second input, pair
/// measurement, feedback and Stop show.
struct LiveConsoleHeader: View {
    @ObservedObject var model: LiveConsoleModel

    var body: some View {
        HStack(spacing: 12) {
            if let text = model.pairCheckText ?? model.admissionTitle {
                Text(text)
                    .font(ConsoleStyle.label(10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            if model.hasSecondInput {
                Button("Measure pair") { model.measurePair() }
                    .controlSize(.small)
                Button("Remove Cam B") { model.removeSecondInput() }
                    .controlSize(.small)
            } else {
                Menu("Add Cam B") {
                    ForEach(model.secondInputCandidates) { device in
                        Button(device.name) { model.addSecondInput(device) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.secondInputCandidates.isEmpty)
            }
            Button("Stop show") { model.stopShow() }
                .controlSize(.small)
                .tint(ConsoleStyle.programRed)
        }
    }
}
