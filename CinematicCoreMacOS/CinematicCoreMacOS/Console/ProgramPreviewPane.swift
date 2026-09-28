//
//  ProgramPreviewPane.swift
//  CinematicCoreMacOS
//
//  One Multiview pane (Preview left, Program right). Draws the role ring,
//  mono-caps label, Program status, the Shot/Source toggle (control-target
//  pane only), the Edit Live banner (Program only) and any PaneOverlayState.
//
//  The picture is a slot: Preview shows the Preview channel's latest RENDERED
//  buffer and Program shows the router-committed buffer (incl. hold/standby).
//  Until ROUTER lands, callers pass `PanePlaceholderPicture`.
//

import CoreGraphics
import SwiftUI

/// Everything a pane shows, derived from one snapshot. Pure so it can be
/// unit-tested without rendering.
nonisolated struct PaneModel: Equatable, Sendable {
    let role: ConsoleSnapshot.Role
    let channel: ChannelID?
    let input: ConsoleSnapshot.Slot.Input?
    let overlay: PaneOverlayState
    /// Program only.
    let status: String?
    /// Only the control-target pane offers Shot/Source.
    let isControlTarget: Bool
    let paneView: ConsoleSnapshot.PaneView
    let showsEditLiveBanner: Bool

    static func preview(from snapshot: ConsoleSnapshot) -> PaneModel {
        let isTarget = snapshot.previewChannel != nil && snapshot.controlTarget.role == .preview
        return PaneModel(
            role: .preview,
            channel: snapshot.previewChannel,
            input: snapshot.input(snapshot.previewChannel),
            overlay: .preview(for: snapshot),
            status: nil,
            isControlTarget: isTarget,
            paneView: isTarget ? snapshot.paneView : .shot,
            showsEditLiveBanner: false)
    }

    static func program(from snapshot: ConsoleSnapshot) -> PaneModel {
        let isTarget = snapshot.controlTarget.role == .program
        return PaneModel(
            role: .program,
            channel: snapshot.programChannel,
            input: snapshot.input(snapshot.programChannel),
            overlay: .program(for: snapshot),
            status: PaneOverlayState.programStatus(for: snapshot.programOutput),
            isControlTarget: isTarget,
            paneView: isTarget ? snapshot.paneView : .shot,
            showsEditLiveBanner: snapshot.editLive)
    }

    var roleTitle: String { role == .program ? "PROGRAM" : "PREVIEW" }

    /// "PREVIEW · CAM B · Band side · Waist Up"
    var label: String {
        guard let channel, let input else { return roleTitle }
        return "\(roleTitle) · \(channel.cameraLabel.uppercased()) · \(input.name) · \(input.shot)"
    }

    var editLiveBannerText: String {
        "EDITING LIVE · Controls change Program · \(channel?.cameraLabel ?? "Program") now"
    }

    /// VoiceOver: role, camera, shot and status.
    var accessibilityLabel: String {
        var parts = [role == .program ? "Program" : "Preview"]
        if let channel { parts.append(channel.cameraLabel) }
        if let input { parts.append(input.name); parts.append(input.shot) }
        if let status { parts.append(status) }
        if let title = overlay.title { parts.append(title) }
        if showsEditLiveBanner { parts.append("Editing live") }
        return parts.joined(separator: ", ")
    }
}

struct ProgramPreviewPane<Picture: View>: View {
    let model: PaneModel
    var onPaneView: (ConsoleSnapshot.PaneView) -> Void = { _ in }
    var onReconnect: (ChannelID) -> Void = { _ in }
    var onDoneEditing: () -> Void = {}
    @ViewBuilder let picture: () -> Picture

    static var ringWidth: CGFloat { 3 }
    static var bannerHeight: CGFloat { 38 }

    private var ringColor: Color {
        model.role == .program ? ConsoleStyle.programRed : ConsoleStyle.previewGreen
    }

    var body: some View {
        ZStack(alignment: .top) {
            picture()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            overlay

            VStack(spacing: 0) {
                if model.showsEditLiveBanner { editLiveBanner }
                topRow
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                Spacer(minLength: 0)
            }
        }
        .background(Color.black)
        .overlay(
            Rectangle().strokeBorder(ringColor, lineWidth: Self.ringWidth)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
    }

    // MARK: - Chrome

    private var topRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(model.label.uppercased())
                .font(ConsoleStyle.label(11))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)

            Spacer(minLength: 8)

            if let status = model.status {
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
            }

            if model.isControlTarget {
                Picker("Pane view", selection: Binding(
                    get: { model.paneView },
                    set: { onPaneView($0) }
                )) {
                    Text("Shot").tag(ConsoleSnapshot.PaneView.shot)
                    Text("Source").tag(ConsoleSnapshot.PaneView.source)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
            }
        }
    }

    private var editLiveBanner: some View {
        HStack {
            Text(model.editLiveBannerText)
                .font(ConsoleStyle.label(12))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Button("Done", action: onDoneEditing)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ConsoleStyle.programRed)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.white, in: Capsule())
                .accessibilityLabel("Done editing \(model.channel?.cameraLabel ?? "Program") live")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.bannerHeight)
        .background(ConsoleStyle.programRed)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlay: some View {
        let state = model.overlay
        if state.isBlocking {
            ZStack {
                Color.black.opacity(0.92)
                VStack(spacing: 10) {
                    if let title = state.title {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    if let detail = state.detail {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                    }
                    if let channel = state.reconnectChannel, let title = state.reconnectTitle {
                        Button(title) { onReconnect(channel) }
                            .controlSize(.large)
                            .padding(.top, 4)
                    }
                }
                .padding(24)
            }
        } else if let title = state.title {
            // Non-blocking: dim the picture and caption it; the operator can
            // still see (and keep preparing) the shot.
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.7), in: Capsule())
                    .padding(.bottom, 16)
            }
        }
    }
}

extension ProgramPreviewPane where Picture == PanePlaceholderPicture {
    init(
        model: PaneModel,
        onPaneView: @escaping (ConsoleSnapshot.PaneView) -> Void = { _ in },
        onReconnect: @escaping (ChannelID) -> Void = { _ in },
        onDoneEditing: @escaping () -> Void = {}
    ) {
        self.init(model: model, onPaneView: onPaneView, onReconnect: onReconnect,
                  onDoneEditing: onDoneEditing) {
            PanePlaceholderPicture(model: model)
        }
    }
}

/// Stand-in picture until ROUTER supplies rendered buffers. Shot view is a
/// neutral frame; Source view is a wide frame with the legal crop dashed.
struct PanePlaceholderPicture: View {
    let model: PaneModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.20), Color(white: 0.09)],
                    startPoint: .top, endPoint: .bottom)
                if let input = model.input, !model.overlay.isBlocking {
                    if model.paneView == .source {
                        let crop = input.legalCrop
                        Rectangle()
                            .strokeBorder(Color.white.opacity(0.85),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .frame(width: geo.size.width * crop.width,
                                   height: geo.size.height * crop.height)
                            .position(x: geo.size.width * crop.midX,
                                      y: geo.size.height * crop.midY)
                        Text("SOURCE · \(model.channel?.cameraLabel.uppercased() ?? "")")
                            .font(ConsoleStyle.label(11))
                            .foregroundStyle(.white.opacity(0.5))
                            .position(x: geo.size.width / 2, y: geo.size.height - 24)
                    } else {
                        Text("\(input.name) · \(input.shot)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
