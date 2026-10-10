//
//  DirectorDemo.swift
//  CinematicCoreMacOS
//
//  C-01 gallery. Every DirectorSection v2 state, in plain words, driven by
//  FakeConsoleModel. The live next-shot panel stays 600×70 until C-03.
//  Mode placement (U1), notice length (A4) and run-sheet format (F3) are
//  still open: this shows the recommended layout with fixture values.
//

#if DEBUG
import SwiftUI

struct DirectorDemo: View {
    @ObservedObject var model: FakeConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recommended layout. Live placement, notice length and run-sheet format are still open. Controls are shown, not wired.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.directorStates) { item in
                DirectorStateCard(item: item)
            }
        }
        .frame(maxWidth: 1232, alignment: .leading)
    }
}

struct DirectorStateCard: View {
    let item: DirectorGalleryCase

    private var section: DirectorSectionMirror { item.section }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title.uppercased())
                .font(ConsoleStyle.label(11))
                .foregroundStyle(.white.opacity(0.55))

            modeRow
            handRow
            statusBlock
            if let channel = section.badgeChannel {
                badgeTile(channel)
            }
            if section.runSheet != nil {
                runSheetRow
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ConsoleStyle.neutralFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ConsoleStyle.neutralBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var modeRow: some View {
        HStack(spacing: 8) {
            ForEach(section.modeChips, id: \.level) { chip in
                modeChip(chip)
            }
        }
    }

    private func modeChip(_ chip: DirectorSectionMirror.ModeChip) -> some View {
        VStack(spacing: 2) {
            Text(chip.title)
                .font(.system(size: 13, weight: chip.selected ? .semibold : .regular))
            if let caption = chip.unqualifiedCaption {
                Text(caption)
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .foregroundStyle(.white.opacity(chip.unqualifiedCaption == nil ? 1 : 0.38))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 88, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chip.selected ? Color.white.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(chip.selected ? ConsoleStyle.previewGreen : ConsoleStyle.neutralBorder, lineWidth: chip.selected ? 2 : 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibilityLabel)
        .accessibilityAddTraits(chip.selected ? .isSelected : [])
    }

    private var handRow: some View {
        let hand = section.handControl
        return HStack(spacing: 0) {
            handSegment(hand.manualTitle, selected: hand.manualSelected)
            handSegment(hand.handTitle, selected: !hand.manualSelected)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hand.accessibilityLabel)
    }

    private func handSegment(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(selected ? .white : .white.opacity(0.45))
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(selected ? Color.white.opacity(0.10) : Color.clear)
            .overlay(
                Rectangle()
                    .strokeBorder(selected ? ConsoleStyle.previewGreen : ConsoleStyle.neutralBorder, lineWidth: selected ? 2 : 1)
            )
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(NextShotStatus.label)
                    .font(ConsoleStyle.label(11))
                    .foregroundStyle(.white.opacity(0.55))
                Text(section.preparedLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(section.statusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let next = section.nextCutLine {
                Text(next)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityLabel(next)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func badgeTile(_ channel: ChannelID) -> some View {
        let slot = InputTileModel.Slot(rawValue: channel.letter) ?? .B
        let shot = section.prepared?.shotName ?? "Wide"
        let tile = InputTileModel(
            slot: slot,
            isAssigned: true,
            role: channel == .a ? .program : .preview,
            name: channel == .a ? "Stage wide" : "Band side",
            shot: shot,
            health: .rate("50.0"),
            renderedImage: nil)
        return InputTileView(
            model: tile,
            onCue: { _ in },
            directorBadge: section.showsAutoBadge(on: channel) ? DirectorSectionMirror.autoBadge : nil)
    }

    private var runSheetRow: some View {
        let sheet = section.runSheet
        return VStack(alignment: .leading, spacing: 6) {
            Text("RUN SHEET")
                .font(ConsoleStyle.label(11))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 16) {
                sheetColumn("Now", sheet?.current ?? "")
                sheetColumn("Next", sheet?.next ?? "None")
                Spacer(minLength: 8)
                Text("Advance")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(ConsoleStyle.neutralBorder, lineWidth: 1)
                    )
                    .accessibilityLabel("Advance")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.runSheetAccessibilityLabel ?? "Run sheet")
    }

    private func sheetColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(ConsoleStyle.label(10))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var dotColor: Color {
        switch section.activity.kind {
        case .active: ConsoleStyle.previewGreen
        case .paused, .inhibited: ConsoleStyle.amber
        case .abstaining: Color.white.opacity(0.35)
        }
    }
}
#endif
