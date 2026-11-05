//
//  AlfieButtonStyle.swift
//  CinematicCoreMacOS
//
//  The shared button family (UX F3). Every custom control takes its rest,
//  hover, pressed, focus, selected and disabled looks from here, so the
//  states read the same everywhere and a snapshot can't quietly drift:
//
//  - Hover: a 6% navy wash on Mist (8% Mist on Navy night); primary and
//    TAKE move one step lighter.
//  - Pressed: one step darker, with no scaling.
//  - Text inside a control uses `text` or `secondaryText`, never
//    `tertiaryText`: a hover or press wash would take tertiary below 4.5:1.
//  - Focus: a 2 pt `accentText` ring, 2 pt outside the control, following
//    its corner radius. Full Keyboard Access reaches every button.
//  - Selected: the `accent` fill with `onAccent` text, so the selected
//    segment is a filled shape as well as a colour. Toggles add an on/off
//    indicator whose shape changes (filled dot or ring).
//  - Disabled: `disabledText` with no opacity. `alfieUnavailableReason`
//    says why, as a help tag and to VoiceOver.
//
//  The pointer stays an arrow over buttons, as macOS does. TAKE is never
//  disabled: an ineligible TAKE uses `.refusing` and still takes the click.
//

import AppKit
import SwiftUI

struct AlfieButtonStyle: ButtonStyle {
    enum Role: Equatable, Sendable {
        /// Start session, Start show: the one main action on a surface.
        case primary
        /// An outlined action: Check pair, Edit Live at rest.
        case secondary
        /// No outline until hovered: run sheet, chooser rows, pill controls.
        case quiet
        /// TAKE, Stop session and Edit Live while on.
        case destructive
        /// A control that stays enabled but currently refuses with a reason
        /// (TAKE without a Preview camera).
        case refusing
        /// A Multi Cam input tile: the tile draws itself; the style adds
        /// hover, pressed and focus.
        case tallyTile
        /// One option in a segmented choice.
        case segment
        /// A mode that is on or off (Manual, Auto Pan).
        case toggle(isOn: Bool)
    }

    /// Chrome is the Mist or Navy night window; video is the pill's glass
    /// over footage, which keeps its dark look in every appearance.
    enum Surface: Sendable {
        case chrome
        case video
    }

    var role: Role
    var surface: Surface = .chrome
    var isSelected = false
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        AlfieButtonFace(label: configuration.label, isPressed: configuration.isPressed, style: self)
    }
}

extension View {
    /// Applies a member of the shared family and hands focus drawing to it,
    /// so a focused control shows one ring, not the system's and Alfie's.
    func alfieButtonStyle(_ role: AlfieButtonStyle.Role, surface: AlfieButtonStyle.Surface = .chrome,
                          isSelected: Bool = false, cornerRadius: CGFloat = 8) -> some View {
        buttonStyle(AlfieButtonStyle(role: role, surface: surface, isSelected: isSelected,
                                     cornerRadius: cornerRadius))
            .focusEffectDisabled()
    }

    /// A disabled control always says why: as a help tag, and as the hint
    /// VoiceOver reads. Pass nil while the control is available.
    @ViewBuilder
    func alfieUnavailableReason(_ reason: String?) -> some View {
        if let reason, !reason.isEmpty {
            help(reason).accessibilityHint(reason)
        } else {
            self
        }
    }
}

// MARK: - Forced states (gallery and snapshot tests)

/// Shows a control as hovered, pressed or focused without a pointer or a
/// keyboard, for the state gallery and its snapshot tests. Production views
/// never set it.
nonisolated enum AlfieForcedControlState: Sendable {
    case hover
    case pressed
    case focus
}

nonisolated private struct AlfieForcedControlStateKey: EnvironmentKey {
    static let defaultValue: AlfieForcedControlState? = nil
}

extension EnvironmentValues {
    var alfieForcedControlState: AlfieForcedControlState? {
        get { self[AlfieForcedControlStateKey.self] }
        set { self[AlfieForcedControlStateKey.self] = newValue }
    }
}

// MARK: - Face

