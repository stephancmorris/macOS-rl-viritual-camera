//
//  StoppedScreen.swift
//  CinematicCoreMacOS
//
//  Replaces the dual feed when a single-camera session (Single Cam or
//  Webcam) is stopped. Multi Cam shows Show setup instead. The mode picker
//  sits above Start, so the operator chooses the screen before starting.
//

import SwiftUI

struct StoppedScreen: View {
    /// Single Cam or Webcam, named above the title and picked above Start.
    @ObservedObject var operatorModes: OperatorModeStore
    /// What discovery sees; decides which modes the picker offers.
    let cameras: OperatorModeChoice.Cameras
    let lastSessionEndedAt: Date?
    var onStart: () -> Void
    /// SU-09: opens the show's run sheet. Nil where the Director doesn't run.
    var onEditRunSheet: (() -> Void)? = nil

    @ObservedObject var readiness: ReadinessObserver
    var lastSessionDuration: TimeInterval? = nil
    var lastSessionRoute: ProgramOutputManager.Route? = nil
    var requestingPermission = false
    var showsRefusal = false
    var focusRequest = 0
    var actionError: String? = nil
    var isStarting = false
    var onReadinessAction: (ReadinessModel.Action) -> Void
    @ObservedObject var preview: StoppedCameraPreviewController
    var canPreview = true
    var onPreview: () -> Void
    @State private var initialFocusRequest = 0
    @FocusState private var startFocused: Bool
    @AccessibilityFocusState private var startSpoken: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("\(operatorModes.mode.title) · Session stopped")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AlfieColor.tertiaryText)

                Text("Alfie is standing by.")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AlfieColor.text)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AlfieColor.tertiaryText)
                    .multilineTextAlignment(.center)

                OperatorModePicker(store: operatorModes, cameras: cameras, style: .stoppedScreen)
                    .padding(.top, 4)

                ReadinessChecklistView(readiness: readiness.readiness, inputs: readiness.inputs,
                    requestingPermission: requestingPermission, showsRefusal: showsRefusal, showsRefusalText: false,
                    focusRequest: focusRequest + initialFocusRequest, actionError: actionError, onAction: onReadinessAction)

                if canPreview {
                    Button(action: onPreview) {
                        Text(preview.isPreviewing ? "Turn previews off" : "Preview cameras")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .alfieButtonStyle(.secondary)
                    .disabled(preview.isChanging || isStarting)
                    .alfieUnavailableReason(preview.isChanging ? "Updating camera previews…" : isStarting ? "The session is starting." : nil)
                    .help("Turns on the selected cameras so you can check their pictures. Program output stays off.")
                    .accessibilityHint("Turns on the selected cameras so you can check their pictures. Program output stays off.")
                    if preview.isChanging {
                        Text("Updating camera previews…").font(.system(size: 12)).foregroundStyle(AlfieColor.secondaryText)
                    }
                    if preview.isPreviewing {
                        StoppedCameraPreview(session: preview.session).frame(width: 320, height: 180)
                            .accessibilityLabel("Camera preview. Program output is off.")
                    }
                    if let error = preview.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(AlfieColor.secondaryText)
                    }
                }

                Button(action: onStart) {
                    Text(isStarting ? "Starting session…" : "Start session")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                }
                .alfieButtonStyle(.primary, cornerRadius: 12)
                .disabled(isStarting)
                .alfieUnavailableReason(isStarting ? "The session is starting." : nil)
                .focused($startFocused)
                .accessibilityFocused($startSpoken)
                .padding(.top, 6)

                if showsRefusal, let row = readiness.readiness.blockingRow {
                    Text("Not ready to start. \(ReadinessRowPresentation(row: row, inputs: readiness.inputs, requestingPermission: requestingPermission).blockingInstruction)")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(AlfieColor.secondaryText)
                        .accessibilityIdentifier("readiness.refusal")
                }
                if isStarting {
                    Text("The session is starting.").font(.system(size: 12)).foregroundStyle(AlfieColor.secondaryText)
                }

                if let onEditRunSheet {
                    Button(action: onEditRunSheet) {
                        Text("Run sheet…")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .alfieButtonStyle(.quiet, cornerRadius: 6)
                    .help("Optional. Plan the show's segments; each uses its feel from Settings › Director.")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(40)
            .onAppear {
                if readiness.readiness.canStart { focusStart() }
                else { initialFocusRequest += 1 }
            }
            .onChange(of: readiness.readiness.canStart) { wasReady, ready in
                if ready { focusStart(); OperatorAnnouncement.say("Ready to start.") }
                else if wasReady, let row = readiness.readiness.blockingRow {
                    let title = row.id == .virtualCamera ? "Alfie camera" : row.id.title
                    OperatorAnnouncement.say("Setup needs attention. \(title).")
                }
            }
        }
    }

    private func focusStart() { startFocused = true; startSpoken = true }

    private var subtitle: String {
        if preview.isPreviewing { return "Camera previews are on. Program output is off." }
        return StoppedSessionCopy.line(endedAt: lastSessionEndedAt, duration: lastSessionDuration,
                                route: lastSessionRoute ?? readiness.inputs.effectiveRoute)
    }
}
