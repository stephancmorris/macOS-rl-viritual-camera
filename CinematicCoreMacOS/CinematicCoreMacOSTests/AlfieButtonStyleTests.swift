//
//  AlfieButtonStyleTests.swift
//  CinematicCoreMacOSTests
//
//  The shared button family's state rules (UX F3) and the hold-to-stop
//  timing (D3, docs/ux/2026-11-05/stop.md), without rendering.
//

import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct AlfieButtonStyleTests {
    private func look(_ role: AlfieButtonStyle.Role, surface: AlfieButtonStyle.Surface = .chrome,
                      selected: Bool = false, enabled: Bool = true, hovered: Bool = false,
                      pressed: Bool = false, focused: Bool = false) -> AlfieButtonAppearance {
        AlfieButtonAppearance.resolve(AlfieButtonStyle(role: role, surface: surface, isSelected: selected),
                                      isEnabled: enabled, isHovered: hovered, isPressed: pressed,
                                      isFocused: focused)
    }

    @Test func primaryStepsLighterOnHoverAndDarkerWhenPressed() {
        #expect(look(.primary).fill == .accent)
        #expect(look(.primary, hovered: true).fill == .primaryHover)
        #expect(look(.primary, hovered: true, pressed: true).fill == .primaryPressed)
        #expect(look(.primary).label == .onAccent)
    }

    @Test func takeAndStopUseTheProgramSteps() {
        #expect(look(.destructive).fill == .programFill)
        #expect(look(.destructive, hovered: true).fill == .programHover)
        #expect(look(.destructive, pressed: true).fill == .programPressed)
        #expect(look(.destructive).label == .onFill)
    }

    /// An ineligible TAKE is never disabled: it keeps hover and press and a
    /// readable reason.
    @Test func refusingStaysInteractiveAndReadable() {
        let refused = look(.refusing, hovered: true)
        #expect(refused.fill == .controlFill)
        #expect(refused.wash == .hover)
        #expect(refused.label == .secondaryText)
    }

    @Test func disabledUsesTheFloorWithNoHoverOrPress() {
        for role in [AlfieButtonStyle.Role.primary, .secondary, .quiet, .segment] {
            let disabled = look(role, enabled: false, hovered: true, pressed: true)
            #expect(disabled.label == .disabledText, "\(role)")
            #expect(disabled.wash == .none, "\(role)")
        }
        #expect(look(.quiet, surface: .video, enabled: false).label == .videoDisabled)
    }

    /// Selection is a filled shape with onAccent text in chrome.
    @Test func selectedIsFilled() {
        #expect(look(.segment, selected: true).fill == .accent)
        #expect(look(.segment, selected: true).label == .onAccent)
        #expect(look(.segment).fill == .none)
        #expect(look(.segment, surface: .video, selected: true).fill == .videoSelected)
    }

    /// The active mode stays legible where its own button is disabled
    /// because it is already on (Manual, Auto Pan).
    @Test func anOnToggleStaysEmphasisedWhenDisabled() {
        let on = look(.toggle(isOn: true), surface: .video, enabled: false)
        #expect(on.label == .videoEmphasis)
        #expect(on.fill == .videoSelected)
        #expect(look(.toggle(isOn: false), surface: .video).fill == .none)
    }

    @Test func focusDrawsTheRingOnEveryRole() {
        let roles: [AlfieButtonStyle.Role] = [.primary, .secondary, .quiet, .destructive, .refusing,
                                              .tallyTile, .segment, .toggle(isOn: false)]
        for role in roles {
            #expect(look(role, focused: true).focusRing, "\(role)")
            #expect(!look(role).focusRing, "\(role)")
        }
    }

    @Test func secondaryIsOutlinedOnlyAtRestInChrome() {
        #expect(look(.secondary).outline)
        #expect(!look(.secondary, selected: true).outline)
        #expect(!look(.secondary, surface: .video).outline)
        #expect(look(.tallyTile, hovered: true).hairline)
    }
}

/// Hold-to-stop with an injected clock.
struct HoldToStopTests {
    @Test func releasingAt079SecondsDoesNotStop() {
        var hold = HoldToStop()
        hold.press(at: 100)
        let r1 = hold.update(at: 100.5)
        #expect(!r1)
        let r2 = hold.release(at: 100.79)
        #expect(!r2)
        #expect(hold.phase == .needsHold)
        #expect(hold.label == "Hold to stop")
        #expect(hold.progress(at: 100.79) == 0)
    }

    @Test func holdingFor08SecondsStopsExactlyOnce() {
        var hold = HoldToStop()
        hold.press(at: 100)
        #expect(hold.label == "Keep holding to stop")
        #expect(abs(hold.progress(at: 100.4) - 0.5) < 0.001)
        let r3 = hold.update(at: 100.8)
        #expect(r3)
        #expect(hold.phase == .stopping)
        let r4 = hold.update(at: 100.9)
        #expect(!r4)
        let r5 = hold.release(at: 101)
        #expect(!r5)
        let r6 = hold.confirm()
        #expect(!r6, "a second Stop is refused while stopping")
        hold.press(at: 102)
        #expect(hold.phase == .stopping, "a new press can't restart a sent Stop")
    }

    @Test func releasingAfterTheHoldCompletesIt() {
        var hold = HoldToStop()
        hold.press(at: 0)
        let r7 = hold.release(at: 0.85)
        #expect(r7)
        #expect(hold.phase == .stopping)
    }

    @Test func cancellingClearsProgressAndNeedsAFreshHold() {
        var hold = HoldToStop()
        hold.press(at: 10)
        hold.cancel()
        #expect(hold.phase == .needsHold)
        #expect(hold.progress(at: 10.5) == 0)
        let r8 = hold.update(at: 11)
        #expect(!r8)
        hold.press(at: 12)
        let r9 = hold.update(at: 12.5)
        #expect(!r9)
        let r10 = hold.update(at: 12.8)
        #expect(r10)
    }

    @Test func aClickOnlyAsksForAHold() {
        var hold = HoldToStop()
        hold.press(at: 5)
        let r11 = hold.release(at: 5.1)
        #expect(!r11)
        #expect(hold.label == "Hold to stop")
    }

    @Test func confirmationStopsOnceWithoutAHold() {
        var hold = HoldToStop()
        let r12 = hold.confirm()
        #expect(r12)
        #expect(hold.label == "Stopping session…")
        let r13 = hold.confirm()
        #expect(!r13)
    }

    @Test func aFailedStopOffersToTryAgain() {
        var hold = HoldToStop()
        let r14 = hold.confirm()
        #expect(r14)
        hold.stopDidFail()
        #expect(hold.label == "Try stopping again")
        hold.press(at: 0)
        let r15 = hold.update(at: 0.8)
        #expect(r15)
    }
}
