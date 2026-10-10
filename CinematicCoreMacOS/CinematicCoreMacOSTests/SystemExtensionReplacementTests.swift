//
//  SystemExtensionReplacementTests.swift
//  CinematicCoreMacOSTests
//
//  CR-018: an older bundled virtual camera never replaces a newer installed
//  one; same or newer versions replace as before.
//

import SystemExtensions
import Testing
@testable import Alfie

struct SystemExtensionReplacementTests {
    private func action(installed: (String, String), bundled: (String, String)) -> OSSystemExtensionRequest.ReplacementAction {
        SystemExtensionActivationManager.replacementAction(
            existingShortVersion: installed.0, existingVersion: installed.1,
            newShortVersion: bundled.0, newVersion: bundled.1)
    }

    @Test func newerOrEqualBundleReplaces() {
        #expect(action(installed: ("1.2", "40"), bundled: ("1.3", "41")) == .replace)
        #expect(action(installed: ("1.2", "40"), bundled: ("1.2", "41")) == .replace)
        #expect(action(installed: ("1.2", "40"), bundled: ("1.2", "40")) == .replace)
    }

    @Test func olderBundleIsRefused() {
        #expect(action(installed: ("1.3", "41"), bundled: ("1.2", "50")) == .cancel)
        #expect(action(installed: ("1.2", "41"), bundled: ("1.2", "40")) == .cancel)
    }

    @Test func versionsCompareNumerically() {
        #expect(action(installed: ("1.9", "9"), bundled: ("1.10", "1")) == .replace)
        #expect(action(installed: ("1.10", "1"), bundled: ("1.9", "9")) == .cancel)
        #expect(action(installed: ("1.2", "9"), bundled: ("1.2", "10")) == .replace)
    }

    @MainActor @Test func refusedDowngradeNamesBothVersions() {
        let details = SystemExtensionActivationManager.downgradeRefusedDetails(installed: "1.3 (41)", bundled: "1.2 (40)")
        #expect(details.detail.contains("1.3 (41)"))
        #expect(details.detail.contains("1.2 (40)"))
    }
}
