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

import SwiftUI

struct OperatorModePicker: View {
    enum Style {
        /// Settings › Composer: segmented control over its description.
        case form
        /// The single-camera stopped screen: centred, dark.
        case stoppedScreen
        /// The Show setup header, beside Show standard and Program output.
        case setupHeader
    }

    @ObservedObject var store: OperatorModeStore
    var style: Style = .form

    @State private var refusal: String?

    private var selection: Binding<OperatorMode> {
        Binding(get: { store.mode }, set: { refusal = store.request($0) })
    }

    private var picker: some View {
        Picker("Mode", selection: selection) {
            ForEach(store.available) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint(refusal ?? store.mode.detail)
    }

    var body: some View {
        content
            .onChange(of: store.mode) { _, _ in refusal = nil }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .form:
            VStack(alignment: .leading, spacing: 6) {
                picker
                Text(refusal ?? store.mode.detail)
                    .font(.caption)
                    .foregroundStyle(refusal == nil ? Color.secondary : Color.orange)
            }

        case .stoppedScreen:
            VStack(spacing: 8) {
                picker
                    .labelsHidden()
                    .frame(width: 340)
                Text(refusal ?? store.mode.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(refusal == nil ? Color.white.opacity(0.55) : Color.orange)
                    .multilineTextAlignment(.center)
            }
            .environment(\.colorScheme, .dark)

        case .setupHeader:
            VStack(alignment: .leading, spacing: 5) {
                Text("Mode")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                picker
                    .labelsHidden()
                    .frame(width: 280)
                if let refusal {
                    Text(refusal)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                        .frame(width: 280, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
