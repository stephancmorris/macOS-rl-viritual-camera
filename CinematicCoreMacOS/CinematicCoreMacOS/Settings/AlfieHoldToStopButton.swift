//
//  AlfieHoldToStopButton.swift
//  CinematicCoreMacOS
//
//  The on-screen Stop (owner decision D3; docs/ux/2026-11-05/stop.md). One
//  uninterrupted press of 0.8 s inside the control stops the session, once,
//  while a darker fill shows how long it has been held. A click or an early
//  release only says "Hold to stop". Keyboard activation (Space or Return
//  with Full Keyboard Access) and VoiceOver's Press open a confirmation
//  instead, so nobody has to hold a key. Session › Stop Session (⌘⌥⇧S)
//  stays the immediate menu action, with no hold.
//
//  Track A puts this in the pill and Track B in the Multi Cam header; each
//  passes the confirmation line for its frozen active route.
//

import AppKit
import SwiftUI

/// The hold-to-stop rules, apart from the view, so the timing can be tested
/// with an injected clock.
nonisolated struct HoldToStop: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// "Stop session".
        case resting
        /// "Keep holding to stop", since the given uptime.
        case holding(since: TimeInterval)
        /// "Hold to stop": after a click, an early release or a cancel.
        case needsHold
        /// "Stopping session…": Stop has been sent once.
        case stopping
        /// The lifecycle reported that Stop did not complete.
        case failed
    }

    static let duration: TimeInterval = 0.8
    /// Uptime arithmetic loses a few ulps; a hold of exactly 0.8 s counts.
    private static let slack: TimeInterval = 1e-6

    private(set) var phase: Phase = .resting

    static func label(for phase: Phase) -> String {
        switch phase {
        case .resting: return "Stop session"
        case .holding: return "Keep holding to stop"
        case .needsHold: return "Hold to stop"
        case .stopping: return "Stopping session…"
        case .failed: return "Try stopping again"
        }
    }

    /// Every label the control can show, so it can reserve the widest one.
    static let allLabels = ["Stop session", "Keep holding to stop", "Hold to stop",
                            "Stopping session…", "Try stopping again"]

    var label: String { Self.label(for: phase) }

    func progress(at now: TimeInterval) -> Double {
        guard case .holding(let since) = phase else { return phase == .stopping ? 1 : 0 }
        return min(max((now - since) / Self.duration, 0), 1)
    }

    /// The pointer went down inside the control.
    mutating func press(at now: TimeInterval) {
        guard phase != .stopping else { return }
        phase = .holding(since: now)
    }

    /// Advances an active hold. Returns true exactly once, when it completes.
    mutating func update(at now: TimeInterval) -> Bool {
        guard case .holding(let since) = phase, now - since >= Self.duration - Self.slack else { return false }
        phase = .stopping
        return true
    }

    /// The pointer came up. Completes a long enough hold; otherwise asks for
    /// a hold and clears the progress.
    mutating func release(at now: TimeInterval) -> Bool {
        if update(at: now) { return true }
        if case .holding = phase { phase = .needsHold }
        return false
    }

    /// The pointer left, Escape, the window lost focus or the gesture was
    /// cancelled. A fresh full hold is needed afterwards.
    mutating func cancel() {
        if case .holding = phase { phase = .needsHold }
    }

    /// A confirmed Stop from the keyboard or VoiceOver: one Stop, no hold.
    mutating func confirm() -> Bool {
        guard phase != .stopping else { return false }
        phase = .stopping
        return true
    }

    mutating func stopDidFail() {
        if phase == .stopping { phase = .failed }
    }

    mutating func reset() {
        phase = .resting
    }
}

struct AlfieHoldToStopButton: View {
    /// What stops, for the confirmation, from `stop.md`'s route table, e.g.
    /// "This stops the cameras and Program output to the ATEM."
    var confirmationMessage = "This stops the cameras and Program output."
    /// Set by the caller when the lifecycle reports that Stop did not
    /// complete; the control then offers "Try stopping again".
    var stopFailed = false
    /// Gallery only: draw a fixed phase and progress.
    var previewPhase: HoldToStop.Phase? = nil
    var previewProgress: Double = 0
    let onStop: () -> Void

