//
//  SettingsComponents.swift
//  CinematicCoreMacOS
//
//  Building blocks for the Settings pages: a scrolling page with a title,
//  mono section labels, rounded cards whose rows are divided automatically,
//  and the Live / Next Start timing chips.
//

import SwiftUI

/// When a page's or row's change takes effect.
enum SettingsTiming {
    /// Applies to the running show immediately.
    case live
    /// Applies the next time capture starts.
    case nextStart

    var title: String {
        switch self {
        case .live: return "Applies live"
        case .nextStart: return "Next Start"
        }
    }
}

struct SettingsTimingChip: View {
    let timing: SettingsTiming

    var body: some View {
        HStack(spacing: 5) {
            if timing == .live {
                Circle().frame(width: 6, height: 6)
            }
            Text(timing.title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.6)
        }
        .foregroundStyle(timing == .live ? AlfieColor.live : AlfieColor.nextStart)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(timing == .live ? AlfieColor.liveSoft : AlfieColor.nextStartSoft))
        .accessibilityLabel(timing == .live ? "Applies live" : "Applies at the next Start")
    }
}

/// A neutral capsule for states such as "Custom" or "Locked".
struct SettingsTag: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(AlfieColor.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(AlfieColor.controlFill))
    }
}

/// One Settings page: title, one-line purpose, optional timing chip, and
/// the page's sections in a centred column that scrolls.
struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    var timing: SettingsTiming? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AlfieColor.text)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(AlfieColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if let timing {
                        SettingsTimingChip(timing: timing)
                    }
                }
                .padding(.bottom, 4)

                content
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(AlfieColor.background)
    }
}

/// Mono uppercase label above a card, matching the Inspector's eyebrows.
struct SettingsSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(AlfieColor.tertiaryText)
            .padding(.leading, 4)
            .padding(.top, 26)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A rounded card. Each direct child is a row; separators go between them.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Group(subviews: content) { rows in
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    if index > 0 {
                        Rectangle().fill(AlfieColor.separator).frame(height: 1)
                    }
                    rows[index]
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AlfieColor.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AlfieColor.separator, lineWidth: 1)
        )
    }
}

/// A card row: title, optional detail and timing chip, control on the right.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String? = nil
    var timing: SettingsTiming? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AlfieColor.text)
                    if let timing {
                        SettingsTimingChip(timing: timing)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(AlfieColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 480, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(title: String, detail: String? = nil, timing: SettingsTiming? = nil) {
        self.init(title: title, detail: detail, timing: timing) { EmptyView() }
    }
}

/// A row whose control is a slider with its value read out in mono.
struct SettingsSliderRow: View {
    let title: String
    var detail: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let format: (Double) -> String

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            HStack(spacing: 12) {
                Group {
                    if let step {
                        Slider(value: $value, in: range, step: step)
                    } else {
                        Slider(value: $value, in: range)
                    }
                }
                .frame(width: 200)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))

                Text(format(value))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AlfieColor.secondaryText)
                    .frame(minWidth: 52, alignment: .trailing)
            }
        }
    }
}

/// A plain read-only value in mono, for About and Diagnostics rows.
struct SettingsValueText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(AlfieColor.secondaryText)
            .textSelection(.enabled)
    }
}

/// A small explanatory paragraph under a card.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(AlfieColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 10)
    }
}
