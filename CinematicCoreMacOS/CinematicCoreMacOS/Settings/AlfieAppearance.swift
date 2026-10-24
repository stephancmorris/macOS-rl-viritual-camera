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
/// look; light uses the same roles. Text pairs pass 4.5:1 in both.
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
    static let warning = dynamic(light: 0xB25000, dark: 0xFF9F0A)
    /// Errors, Program tally and on-air red.
    static let danger = dynamic(light: 0xD70015, dark: 0xFF453A)

    // Console chrome. Older views tint white for text and hairlines over the
    // dark console; `ink` is that white in Dark and near-black in Light, so
    // `ink.opacity(x)` keeps the same hierarchy in both.
    static let ink = dynamic(light: 0x1C1D21, dark: 0xFFFFFF)
    /// The drawer that slides over the console (Inspector).
    static let drawer = dynamic(light: 0xF7F7F9, dark: 0x141416, lightAlpha: 0.92, darkAlpha: 0.78)
    /// Camera previews and Program/Preview panes stay dark in both
    /// appearances so footage reads true.
    static let videoWell = Color(red: 0.03, green: 0.03, blue: 0.04)

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
