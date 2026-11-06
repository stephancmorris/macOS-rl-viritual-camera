//
//  AlfieAppearance.swift
//  CinematicCoreMacOS
//
//  The operator's System / Light / Dark choice (Settings › General) and the
//  colour roles that follow it. Each role resolves per appearance, so a view
//  that uses `AlfieColor` needs no colour-scheme branching of its own.
//

import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// UserDefaults key the choice is persisted under.
    static let userDefaultsKey = "appAppearance"

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    static var current: AppAppearance {
        UserDefaults.standard.string(forKey: userDefaultsKey).flatMap(AppAppearance.init) ?? .system
    }

    /// Sets the appearance of every window and menu. `nil` follows macOS.
    /// The Program feed is rendered pixels and is never affected.
    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Colour roles shared by light and dark: Mist in Light and Navy night in
/// Dark (owner decision D1, 5 Nov 2026). Text pairs pass 4.5:1 on every
/// surface in both, and `AlfieColorContrastTests` holds every pair to that
/// and pins each value below.
///
/// This file is the only place a view's colour is written as a number.
/// Views pick a role; `ColorRoleLintTests` fails on `Color(red:)` and on
/// opacity or white text anywhere else.
/// Nonisolated: AppKit resolves dynamic colours on whatever thread draws.
nonisolated enum AlfieColor {
    static let background = dynamic(light: 0xE4EAF1, dark: 0x0A1A2E)
    static let sidebar = dynamic(light: 0xDCE3EB, dark: 0x071526)
    static let card = dynamic(light: 0xF4F7F9, dark: 0x0C2340)
    static let controlFill = dynamic(light: 0xD6DDE5, dark: 0x173252)
    /// Separators and borders double under Increase Contrast (UX F4).
    static let separator = dynamic(light: 0x0C2340, dark: 0xE8EDF4, lightAlpha: 0.10, darkAlpha: 0.10,
                                   increased: IncreasedContrast.separator)
    static let border = dynamic(light: 0x0C2340, dark: 0xE8EDF4, lightAlpha: 0.18, darkAlpha: 0.16,
                                increased: IncreasedContrast.border)
    static let text = dynamic(light: 0x0C2340, dark: 0xE8EDF4)
    static let secondaryText = dynamic(light: 0x3E4F66, dark: 0xACB4BF)
    /// Takes the secondary value under Increase Contrast.
    static let tertiaryText = dynamic(light: 0x536174, dark: 0x919BA7,
                                      increased: IncreasedContrast.tertiaryText)
    /// Primary and selected fills under `onAccent` text: navy in Light, Mist
    /// in Navy night.
    static let accent = dynamic(light: 0x0C2340, dark: 0xE8EDF4)
    /// Links, highlighted values and the focus ring.
    static let accentText = dynamic(light: 0x1D4F91, dark: 0x9CC0EE)
    static let accentSoft = dynamic(light: 0x0C2340, dark: 0x9CC0EE, lightAlpha: 0.10, darkAlpha: 0.16)
    static let live = dynamic(light: 0x12672C, dark: 0x30D158)
    static let liveSoft = dynamic(light: 0x12672C, dark: 0x30D158, lightAlpha: 0.12, darkAlpha: 0.14)
    static let nextStart = dynamic(light: 0x7A5400, dark: 0xFFD60A)
    static let nextStartSoft = dynamic(light: 0xFFBE00, dark: 0xFFD60A, lightAlpha: 0.18, darkAlpha: 0.12)
    static let warning = dynamic(light: 0x9C4600, dark: 0xFF9F0A)
    /// Error text and the Program tally on console chrome. Never a fill
    /// under text: use `programFill` or `tally.programChip`.
    static let danger = dynamic(light: 0xB3001B, dark: 0xFF6961)

    // Console chrome. `ink` is navy in Light and Mist in Navy night, so
    // `ink.opacity(x)` gives fills and hairlines the same weight in both.
    // Text never uses it: pick `text`, `secondaryText`, `tertiaryText` or
    // `disabledText`, which hold contrast where an opacity would not.
    static let ink = dynamic(light: 0x0C2340, dark: 0xE8EDF4)
    /// The drawer that slides over the console (Inspector).
    static let drawer = dynamic(light: 0xF0F3F7, dark: 0x0A1D35, lightAlpha: 0.96, darkAlpha: 0.94)
    /// The drawer under Reduce Transparency.
    static let drawerOpaque = dynamic(light: 0xF0F3F7, dark: 0x0A1D35)
    /// Camera previews and Program/Preview panes stay neutral black in both
    /// appearances so footage reads true. Never tinted.
    static let videoWell = fixed(0x08080A)

    // MARK: Text on fills, and disabled labels

    /// Text and icons on `accent` fills: selected segments, primary buttons.
    static let onAccent = dynamic(light: 0xE8EDF4, dark: 0x0C2340)
    /// Text on solid saturated fills: `programFill`, tally chips, status fills.
    static let onFill = fixed(0xFFFFFF)
    /// Text on bright fills: tracking chips, the green AUTO badge.
    static let onBrightFill = fixed(0x111111)
    /// Solid on-air red under `onFill` text: TAKE, Stop session, Edit Live
    /// while on.
    static let programFill = dynamic(light: 0xB3001B, dark: 0xD70015)
    /// The label of a disabled control: a 3:1 floor on every surface. The
    /// control still says why it is disabled, in `secondaryText`.
    static let disabledText = dynamic(light: 0x6E7C91, dark: 0x7B8796)

    // MARK: Control states (UX F3)

    /// Hover, pressed and selected fills for `AlfieButtonStyle`. Hover is one
    /// step lighter, pressed one step darker, with no scaling. `text` and
    /// `secondaryText` pass 4.5:1 under every wash; text inside a control
    /// never uses `tertiaryText`, which a wash would push below it.
    static let control = Control(
        hoverWash: dynamic(light: 0x0C2340, dark: 0xE8EDF4, lightAlpha: 0.06, darkAlpha: 0.08),
        pressWash: dynamic(light: 0x0C2340, dark: 0x000000, lightAlpha: 0.12, darkAlpha: 0.20),
        primaryHover: dynamic(light: 0x1B3A63, dark: 0xF7F9FC),
        primaryPressed: dynamic(light: 0x081A30, dark: 0xCDD6E0),
        programHover: dynamic(light: 0xC40021, dark: 0xE0101F),
        programPressed: dynamic(light: 0x94001A, dark: 0xB3001B),
        outline: dynamic(light: 0x0C2340, dark: 0xE8EDF4, lightAlpha: 0.40, darkAlpha: 0.40,
                         increased: IncreasedContrast.outline),
        videoRestFill: fixed(0xFFFFFF, alpha: 0.07),
        videoHoverWash: fixed(0xFFFFFF, alpha: 0.08),
        videoPressWash: fixed(0xFFFFFF, alpha: 0.20),
        videoSelectedFill: fixed(0xFFFFFF, alpha: 0.14))

    nonisolated struct Control: Sendable {
        /// Quiet, secondary and segment buttons under the pointer.
        let hoverWash: Color
        let pressWash: Color
        let primaryHover: Color
        let primaryPressed: Color
        /// TAKE and Stop session.
        let programHover: Color
        let programPressed: Color
        /// A secondary button's outline at rest.
        let outline: Color
        /// Controls on the pill's glass over footage.
        let videoRestFill: Color
        let videoHoverWash: Color
        let videoPressWash: Color
        let videoSelectedFill: Color
    }

    // MARK: On footage
    // Drawn on video or on the dark glass over it, so identical in both
    // appearances.

    /// Program and Preview tallies on video panes and tiles.
    static let tally = Tally(program: fixed(0xFF453A), preview: fixed(0x30D158),
                             programChip: fixed(0x991A1A), previewChip: fixed(0x1A6140))
    /// Detection and subject-lock states. Locked is green everywhere: the
    /// box on the footage and the dot on the pill.
    static let tracking = Tracking(candidate: fixed(0x78DBFF), acquiring: fixed(0xFFBD3B),
                                   locked: fixed(0x38FF14))
    /// Text, indicators and chrome on the pill, HUD and video panes.
    static let onVideo = OnVideo(emphasis: fixed(0xFFFFFF), primary: fixed(0xDEDEE0),
                                 secondary: fixed(0xB4B4B8), tertiary: fixed(0x8E8E93),
                                 disabled: fixed(0x6C6C70), live: fixed(0x30D158),
                                 warning: fixed(0xFFBD3B), modeOn: fixed(0x4FEDC7),
                                 glass: fixed(0x1C1C1F, alpha: 0.55), glassOpaque: fixed(0x1C1C1F),
                                 tileGround: fixed(0x14171C))

    /// The standby backdrop: a flat background-to-sidebar gradient, top
    /// leading to bottom trailing.
    static let backdropStops = [background, sidebar]

    nonisolated struct Tally: Sendable {
        let program: Color
        let preview: Color
        /// Darker chip fills that carry `onFill` text on the pill.
        let programChip: Color
        let previewChip: Color
    }

    nonisolated struct Tracking: Sendable {
        /// A detected person who can be picked.
        let candidate: Color
        /// Acquiring, recovering and searching.
        let acquiring: Color
        let locked: Color
    }

    nonisolated struct OnVideo: Sendable {
        /// Highlighted or on.
        let emphasis: Color
        let primary: Color
        let secondary: Color
        let tertiary: Color
        /// A disabled control's label: 3:1 on the glass over dark footage.
        let disabled: Color
        let live: Color
        let warning: Color
        /// The dot beside a mode that is on (Manual, Auto Pan).
        let modeOn: Color
        /// The pill's tint over its material.
        let glass: Color
        /// The pill's ground under Reduce Transparency: no material.
        let glassOpaque: Color
        /// An assigned tile before its first frame.
        let tileGround: Color
    }

    private static func fixed(_ hex: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    /// What Increase Contrast changes: tertiary text takes the secondary
    /// value; borders, separators and control outlines double.
    nonisolated enum IncreasedContrast {
        static let tertiaryText = Increased(light: 0x3E4F66, dark: 0xACB4BF)
        static let separator = Increased(light: 0x0C2340, dark: 0xE8EDF4, lightAlpha: 0.20, darkAlpha: 0.20)
        static let border = Increased(light: 0x0C2340, dark: 0xE8EDF4, lightAlpha: 0.36, darkAlpha: 0.32)
        static let outline = Increased(light: 0x0C2340, dark: 0xE8EDF4, lightAlpha: 0.80, darkAlpha: 0.80)
    }

    /// The value a role takes when Increase Contrast is on.
    nonisolated struct Increased: Sendable {
        let light: UInt32
        let dark: UInt32
        var lightAlpha: CGFloat = 1
        var darkAlpha: CGFloat = 1
    }

    private static func dynamic(light: UInt32, dark: UInt32,
                                lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1,
                                increased: Increased? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let isIncreased = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
                || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let (hex, alpha) = resolve(light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha,
                                       increased: increased, isDark: isDark, isIncreased: isIncreased)
            return NSColor(hex: hex, alpha: alpha)
        })
    }

    /// The value a role resolves to. Increase Contrast reaches AppKit as the
    /// high-contrast appearances and as the workspace flag; the appearance
    /// can't be constructed by name, so tests call this directly.
    static func resolve(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1,
                        increased: Increased?, isDark: Bool, isIncreased: Bool) -> (UInt32, CGFloat) {
        if isIncreased, let increased {
            return (isDark ? increased.dark : increased.light, isDark ? increased.darkAlpha : increased.lightAlpha)
        }
        return (isDark ? dark : light, isDark ? darkAlpha : lightAlpha)
    }
}

nonisolated private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
