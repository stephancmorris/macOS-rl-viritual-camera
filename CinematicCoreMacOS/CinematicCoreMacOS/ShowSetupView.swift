//
//  ShowSetupView.swift
//  CinematicCoreMacOS
//
//  The stopped-screen show setup (SHOW-SETUP), 1280×800: show standard and
//  Program output, slot cards A–D, the pair check and the two Start buttons.
//  Pure view over ShowSetupModel; every change goes through ShowSetupActions
//  so the live adapter can apply it to the engine's own settings.
//

import SwiftUI

struct ShowSetupActions {
    var selectDevice: (ChannelID, String) -> Void
    var selectStandard: (ShowStandard) -> Void
    var selectOutput: (ProgramOutputManager.Route) -> Void
    var startAOnly: () -> Void
    var startPair: () -> Void
    /// See PairCheckPanel.onCheck.
    var checkPair: (() -> Void)?
}

struct ShowSetupView: View {
    let model: ShowSetupModel
    let actions: ShowSetupActions

    static let sidePadding: CGFloat = 64
    static let thumbnailHeight: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                      alignment: .leading, spacing: 10) {
                slotCard(.a)
                slotCard(.b)
                emptySlot(.c)
                emptySlot(.d)
            }
            .padding(.bottom, 14)

            PairCheckPanel(model: model, onCheck: actions.checkPair)
                .padding(.bottom, 16)

            HStack(spacing: 12) {
                Button(action: actions.startAOnly) {
                    Text("Start with Camera A only")
                }
                .buttonStyle(SetupButtonStyle(isPrimary: false))
                .disabled(!model.canStartAOnly)

                Button(action: actions.startPair) {
                    Text("Start show · A Program, B Preview")
                }
                .buttonStyle(SetupButtonStyle(isPrimary: true))
                .disabled(!model.canStartPair)
                Spacer()
            }

            Spacer(minLength: 12)

            Text("Nothing goes to the ATEM until you press Start. Alfie never restores a Program/Preview state from the last show.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, Self.sidePadding)
        .padding(.top, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(ConsoleStyle.background)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SESSION STOPPED")
                    .font(ConsoleStyle.label(10))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Show setup")
                    .font(.system(size: 27, weight: .semibold))
            }
            Spacer()
            headerPicker("Show standard") {
                Picker("Show standard", selection: Binding(
                    get: { model.standard },
                    set: { actions.selectStandard($0) })) {
                    ForEach(ShowStandard.allCases) { Text($0.title).tag($0) }
                }
            }
            headerPicker("Program output") {
                Picker("Program output", selection: Binding(
                    get: { model.output },
                    set: { actions.selectOutput($0) })) {
                    ForEach(model.outputs) { Text($0.title).tag($0) }
                }
            }
        }
    }

    private func headerPicker<P: View>(_ title: String, @ViewBuilder picker: () -> P) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(title)
                if model.isRunning {
                    Image(systemName: "lock.fill").accessibilityLabel("Locked while the show runs")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            picker()
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 180)
                .disabled(model.isRunning)
        }
    }

    // MARK: Slots

    private func slotCard(_ slot: ChannelID) -> some View {
        let device = model.device(for: slot)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("CAM \(slot.letter)")
                    .font(ConsoleStyle.label(12))
                Text(slot == .a ? "Program at Start" : "Preview at Start")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                devicePicker(slot)
            }
            thumbnail(device)
            if let device {
                HStack(spacing: 14) {
                    // Read-only: the engine has one capture profile for all
                    // channels (Settings → Framing); no per-slot choice yet.
                    Text("Capture profile · \(model.captureProfile)")
                    Text(model.deliveryTitle)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Camera \(slot.letter), \(device.name). Capture profile \(model.captureProfile). \(model.deliveryTitle)")
            } else {
                Text(model.noteText(for: slot) ?? "Choose a device")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ConsoleStyle.amber)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(device == nil ? ConsoleStyle.amber.opacity(0.45) : ConsoleStyle.neutralBorder, lineWidth: 1)
        }
    }

    private func devicePicker(_ slot: ChannelID) -> some View {
        Menu {
            ForEach(model.options(for: slot)) { option in
                Button {
                    actions.selectDevice(slot, option.device.uniqueID)
                } label: {
                    Text(option.unavailableReason.map { "\(option.device.name) — \($0)" } ?? option.device.name)
                }
                .disabled(!option.isAvailable)
            }
            if model.devices.isEmpty {
                Text("No cameras connected")
            }
        } label: {
            Text(model.deviceTitle(for: slot))
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(model.isRunning)
        .accessibilityLabel("Camera \(slot.letter) device")
        .accessibilityValue(model.deviceTitle(for: slot))
    }

    /// Neutral placeholder: no camera opens before Start, so there is no
    /// picture yet — only the chosen device's name.
    private func thumbnail(_ device: ShowSetupModel.Device?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.55))
            VStack(spacing: 8) {
                Image(systemName: device == nil ? "video.slash" : "video")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                Text(device?.name ?? "No camera")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(device == nil ? 0.4 : 0.8))
                    .lineLimit(1)
                Text("The camera opens when the show starts")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
        }
        .frame(height: Self.thumbnailHeight)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func emptySlot(_ slot: ChannelID) -> some View {
        HStack(spacing: 10) {
            Text("CAM \(slot.letter)")
                .font(ConsoleStyle.label(12))
                .foregroundStyle(.white.opacity(0.45))
            Text("not assigned")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Start buttons: filled blue for the pair start, neutral for A only.
private struct SetupButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.8 : 1))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isPrimary ? 0.18 : 0.2), lineWidth: 1)
            }
    }

    private var fill: Color {
        guard isEnabled else { return ConsoleStyle.disabledFill }
        return isPrimary ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color.white.opacity(0.08)
    }
}