/// The resolved look of one state, kept separate from the view so the state
/// rules can be read and tested without rendering.
struct AlfieButtonAppearance: Equatable {
    enum Fill: Equatable {
        case none, accent, programFill, controlFill, primaryHover, primaryPressed
        case programHover, programPressed, videoRest, videoSelected
    }

    enum Wash: Equatable {
        case none, hover, pressed, videoHover, videoPressed
    }

    enum LabelColor: Equatable {
        /// The label keeps its own colours (tiles).
        case inherited
        case text, secondaryText, disabledText, onAccent, onFill
        case videoPrimary, videoSecondary, videoEmphasis, videoDisabled
    }

    var fill: Fill
    var wash: Wash
    var label: LabelColor
    var outline: Bool
    var hairline: Bool
    var focusRing: Bool

    static func resolve(_ style: AlfieButtonStyle, isEnabled: Bool, isHovered: Bool,
                        isPressed: Bool, isFocused: Bool) -> Self {
        let video = style.surface == .video
        let hovered = isEnabled && isHovered
        let pressed = isEnabled && isPressed
        var look = Self(fill: .none, wash: .none, label: video ? .videoPrimary : .text,
                        outline: false, hairline: false, focusRing: isFocused)
        let wash: Wash = pressed ? (video ? .videoPressed : .pressed)
            : hovered ? (video ? .videoHover : .hover) : .none

        var selected = style.isSelected
        if case .toggle(let isOn) = style.role { selected = isOn }

        switch style.role {
        case .primary:
            look.fill = !isEnabled ? .controlFill : pressed ? .primaryPressed : hovered ? .primaryHover : .accent
            look.label = isEnabled ? .onAccent : .disabledText
        case .destructive:
            look.fill = !isEnabled ? .controlFill : pressed ? .programPressed : hovered ? .programHover : .programFill
            look.label = isEnabled ? .onFill : .disabledText
        case .refusing:
            look.fill = .controlFill
            look.wash = wash
            look.label = .secondaryText
        case .secondary:
            look.fill = selected ? (video ? .videoSelected : .accent) : (video ? .videoRest : .none)
            look.wash = wash
            look.outline = !video && !selected
            look.label = selectedLabel(selected, video: video, isEnabled: isEnabled, rest: video ? .videoEmphasis : .text)
        case .quiet, .segment, .toggle:
            look.fill = selected ? (video ? .videoSelected : .accent) : .none
            look.wash = wash
            let rest: LabelColor = style.role == .segment && video ? .videoSecondary
                : (video ? .videoPrimary : .text)
            look.label = selectedLabel(selected, video: video, isEnabled: isEnabled, rest: rest)
        case .tallyTile:
            look.label = .inherited
            look.wash = pressed ? .videoPressed : .none
            look.hairline = hovered
        }
        return look
    }

    private static func selectedLabel(_ selected: Bool, video: Bool, isEnabled: Bool,
                                      rest: LabelColor) -> LabelColor {
        // The active mode stays legible even where its own button is
        // disabled because it is already on.
        if selected { return video ? .videoEmphasis : .onAccent }
        if !isEnabled { return video ? .videoDisabled : .disabledText }
        return rest
    }
}

