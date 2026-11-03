//
//  AutoPanMotion.swift
//  CinematicCoreMacOS
//
//  PAN-EASE-MODEL: the shape of an auto-pan sweep. Phase still advances at
//  constant speed and holds for the 1.5 s dwell at each end (CameraManager),
//  so transit time, dwell, phase continuity across width changes and zero
//  travel are unchanged. Only the mapping from phase to position differs:
//  the eased profile ramps speed up and down near each end instead of
//  turning around at full speed. Off by default (DeveloperFlags.easedAutoPan)
//  until the owner approves the curve from a replay (PAN-EASE).
//

import CoreGraphics

nonisolated enum AutoPanMotion {
    /// Fraction of the sweep spent accelerating at each end. Unapproved;
    /// a starting value for the replay comparison.
    static let easeFraction: CGFloat = 0.15

    /// Today's constant-speed sweep: position equals phase.
    static func linear(_ phase: CGFloat) -> CGFloat { min(1, max(0, phase)) }

    /// Trapezoidal speed profile over phase 0…1: speed ramps linearly from
    /// zero over `easeFraction`, holds, then ramps back to zero. Continuous
    /// position and speed; monotonic; 0 → 0 and 1 → 1.
    static func eased(_ phase: CGFloat, easeFraction r: CGFloat = easeFraction) -> CGFloat {
        let x = min(1, max(0, phase))
        let r = min(0.5, max(0, r))
        guard r > 0 else { return x }
        let peak = 1 / (1 - r)
        if x < r { return peak * x * x / (2 * r) }
        if x > 1 - r { let y = 1 - x; return 1 - peak * y * y / (2 * r) }
        return peak * (x - r / 2)
    }

    /// Position along the travel for `phase`, eased or not.
    static func position(_ phase: CGFloat, eased: Bool) -> CGFloat {
        eased ? self.eased(phase) : linear(phase)
    }
}