    @State private var hold = HoldToStop()
    @State private var progress: Double = 0
    @State private var isTracking = false
    @State private var isConfirming = false
    @State private var size: CGSize = .zero
    @State private var ticker: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    @Environment(\.alfieForcedControlState) private var forced
    private let display = AlfieDisplay()

    private static let cornerRadius: CGFloat = 14

    var body: some View {
        let phase = previewPhase ?? hold.phase
        let rawProgress = previewPhase == nil ? progress : previewProgress
        // Reduce Motion: the fill moves in quarters rather than sweeping.
        let shownProgress = display.reduceMotion ? (rawProgress * 4).rounded(.down) / 4 : rawProgress
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        face(phase: phase)
            .background {
                ZStack(alignment: .leading) {
                    shape.fill(AlfieColor.programFill)
                    // The held part darkens from the leading edge; the label
                    // says what is happening, so colour is never the only cue.
                    Rectangle()
                        .fill(AlfieColor.control.programPressed)
                        .frame(width: size.width * shownProgress)
                }
                .clipShape(shape)
            }
            .overlay {
                if isFocused || forced == .focus {
                    RoundedRectangle(cornerRadius: Self.cornerRadius + 2 + display.focusRingWidth, style: .continuous)
                        .strokeBorder(AlfieColor.accentText, lineWidth: display.focusRingWidth)
                        .padding(-(2 + display.focusRingWidth))
                }
            }
            .contentShape(shape)
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .gesture(holdGesture)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.space, .return]) { _ in
                isConfirming = true
                return .handled
            }
            .onKeyPress(.escape) {
                guard case .holding = hold.phase else { return .ignored }
                cancelHold()
                return .handled
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                cancelHold()
            }
            .onChange(of: stopFailed) { _, failed in
                if failed {
                    hold.stopDidFail()
                    progress = 0
                    Self.announce("Could not stop the session. Try again.")
                }
            }
            .onDisappear {
                ticker?.cancel()
                hold.reset()
                progress = 0
            }
            .help("Hold for 0.8 seconds to stop this session.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stop session")
            .accessibilityHint("Opens a confirmation before stopping.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { isConfirming = true }
            .alert("Stop this session?", isPresented: $isConfirming) {
                Button("Keep running", role: .cancel) {
                    isFocused = true
                    Self.announce("Session kept running.")
                }
                .keyboardShortcut(.defaultAction)
                Button("Stop session", role: .destructive) {
                    if hold.confirm() { complete() }
                }
            } message: {
                Text(confirmationMessage)
            }
    }

    private func face(phase: HoldToStop.Phase) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AlfieColor.onFill)
                .frame(width: 9, height: 9)
            ZStack(alignment: .leading) {
                // Reserve the widest label so the pill doesn't move.
                ForEach(HoldToStop.allLabels, id: \.self) { label in
                    Text(label).hidden()
                }
                Text(HoldToStop.label(for: phase))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AlfieColor.onFill)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTracking {
                    isTracking = true
                    guard hold.phase != .stopping else { return }
                    hold.press(at: Self.now())
                    startTicker()
                } else if !CGRect(origin: .zero, size: size).contains(value.location) {
                    cancelHold()
                }
            }
            .onEnded { _ in
                isTracking = false
                ticker?.cancel()
                if hold.release(at: Self.now()) {
                    complete()
                } else if hold.phase != .stopping {
                    progress = 0
                }
            }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                let now = Self.now()
                if hold.update(at: now) {
                    complete()
                    return
                }
                guard case .holding = hold.phase else { return }
                progress = hold.progress(at: now)
            }
        }
    }

    private func cancelHold() {
        guard case .holding = hold.phase else { return }
        ticker?.cancel()
        hold.cancel()
        progress = 0
    }

    private func complete() {
        ticker?.cancel()
        progress = 1
        Self.announce("Stopping session.")
        onStop()
    }

    private static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private static func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