private struct AlfieButtonFace<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let style: AlfieButtonStyle

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.alfieForcedControlState) private var forced
    @State private var isHovering = false

    var body: some View {
        let look = AlfieButtonAppearance.resolve(style, isEnabled: isEnabled,
                                                 isHovered: isHovering || forced == .hover,
                                                 isPressed: isPressed || forced == .pressed,
                                                 isFocused: isFocused || forced == .focus)
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        HStack(spacing: 0) {
            if case .toggle(let isOn) = style.role {
                // The label's own leading padding is the gap to the text.
                AlfieToggleIndicator(isOn: isOn, isEnabled: isEnabled, surface: style.surface)
                    .padding(.leading, 10)
            }
            label
        }
        .modifier(AlfieLabelColor(color: look.label))
        // The wash sits between the fill and the label, so text keeps its
        // contrast. A control with its own ground (a Settings card) applies
        // that ground outside the style, behind the wash.
        .background {
            ZStack {
                shape.fill(Self.color(look.fill))
                if style.role != .tallyTile { shape.fill(Self.color(look.wash)) }
            }
        }
        .overlay {
            // A tile is opaque video, so its press shows over the picture.
            if style.role == .tallyTile {
                shape.fill(Self.color(look.wash)).allowsHitTesting(false)
            }
        }
        .overlay {
            if look.outline {
                shape.strokeBorder(isEnabled ? AlfieColor.control.outline : AlfieColor.border, lineWidth: 1)
            }
            if look.hairline {
                shape.strokeBorder(AlfieColor.onVideo.secondary, lineWidth: 1)
            }
        }
        .overlay {
            if look.focusRing {
                RoundedRectangle(cornerRadius: style.cornerRadius + 4, style: .continuous)
                    .strokeBorder(AlfieColor.accentText, lineWidth: 2)
                    .padding(-4)
            }
        }
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .modifier(AlfieToggleValue(role: style.role))
    }

    static func color(_ fill: AlfieButtonAppearance.Fill) -> Color {
        switch fill {
        case .none: return .clear
        case .accent: return AlfieColor.accent
        case .programFill: return AlfieColor.programFill
        case .controlFill: return AlfieColor.controlFill
        case .primaryHover: return AlfieColor.control.primaryHover
        case .primaryPressed: return AlfieColor.control.primaryPressed
        case .programHover: return AlfieColor.control.programHover
        case .programPressed: return AlfieColor.control.programPressed
        case .videoRest: return AlfieColor.control.videoRestFill
        case .videoSelected: return AlfieColor.control.videoSelectedFill
        }
    }

    static func color(_ wash: AlfieButtonAppearance.Wash) -> Color {
        switch wash {
        case .none: return .clear
        case .hover: return AlfieColor.control.hoverWash
        case .pressed: return AlfieColor.control.pressWash
        case .videoHover: return AlfieColor.control.videoHoverWash
        case .videoPressed: return AlfieColor.control.videoPressWash
        }
    }
}

private struct AlfieLabelColor: ViewModifier {
    let color: AlfieButtonAppearance.LabelColor

    func body(content: Content) -> some View {
        switch color {
        case .inherited: content
        case .text: content.foregroundStyle(AlfieColor.text)
        case .secondaryText: content.foregroundStyle(AlfieColor.secondaryText)
        case .disabledText: content.foregroundStyle(AlfieColor.disabledText)
        case .onAccent: content.foregroundStyle(AlfieColor.onAccent)
        case .onFill: content.foregroundStyle(AlfieColor.onFill)
        case .videoPrimary: content.foregroundStyle(AlfieColor.onVideo.primary)
        case .videoSecondary: content.foregroundStyle(AlfieColor.onVideo.secondary)
        case .videoEmphasis: content.foregroundStyle(AlfieColor.onVideo.emphasis)
        case .videoDisabled: content.foregroundStyle(AlfieColor.onVideo.disabled)
        }
    }
}

/// On is a filled dot; off is a ring. The shape carries the state, so it
/// never depends on colour alone.
private struct AlfieToggleIndicator: View {
    let isOn: Bool
    let isEnabled: Bool
    let surface: AlfieButtonStyle.Surface

    var body: some View {
        let on = surface == .video ? AlfieColor.onVideo.modeOn : AlfieColor.live
        let off = surface == .video
            ? (isEnabled ? AlfieColor.onVideo.secondary : AlfieColor.onVideo.disabled)
            : (isEnabled ? AlfieColor.secondaryText : AlfieColor.disabledText)
        ZStack {
            if isOn {
                Circle().fill(on)
            } else {
                Circle().strokeBorder(off, lineWidth: 1.5)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}

private struct AlfieToggleValue: ViewModifier {
    let role: AlfieButtonStyle.Role

    func body(content: Content) -> some View {
        if case .toggle(let isOn) = role {
            content.accessibilityValue(isOn ? "On" : "Off")
        } else {
            content
        }
    }
}
