//
//  WebcamCallOverlay.swift
//  CinematicCoreMacOS
//
//  Track A (UX J5, webcam.md): while a Webcam session is live, say whether
//  an app is using the Alfie camera stream, and show a one-time note on how
//  to pick Alfie in a meeting app. Stream activity only: it never names the
//  receiving app or claims the call is receiving frames.
//

import AppKit
import SwiftUI

/// webcam.md's live-state copy.
nonisolated enum WebcamUsageCopy {
    static let tip = "In Zoom, Meet or FaceTime, choose Alfie as your camera."
    static let tipDismissName = "Dismiss camera selection tip"

    struct Status: Equatable, Sendable {
        let text: String
        let help: String
        let spoken: String
        let symbol: String
    }

    static func status(for state: WebcamUsageState) -> Status {
        switch state {
        case .inUse:
            return Status(text: "Alfie camera · in use", help: "An app has started the Alfie camera stream.",
                          spoken: "Alfie camera is in use.", symbol: "video.fill")
        case .notInUse:
            return Status(text: "Alfie camera · not in use yet", help: tip,
                          spoken: "Alfie camera is not in use yet. Choose Alfie as the camera in your meeting app.",
                          symbol: "video.slash")
        case .unknown:
            return Status(text: "Alfie camera · use status unavailable",
                          help: "Check your meeting app to see whether Alfie is selected.",
                          spoken: "Alfie camera use status is unavailable. Check your meeting app.",
                          symbol: "questionmark.circle")
        }
    }

    /// What to announce when the state changes, once per change. The first
    /// unknown while the first read lands stays silent; known zero after use
    /// says the stream stopped, which isn't the meeting ending.
    static func announcement(from old: WebcamUsageState, to new: WebcamUsageState, hasBeenInUse: Bool) -> String? {
        guard old != new else { return nil }
        if new == .notInUse && hasBeenInUse { return "Alfie camera is no longer in use." }
        return status(for: new).spoken
    }
}

/// The one-time note: shown on live Webcam until "Got it" is pressed.
nonisolated enum WebcamTip {
    static let defaultsKey = "alfie.webcam.callTipDismissed"
}

struct WebcamCallOverlay: View {
    @ObservedObject var cameraManager: CameraManager
    @StateObject private var usage = WebcamUsageObserver()
    @AppStorage(WebcamTip.defaultsKey) private var tipDismissed = false
    @State private var hasBeenInUse = false

    private var isWebcam: Bool { cameraManager.shotComposer.config.cinematicFormat == .webcam }
    private var isLive: Bool { isWebcam && cameraManager.isRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLive {
                WebcamUsageChip(state: usage.state)
                if !tipDismissed {
                    WebcamTipCard { tipDismissed = true }
                        .onAppear { PillCommandAnnouncement.say(WebcamUsageCopy.tip) }
                }
            }
        }
        .onAppear(perform: updateMonitoring)
        .onChange(of: isLive) { _, _ in updateMonitoring() }
        // The observer starts at unknown, so its first change is the first
        // real reading; nothing is said before then.
        .onChange(of: usage.state) { old, new in
            if let text = WebcamUsageCopy.announcement(from: old, to: new, hasBeenInUse: hasBeenInUse) {
                PillCommandAnnouncement.say(text)
            }
            if new == .inUse { hasBeenInUse = true }
        }
        // Stop clears cached evidence at once; the view also leaves with the
        // live screen.
        .onDisappear { usage.setMonitoring(mode: .webcam, isLive: false) }
    }

    private func updateMonitoring() {
        if !isLive { hasBeenInUse = false }
        usage.setMonitoring(mode: isWebcam ? .webcam : .singleCam, isLive: cameraManager.isRunning)
    }
}

/// The worded state with its own shape, so colour is never the only cue.
struct WebcamUsageChip: View {
    let state: WebcamUsageState

    var body: some View {
        let status = WebcamUsageCopy.status(for: state)
        HStack(spacing: 7) {
            Image(systemName: status.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state == .inUse ? AlfieColor.onVideo.live : AlfieColor.onVideo.secondary)
                .accessibilityHidden(true)
            Text(status.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AlfieColor.onVideo.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(OperatorPillBackground(cornerRadius: 9))
        .help(status.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.spoken)
    }
}

struct WebcamTipCard: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "video.badge.checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AlfieColor.onVideo.emphasis)
                .accessibilityHidden(true)
            Text(WebcamUsageCopy.tip)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AlfieColor.onVideo.emphasis)
                .fixedSize(horizontal: false, vertical: true)
            Button("Got it", action: onDismiss)
                .alfieButtonStyle(.secondary, surface: .video, cornerRadius: 9)
                .accessibilityLabel(WebcamUsageCopy.tipDismissName)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 420, alignment: .leading)
        .background(OperatorPillBackground(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
