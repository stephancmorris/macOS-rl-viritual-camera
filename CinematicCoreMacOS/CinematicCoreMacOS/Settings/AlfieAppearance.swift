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

/// Colour roles shared by light and dark. Dark keeps the console's near-black
/// look; light uses the same roles. Text pairs pass 4.5:1 in both, and
/// `AlfieColorContrastTests` holds every pair to that.
///
/// This file is the only place a view's colour is written as a number.
/// Views pick a role; `ColorRoleLintTests` fails on `Color(red:)` and on
/// opacity or white text anywhere else.
/// Nonisolated: AppKit resolves dynamic colours on whatever thread draws.
nonisolated enum AlfieColor {
    static let background = dynamic(light: 0xF5F5F7, dark: 0x0E1015)
    static let sidebar = dynamic(light: 0xECECEF, dark: 0x121419)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x181B21)
    static let controlFill = dynamic(light: 0xECEDF0, dark: 0x22262E)
    static let separator = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)
    static let border = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.14, darkAlpha: 0.14)
    static let text = dynamic(light: 0x1C1D21, dark: 0xF2F3F5)
    static let secondaryText = dynamic(light: 0x545964, dark: 0xA9AEB8)
    static let tertiaryText = dynamic(light: 0x666B75, dark: 0x8A909B)
    /// Fills that carry white text.
    static let accent = dynamic(light: 0x0066D6, dark: 0x0A6FE0)
    static let accentText = dynamic(light: 0x0060C9, dark: 0x5AA9FF)
    static let accentSoft = dynamic(light: 0x0066D6, dark: 0x0A84FF, lightAlpha: 0.10, darkAlpha: 0.16)
    static let live = dynamic(light: 0x157A34, dark: 0x30D158)
    static let liveSoft = dynamic(light: 0x157A34, dark: 0x30D158, lightAlpha: 0.12, darkAlpha: 0.14)
    static let nextStart = dynamic(light: 0x8A5F00, dark: 0xFFD60A)
    static let nextStartSoft = dynamic(light: 0xFFBE00, dark: 0xFFD60A, lightAlpha: 0.18, darkAlpha: 0.12)
    static let warning = dynamic(light: 0xAC4D00, dark: 0xFF9F0A)
    /// Errors, Program tally and on-air red.
    static let danger = dynamic(light: 0xD70015, dark: 0xFF5046)

    // Console chrome. `ink` is white in Dark and near-black in Light, so
    // `ink.opacity(x)` gives fills and hairlines the same weight in both.
    // Text never uses it: pick `text`, `secondaryText`, `tertiaryText` or
    // `disabledText`, which hold contrast where an opacity would not.
    static let ink = dynamic(light: 0x1C1D21, dark: 0xFFFFFF)
    /// The drawer that slides over the console (Inspector).
    static let drawer = dynamic(light: 0xF7F7F9, dark: 0x141416, lightAlpha: 0.92, darkAlpha: 0.78)
    /// Camera previews and Program/Preview panes stay dark in both
    /// appearances so footage reads true.
    static let videoWell = Color(red: 0.03, green: 0.03, blue: 0.04)

    // MARK: Text on fills, and disabled labels

    /// Text and icons on `accent` fills: selected segments, primary buttons.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// Text on solid saturated fills: `programFill`, tally chips, status fills.
    static let onFill = fixed(0xFFFFFF)
    /// Text on bright fills: tracking chips, the green AUTO badge.
    static let onBrightFill = fixed(0x111111)
    /// Solid on-air red under `onFill` text: TAKE, Stop session, Edit Live
    /// while on. Darker than `danger` in Dark so white text passes 4.5:1.
    static let programFill = dynamic(light: 0xD70015, dark: 0xD70015)
    /// The label of a disabled control: a 3:1 floor on every surface. The
    /// control still says why it is disabled, in `secondaryText`.
    static let disabledText = dynamic(light: 0x84888F, dark: 0x6A6F79)

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
                                 glass: fixed(0x1C1C1F, alpha: 0.55), tileGround: fixed(0x14171C))

    /// The standby backdrop's gradient, top leading to bottom trailing.
    static let backdropStops = [dynamic(light: 0xF7F7FA, dark: 0x0F1421),
                                dynamic(light: 0xF2F2F7, dark: 0x080D17),
                                dynamic(light: 0xEBEDF2, dark: 0x000000)]

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
        /// An assigned tile before its first frame.
        let tileGround: Color
    }

    private static func fixed(_ hex: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    private static func dynamic(light: UInt32, dark: UInt32,
                                lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
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
