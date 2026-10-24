//
//  OperatorModePicker.swift
//  CinematicCoreMacOS
//
//  The one control for Single Cam | Multi Cam | Webcam (MODE-SWITCH), in that
//  order wherever it appears: both stopped screens and Settings. Every change
//  goes through `OperatorModeStore.request`, so a live-switch refusal leaves
//  the mode as it was and its reason shows beside the control, not in an
//  alert. The Multiview kill switch removes Multi Cam from the choices.
//
//  Which segments are offered follows the cameras (`OperatorModeChoice`):
//  Multi Cam unlocks when a second camera connects, and Webcam appears only
//  on a Mac with a built-in camera. Each segment says why under its title.
//

import SwiftUI

struct OperatorModePicker: View {
    enum Style {
        /// Settings › Show & cameras: follows the app's appearance.
        case form
        /// The single-camera stopped screen: centred.
        case stoppedScreen
        /// The Show setup header, beside Show standard and Program output.
        case setupHeader
    }

    @ObservedObject var store: OperatorModeStore
    /// The cameras discovery currently sees.
    let cameras: OperatorModeChoice.Cameras
    var style: Style = .form

    @State private var refusal: String?
    /// Briefly outlines Multi Cam when a second camera unlocks it.
    @State private var isHighlightingMultiCam = false

    private var choices: [OperatorModeChoice] {
        OperatorModeChoice.choices(available: store.available, current: store.mode, cameras: cameras)
    }

    private var isMultiCamEnabled: Bool {
        choices.first { $0.mode == .multiCam }?.isEnabled ?? false
    }

    var body: some View {
        content
            .onChange(of: store.mode) { _, _ in refusal = nil }
            .onChange(of: isMultiCamEnabled) { wasEnabled, isEnabled in
                guard !wasEnabled, isEnabled, store.mode != .multiCam else { return }
                withAnimation(.easeOut(duration: 0.25)) { isHighlightingMultiCam = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.easeIn(duration: 0.4)) { isHighlightingMultiCam = false }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .form:
            VStack(alignment: .leading, spacing: 8) {
                segments(palette: .appearance, showsNotes: true)
                Text(refusal ?? store.mode.detail)
                    .font(.caption)
                    .foregroundStyle(refusal == nil ? AlfieColor.secondaryText : AlfieColor.warning)
            }

        case .stoppedScreen:
            VStack(spacing: 10) {
                segments(palette: .console, showsNotes: true)
                Text(refusal ?? store.mode.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(refusal == nil ? AlfieColor.ink.opacity(0.55) : AlfieColor.warning)
                    .multilineTextAlignment(.center)
            }

        case .setupHeader:
            VStack(alignment: .leading, spacing: 5) {
                Text("Mode")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AlfieColor.ink.opacity(0.6))
                segments(palette: .console, showsNotes: false)
                if let refusal {
                    Text(refusal)
                        .font(.system(size: 11))
                        .foregroundStyle(AlfieColor.warning)
                        .frame(width: 280, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func segments(palette: Palette, showsNotes: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(choices) { choice in
                segment(choice, palette: palette, showsNotes: showsNotes)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.track))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
        .accessibilityHint(refusal ?? store.mode.detail)
    }

    private func segment(_ choice: OperatorModeChoice, palette: Palette, showsNotes: Bool) -> some View {
        let isSelected = store.mode == choice.mode
        let highlight = choice.mode == .multiCam && isHighlightingMultiCam
        return Button {
            refusal = store.request(choice.mode)
        } label: {
            VStack(spacing: 2) {
                Text(choice.mode.title)
                    .font(.system(size: 13, weight: .semibold))
                if showsNotes {
                    Text(choice.note)
                        .font(.system(size: 11))
                        .opacity(0.85)
                }
            }
            .lineLimit(1)
            .foregroundStyle(isSelected ? Color.white
                             : choice.isEnabled ? palette.text : palette.disabledText)
            .frame(minWidth: showsNotes ? 132 : 84)
            .padding(.horizontal, 12)
            .padding(.vertical, showsNotes ? 7 : 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.selected : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.selected, lineWidth: highlight ? 1.5 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!choice.isEnabled)
        .help(choice.isEnabled ? choice.mode.detail : choice.note)
        .accessibilityLabel(choice.mode.title)
        .accessibilityValue(choice.note)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private struct Palette {
        let track: Color
        let selected: Color
        let text: Color
        let disabledText: Color

        /// Settings: light or dark with the app.
        static let appearance = Palette(track: AlfieColor.controlFill,
                                        selected: AlfieColor.accent,
                                        text: AlfieColor.text,
                                        disabledText: AlfieColor.tertiaryText)
        /// The console screens: the same roles on the console's backdrop.
        static let console = Palette(track: AlfieColor.ink.opacity(0.08),
                                     selected: AlfieColor.accent,
                                     text: AlfieColor.ink.opacity(0.92),
                                     disabledText: AlfieColor.ink.opacity(0.42))
    }
}

extension OperatorModeChoice.Cameras {
    init(_ devices: [CameraManager.CameraDevice]) {
        self.init(devices: devices.map { (uniqueID: $0.uniqueID, isBuiltIn: $0.isBuiltIn) })
    }
}
