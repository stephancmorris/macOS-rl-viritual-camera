//
//  AlfieDisplayPreferences.swift
//  CinematicCoreMacOS
//
//  The four macOS display settings Alfie honours (UX F4), read in one place:
//
//  - Increase Contrast: borders and separators double, tertiary text takes
//    the secondary value (both in `AlfieColor`, from the high-contrast
//    appearance) and the focus ring is 3 pt.
//  - Reduce Transparency: the Inspector drawer, its handle and the pill
//    are opaque.
//  - Reduce Motion: no acquiring pulse, live-dot pulse, refusal flash or
//    drawer slide; the drawer cross-fades and hold-to-stop fills in steps.
//  - Differentiate Without Colour: a lock glyph joins the pill's lock dot.
//
//  Views read `AlfieDisplay` (a DynamicProperty), which takes the system
//  values from SwiftUI's environment. Snapshot tests set
//  `alfieDisplayOverride` to force a setting, since SwiftUI's own keys
//  can't be set from outside.
//

import SwiftUI

nonisolated struct AlfieDisplayPreferences: Equatable, Sendable {
    var increaseContrast = false
    var reduceTransparency = false
    var reduceMotion = false
    var differentiateWithoutColor = false

    static let standard = AlfieDisplayPreferences()
}

nonisolated private struct AlfieDisplayOverrideKey: EnvironmentKey {
    static let defaultValue: AlfieDisplayPreferences? = nil
}

extension EnvironmentValues {
    /// Gallery and snapshot tests only: replaces the system settings below.
    var alfieDisplayOverride: AlfieDisplayPreferences? {
        get { self[AlfieDisplayOverrideKey.self] }
        set { self[AlfieDisplayOverrideKey.self] = newValue }
    }
}

/// The display settings in effect for a view. Store one in a view as
/// `private let display = AlfieDisplay()`.
struct AlfieDisplay: DynamicProperty {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiateWithoutColor
    @Environment(\.alfieDisplayOverride) private var override

    var preferences: AlfieDisplayPreferences {
        override ?? AlfieDisplayPreferences(increaseContrast: contrast == .increased,
                                            reduceTransparency: systemReduceTransparency,
                                            reduceMotion: systemReduceMotion,
                                            differentiateWithoutColor: systemDifferentiateWithoutColor)
    }

    var increaseContrast: Bool { preferences.increaseContrast }
    var reduceTransparency: Bool { preferences.reduceTransparency }
    var reduceMotion: Bool { preferences.reduceMotion }
    var differentiateWithoutColor: Bool { preferences.differentiateWithoutColor }

    /// The focus ring's width: 2 pt, 3 pt under Increase Contrast.
    var focusRingWidth: CGFloat { increaseContrast ? 3 : 2 }
    /// A control's outline: 1 pt, doubled under Increase Contrast.
    var outlineWidth: CGFloat { increaseContrast ? 2 : 1 }
}
