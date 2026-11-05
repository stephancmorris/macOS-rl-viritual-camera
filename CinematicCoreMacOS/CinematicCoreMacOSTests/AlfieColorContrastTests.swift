//
//  AlfieColorContrastTests.swift
//  CinematicCoreMacOSTests
//
//  Holds every text-on-surface pair in `AlfieColor` to WCAG 2.x contrast in
//  both appearances: 4.5:1 for text, 3:1 for disabled labels, the focus ring
//  and indicators drawn on footage. A palette change that breaks a pair fails
//  here with the pair, the appearance and the measured ratio.
//

import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct AlfieColorContrastTests {
    enum Look: String, CaseIterable, Sendable {
        case light, dark
    }

    // MARK: Pairs

    /// The surfaces text sits on. The drawer is translucent, so it is
    /// measured over the background it slides across.
    private static func surfaces(_ look: Look) -> [(String, Color, Color?)] {
        [("background", AlfieColor.background, nil),
         ("sidebar", AlfieColor.sidebar, nil),
         ("card", AlfieColor.card, nil),
         ("controlFill", AlfieColor.controlFill, nil),
         ("drawer", AlfieColor.drawer, AlfieColor.background)]
    }

    private static let textRoles: [(String, Color)] = [
        ("text", AlfieColor.text),
        ("secondaryText", AlfieColor.secondaryText),
        ("tertiaryText", AlfieColor.tertiaryText),
        ("accentText", AlfieColor.accentText),
        ("live", AlfieColor.live),
        ("warning", AlfieColor.warning),
        ("danger", AlfieColor.danger),
        ("nextStart", AlfieColor.nextStart)
    ]

    @Test(arguments: Look.allCases)
    func textRolesPassOnEverySurface(look: Look) {
        for (surfaceName, surface, under) in Self.surfaces(look) {
            let ground = Self.flatten(surface, over: under, look)
            for (roleName, role) in Self.textRoles {
                let ratio = Self.contrast(Self.flatten(role, over: nil, look), ground)
                #expect(ratio >= 4.5, "\(roleName) on \(surfaceName) in \(look): \(Self.format(ratio))")
            }
        }
    }

    /// Disabled labels and the focus ring (`accentText`) need 3:1.
    @Test(arguments: Look.allCases)
    func disabledLabelsAndFocusRingPassThreeToOne(look: Look) {
        for (surfaceName, surface, under) in Self.surfaces(look) {
            let ground = Self.flatten(surface, over: under, look)
            for (roleName, role) in [("disabledText", AlfieColor.disabledText), ("focus ring", AlfieColor.accentText)] {
                let ratio = Self.contrast(Self.flatten(role, over: nil, look), ground)
                #expect(ratio >= 3, "\(roleName) on \(surfaceName) in \(look): \(Self.format(ratio))")
            }
        }
    }

    @Test(arguments: Look.allCases)
    func textOnFillsPasses(look: Look) {
        let pairs: [(String, Color, Color)] = [
            ("onAccent on accent", AlfieColor.onAccent, AlfieColor.accent),
            ("onFill on programFill", AlfieColor.onFill, AlfieColor.programFill),
            ("onFill on tally.programChip", AlfieColor.onFill, AlfieColor.tally.programChip),
            ("onFill on tally.previewChip", AlfieColor.onFill, AlfieColor.tally.previewChip),
            ("onBrightFill on tracking.candidate", AlfieColor.onBrightFill, AlfieColor.tracking.candidate),
            ("onBrightFill on tracking.acquiring", AlfieColor.onBrightFill, AlfieColor.tracking.acquiring),
            ("onBrightFill on tracking.locked", AlfieColor.onBrightFill, AlfieColor.tracking.locked),
            ("onBrightFill on the AUTO badge", AlfieColor.onBrightFill, AlfieColor.tally.preview),
            ("secondaryText on the refused TAKE", AlfieColor.secondaryText, ConsoleStyle.disabledFill)
        ]
        for (name, fore, fill) in pairs {
            let ratio = Self.contrast(Self.flatten(fore, over: nil, look), Self.flatten(fill, over: nil, look))
            #expect(ratio >= 4.5, "\(name) in \(look): \(Self.format(ratio))")
        }
    }

    /// Text on the pill and HUD, measured on the pill's glass over dark
    /// footage and on a bare video well. Footage itself is unbounded; the
    /// glass and the shadows carry the rest.
    @Test func onVideoTextPassesOnTheGlass() {
        let well = Self.flatten(AlfieColor.videoWell, over: nil, .dark)
        let glass = Self.flatten(AlfieColor.onVideo.glass, over: AlfieColor.videoWell, .dark)
        let text: [(String, Color, Double)] = [
            ("emphasis", AlfieColor.onVideo.emphasis, 4.5),
            ("primary", AlfieColor.onVideo.primary, 4.5),
            ("secondary", AlfieColor.onVideo.secondary, 4.5),
            ("tertiary", AlfieColor.onVideo.tertiary, 4.5),
            ("disabled", AlfieColor.onVideo.disabled, 3)
        ]
        for (name, role, minimum) in text {
            let value = Self.flatten(role, over: nil, .dark)
            for (groundName, ground) in [("glass", glass), ("video well", well)] {
                let ratio = Self.contrast(value, ground)
                #expect(ratio >= minimum, "onVideo.\(name) on \(groundName): \(Self.format(ratio))")
            }
        }
    }

    /// Tallies, tracking boxes and status dots are graphics: 3:1 on footage.
    @Test func indicatorsOnFootagePassThreeToOne() {
        let well = Self.flatten(AlfieColor.videoWell, over: nil, .dark)
        let indicators: [(String, Color)] = [
            ("tally.program", AlfieColor.tally.program),
            ("tally.preview", AlfieColor.tally.preview),
            ("tracking.candidate", AlfieColor.tracking.candidate),
            ("tracking.acquiring", AlfieColor.tracking.acquiring),
            ("tracking.locked", AlfieColor.tracking.locked),
            ("onVideo.live", AlfieColor.onVideo.live),
            ("onVideo.warning", AlfieColor.onVideo.warning),
            ("onVideo.modeOn", AlfieColor.onVideo.modeOn)
        ]
        for (name, role) in indicators {
            let ratio = Self.contrast(Self.flatten(role, over: nil, .dark), well)
            #expect(ratio >= 3, "\(name) on the video well: \(Self.format(ratio))")
        }
    }

    /// The pill's lock dot and the SUBJECT box on the footage are one colour.
    @Test func lockedIsOneGreen() {
        let dot = Self.flatten(OperatorPill.LockState.locked.dotColor, over: nil, .dark)
        let box = Self.flatten(AlfieColor.tracking.locked, over: nil, .dark)
        #expect(dot == box)
    }

    /// The forced-dark video panes, the Settings previews and this test all
    /// rely on the colour scheme in the environment choosing the role's
    /// appearance.
    @Test func rolesResolvePerColourScheme() {
        let light = Self.flatten(AlfieColor.background, over: nil, .light)
        let dark = Self.flatten(AlfieColor.background, over: nil, .dark)
        #expect(abs(light.r - 0xF5 / 255) < 0.01 && abs(light.b - 0xF7 / 255) < 0.01, "light background: \(light)")
        #expect(abs(dark.r - 0x0E / 255) < 0.01 && abs(dark.b - 0x15 / 255) < 0.01, "dark background: \(dark)")
    }

    // MARK: Colour maths

    struct RGB: Equatable, CustomStringConvertible {
        var r: Double
        var g: Double
        var b: Double
        var description: String {
            String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        }
    }

    /// Resolves `color` for `look` in gamma-encoded sRGB, composited over
    /// `under` (or opaque) as AppKit draws it.
    static func flatten(_ color: Color, over under: Color?, _ look: Look) -> RGB {
        let (top, alpha) = resolve(color, look)
        guard alpha < 0.999 else { return top }
        let bottom = under.map { flatten($0, over: nil, look) } ?? RGB(r: 0, g: 0, b: 0)
        return RGB(r: top.r * alpha + bottom.r * (1 - alpha),
                   g: top.g * alpha + bottom.g * (1 - alpha),
                   b: top.b * alpha + bottom.b * (1 - alpha))
    }

    private static func resolve(_ color: Color, _ look: Look) -> (RGB, Double) {
        var environment = EnvironmentValues()
        environment.colorScheme = look == .dark ? .dark : .light
        let resolved = color.resolve(in: environment)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let converted = resolved.cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 4 else {
            Issue.record("could not convert \(color) to sRGB")
            return (RGB(r: 0, g: 0, b: 0), 1)
        }
        return (RGB(r: Double(c[0]), g: Double(c[1]), b: Double(c[2])), Double(c[3]))
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ c: RGB) -> Double {
        func channel(_ v: Double) -> Double {
            let v = min(max(v, 0), 1)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    private static func format(_ ratio: Double) -> String {
        String(format: "%.2f:1", ratio)
    }
}
