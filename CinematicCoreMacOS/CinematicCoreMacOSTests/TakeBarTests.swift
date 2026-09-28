//
//  TakeBarTests.swift
//  CinematicCoreMacOSTests
//
//  TakeAvailability: every refusal reason, their priority order, the ready
//  state, and labels that use channel letters and the active ShowStandard.
//

import Testing
@testable import Alfie

struct TakeBarTests {
    typealias Inputs = ConsoleSnapshot.TakeInputs

    private func evaluate(
        _ take: Inputs,
        program: ChannelID = .a,
        preview: ChannelID? = .b,
        standard: ShowStandard = .p50,
        editLive: Bool = false
    ) -> TakeAvailability {
        .evaluate(take: take, program: program, preview: preview, standard: standard, editLive: editLive)
    }

    @Test func readyPreviewIsEligibleAndNamesTheRoute() {
        let availability = evaluate(.ready)
        #expect(availability.isEligible)
        #expect(availability.reason == nil)
        #expect(availability.reasonText == nil)
        #expect(availability.subtitle == "Cam B → Program")
        #expect(availability.takeAccessibilityLabel == "Take Cam B to Program")
    }

    @Test func missingSourceReason() {
        var take = Inputs.ready
        take.sourcePresent = false
        let availability = evaluate(take)
        #expect(!availability.isEligible)
        #expect(availability.reason == .sourceMissing)
        #expect(availability.subtitle == "Cam B source missing")
    }

    @Test func unsupportedReasonUsesActiveShowStandard() {
        var take = Inputs.ready
        take.supportedAtStandard = false
        #expect(evaluate(take).subtitle == "Cam B unsupported alongside Cam A at 1080p50")
        #expect(evaluate(take, standard: .p5994).subtitle == "Cam B unsupported alongside Cam A at 1080p59.94")
        #expect(evaluate(take, program: .b, preview: .a, standard: .p60).subtitle
                == "Cam A unsupported alongside Cam B at 1080p60")
    }

    @Test(arguments: [
        \Inputs.hasFreshRender,
        \Inputs.matchesSourceGeneration,
        \Inputs.matchesShotRevision,
        \Inputs.legalGeometry,
    ])
    func everyFailedRenderCheckReadsAsPreparing(check: WritableKeyPath<Inputs, Bool>) {
        var take = Inputs.ready
        take[keyPath: check] = false
        let availability = evaluate(take)
        #expect(availability.reason == .preparing)
        #expect(availability.subtitle == "Preparing Cam B · waiting for a fresh frame")
    }

    @Test func heldFrameIsNeverTakeable() {
        var take = Inputs.ready
        take.isHeldFrame = true
        #expect(evaluate(take).reason == .preparing)
    }

    @Test func reasonsFollowPriorityOrder() {
        var take = Inputs.ready
        take.hasFreshRender = false
        take.supportedAtStandard = false
        take.sourcePresent = false
        #expect(evaluate(take).reason == .sourceMissing)

        take.sourcePresent = true
        #expect(evaluate(take).reason == .unsupported)

        take.supportedAtStandard = true
        #expect(evaluate(take).reason == .preparing)
    }

    @Test func singleInputHasNoPreviewToTake() {
        let availability = evaluate(.ready, preview: nil)
        #expect(!availability.isEligible)
        #expect(availability.reason == .noPreviewCamera)
        #expect(availability.subtitle == "No Preview camera")
    }

    @Test func pendingTakeRefusesFurtherClicksButKeepsOldRoles() {
        var take = Inputs.ready
        take.takePending = true
        let availability = evaluate(take)
        #expect(!availability.isEligible)
        #expect(availability.reason == nil)
        #expect(availability.subtitle == "Cam B → Program")
    }

    @Test func editLiveLabelsNameTheProgramChannel() {
        let off = evaluate(.ready)
        #expect(off.editLiveTitle == "Edit Live · Cam A")
        #expect(off.editLiveAccessibilityLabel == "Edit Program Cam A live")

        let on = evaluate(.ready, editLive: true)
        #expect(on.editLiveTitle == "Done editing Cam A")
        // Edit Live never blocks a Take; a successful Take leaves it.
        #expect(on.isEligible)
    }

    // MARK: - Fake model contract (routing unchanged on refusal)

    @MainActor @Test(arguments: [
        FakeConsoleModel.Scenario.preparing, .unsupported, .missing, .oneInput,
    ])
    func refusedTakeLeavesRolesUnchanged(scenario: FakeConsoleModel.Scenario) {
        let model = FakeConsoleModel(scenario: scenario)
        let before = model.snapshot
        model.take()
        #expect(model.snapshot == before)
        #expect(model.actionLog == ["take"])
    }

    @MainActor @Test func successfulTakeSwapsRolesAndLeavesEditLive() {
        let model = FakeConsoleModel(scenario: .editLive)
        model.take()
        #expect(model.snapshot.programChannel == .b)
        #expect(model.snapshot.previewChannel == .a)
        #expect(!model.snapshot.editLive)
        #expect(model.snapshot.controlTarget == .init(channel: .a, role: .preview))
        #expect(model.snapshot.slot(.b).input?.role == .program)
        #expect(model.snapshot.slot(.a).input?.role == .preview)
    }
}
