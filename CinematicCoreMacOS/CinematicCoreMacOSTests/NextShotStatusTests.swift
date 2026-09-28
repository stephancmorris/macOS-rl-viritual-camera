//
//  NextShotStatusTests.swift
//  CinematicCoreMacOSTests
//

import Testing
@testable import Alfie

struct NextShotStatusTests {
    private func status(_ scenario: FakeConsoleModel.Scenario, _ standard: ShowStandard = .p50) -> NextShotStatus {
        .make(FakeConsoleModel.snapshot(for: scenario, standard: standard))
    }

    @Test func ready() {
        let next = status(.ready)
        #expect(next.shotLine == "Cam B · Band side · Waist Up")
        #expect(next.readiness == .ready)
        #expect(next.statusText == "Ready · Take sends exactly this shot")
        #expect(next.accessibilityLabel == "Next: Cam B, Band side, Waist Up. Ready · Take sends exactly this shot")
    }

    @Test func preparing() {
        let next = status(.preparing)
        #expect(next.readiness == .notReady)
        #expect(next.statusText == "Preparing Cam B · waiting for a fresh frame")
    }

    @Test func unsupported() {
        #expect(status(.unsupported).statusText == "Cam B unsupported alongside Cam A at 1080p50")
        #expect(status(.unsupported, .p5994).statusText == "Cam B unsupported alongside Cam A at 1080p59.94")
    }

    @Test func missing() {
        let next = status(.missing)
        #expect(next.readiness == .notReady)
        #expect(next.statusText == "Cam B source missing")
    }

    @Test func editLive() {
        let next = status(.editLive)
        #expect(next.readiness == .editingLive)
        #expect(next.statusText == "Editing Program live · Preview Cam B is unchanged")
    }

    @Test func singleInput() {
        let next = status(.oneInput)
        #expect(next.readiness == .noPreviewCamera)
        #expect(next.shotLine == "No Preview camera")
        #expect(next.preview == nil)
    }

    @Test func followsRolesAfterTake() {
        #expect(status(.twoInputs).shotLine == "Cam A · Stage wide · Waist Up")
    }

    @Test(arguments: FakeConsoleModel.Scenario.allCases, ShowStandard.allCases)
    func reasonAlwaysEqualsTheTakeButtonReason(scenario: FakeConsoleModel.Scenario, standard: ShowStandard) {
        let snapshot = FakeConsoleModel.snapshot(for: scenario, standard: standard)
        let take = TakeAvailability.evaluate(snapshot)
        let next = NextShotStatus.make(snapshot)
        #expect(next.reasonText == take.reasonText)
        if next.readiness == .notReady {
            #expect(next.statusText == take.subtitle)
        }
    }

    @Test(arguments: FakeConsoleModel.Scenario.allCases)
    func directorSectionIsAlwaysNilInR2(scenario: FakeConsoleModel.Scenario) {
        #expect(status(scenario).director == nil)
    }
}
