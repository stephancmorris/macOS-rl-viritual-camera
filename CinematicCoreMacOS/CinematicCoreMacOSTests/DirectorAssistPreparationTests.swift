import Foundation
import Testing
@testable import Alfie

/// Synthetic MainActor replays through the actual CameraManager dispatcher.
@MainActor struct DirectorAssistPreparationTests {
    private final class Clock { var now = 100.0 }
    private struct Rig { let show: ShowCoordinator; let clock: Clock; let subject: UUID }
    private func configuration(one: Bool = true, age: Double = 1) -> DirectorAssistPreparation.Configuration {
        .init(readiness: .init(minimumSettledTime: 0, maximumMotion: 0.2, cutOnMotionAllowed: false,
              minimumCutSettledTime: 1, maximumCutMotion: 0.1), maximumRequestAge: age, onePreparationPerTenure: one)
    }
    private func rig() -> Rig {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        let clock = Clock(), subject = UUID(), b = show.addChannel(.b)
        show.clock = { clock.now }
        show.channelA.setRunningForTesting(true); b.setRunningForTesting(true)
        b.shotComposer.lockTarget(subject); b.setOperationMode(.autoTracking)
        show.director.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
                  outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist])
        }
        show.director.assistPreparation.readinessForTesting = .init(reasons: [])
        show.director.attach()
        #expect(show.director.setLevel(.assist) == .accepted)
        return .init(show: show, clock: clock, subject: subject)
    }
    private func request(_ r: Rig, shot: DirectorShot = .init(preset: .stage(.fullBody)), one: Bool = true) throws -> DirectorPreparation.Request {
        try #require(r.show.director.assistPreparation.enqueue(shot, configuration: configuration(one: one)))
    }
    @Test func actualDispatchMatchesReceiptAndChangesOnlyPreviewWhileKeepingTheLock() throws {
        let r = rig(), b = r.show.channel(.b)!, aBefore = r.show.channelA.revisions, before = b.revisions
        let result = r.show.director.preparePreview(.init(preset: .stage(.fullBody)), configuration: configuration())
        guard case .committed(let receipt) = result else { Issue.record("Expected real camera preparation"); return }
        #expect(b.revisions == receipt.postRevisions)
        #expect(b.revisions.controlEpoch == before.controlEpoch + 1 && b.revisions.shotRevision == before.shotRevision + 1)
        #expect(b.revisions.sourceGeneration == before.sourceGeneration && r.show.channelA.revisions == aBefore)
        #expect(b.manualLockedTargetID == r.subject && b.activeMode == .autoTracking && b.recoveryState.trackingOwnsControl)
        #expect(r.show.programChannel == .a && !r.show.director.authority.paused)
        #expect(r.show.director.directorSection.prepared?.shot == .init(preset: .stage(.fullBody)))
        #expect(r.show.director.directorSection.showsAutoBadge(on: .b))
    }
    @Test func tenureFlagCountsOnlyCommittedPreparations() throws {
        let r = rig(), sink = r.show.director.assistPreparation
        let old = try request(r), next = try request(r, shot: .init(preset: .stage(.waistUp)))
        #expect(sink.commit(old) == .rejected([.requestReplaced]))
        guard case .committed = sink.commit(next) else { Issue.record("Replacement did not commit"); return }
        #expect(sink.enqueue(.init(preset: .stage(.fullBody)), configuration: configuration()) == nil)
        let permitted = try request(r, one: false)
        guard case .committed = sink.commit(permitted) else { Issue.record("Explicit unrestricted tenure flag refused"); return }
    }
    @Test(arguments: ["manual", "editLive", "source", "gesture", "readiness", "expired", "roles"])
    func syntheticReplayHasZeroStaleCommits(intervention: String) throws {
        let r = rig(), sink = r.show.director.assistPreparation, b = r.show.channel(.b)!
        let captured = try request(r), before = b.revisions
        switch intervention {
        case "manual": r.show.director.takeOver()
        case "editLive": r.show.setEditLive(true)
        case "source": b.setSourceMissingForTesting(true)
        case "gesture": b.setOperatorGestureForTesting(true)
        case "readiness": sink.readinessForTesting = .init(reasons: [.identityUncertain])
        case "roles": _ = r.show.router.setProgram(.b, expectedRouteGeneration: r.show.router.routeGeneration)
        default: r.clock.now = 101.001
        }
        guard case .rejected = sink.commit(captured) else { Issue.record("Stale preparation committed"); return }
        #expect(b.revisions == before)
        #expect(sink.preparation.composition == nil)
    }
    @Test func mismatchOrRefusedDispatchIsTerminalAndTakesOver() throws {
        for accepts in [true, false] {
            let r = rig(), sink = r.show.director.assistPreparation
            let captured = try request(r)
            sink.dispatchForTesting = { _, _ in accepts ? .accepted : .rejected("synthetic refusal") }
            #expect(sink.commit(captured) == .failed)
            #expect(r.show.director.authority.paused && sink.preparation.composition == nil)
            #expect(sink.commit(captured) == .rejected([.requestReplaced]))
        }
    }
    @Test func detachmentRetiresCapturedPreparationAndReattachmentRequiresFreshHandback() throws {
        let r = rig(), controller = r.show.director, sink = controller.assistPreparation
        let captured = try request(r), channel = try #require(r.show.channel(.b)), before = channel.revisions
        let epoch = controller.authority.epoch
        controller.detach()
        #expect(!controller.isAttached && controller.authority.paused && controller.authority.epoch > epoch)
        #expect(sink.preparation.request == nil && sink.preparation.composition == nil)
        #expect(sink.commit(captured) == .rejected([.requestReplaced]))
        #expect(sink.enqueue(.init(preset: .stage(.fullBody)), configuration: configuration()) == nil)
        #expect(channel.revisions == before)

        controller.attach()
        #expect(controller.authority.paused)
        #expect(sink.commit(captured) == .rejected([.requestReplaced]))
        #expect(controller.handToAlfie() == .accepted)
        let fresh = try request(r)
        #expect(sink.commit(captured) == .rejected([.requestReplaced]))
        guard case .committed = sink.commit(fresh) else { Issue.record("Fresh attached request did not commit"); return }
        #expect(channel.revisions.controlEpoch == before.controlEpoch + 1)
    }
    @Test func detachedPreparationRefusesEvenWhenAuthorityWasExplicitlyRestored() throws {
        let r = rig(), controller = r.show.director, sink = controller.assistPreparation
        let channel = try #require(r.show.channel(.b)), before = channel.revisions
        controller.detach()
        // A retained caller can still invoke the control API directly. Restoring
        // its value-state grant cannot replace the missing manual/fault hooks.
        #expect(controller.handToAlfie() == .accepted)
        #expect(controller.authority.mayPrepare)
        #expect(sink.enqueue(.init(preset: .stage(.fullBody)), configuration: configuration()) == nil)
        controller.attach()
        #expect(controller.authority.paused && channel.revisions == before)
    }
    @Test func reinstallingHooksRetiresCapturedPreparationWithoutRenewingItsToken() throws {
        let r = rig(), controller = r.show.director, sink = controller.assistPreparation
        let captured = try request(r), channel = try #require(r.show.channel(.b)), before = channel.revisions
        let epoch = controller.authority.epoch
        controller.attach()
        #expect(controller.isAttached && controller.authority.epoch == epoch && !controller.authority.paused)
        #expect(sink.commit(captured) == .rejected([.requestReplaced]))
        #expect(channel.revisions == before)
        let fresh = try request(r)
        guard case .committed = sink.commit(fresh) else { Issue.record("Fresh request after hooks reinstalled did not commit"); return }
    }
    @Test func neverPreparesWithoutFreshEvidenceTrackingOrQualification() {
        let r = rig(), sink = r.show.director.assistPreparation, shot = DirectorShot(preset: .stage(.fullBody))
        sink.readinessForTesting = nil
        #expect(sink.enqueue(shot, configuration: configuration()) == nil)
        sink.readinessForTesting = .init(reasons: [])
        r.show.channel(.b)!.setOperatorGestureForTesting(true)
        #expect(sink.enqueue(shot, configuration: configuration()) == nil)
        r.show.channel(.b)!.setOperatorGestureForTesting(false)
        r.show.director.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
                  outputHealthy: true, admissionCurrent: true, qualifiedLevels: [])
        }
        #expect(sink.enqueue(shot, configuration: configuration()) == nil)
    }
    @Test func invalidClocksLeasesAndForeignPresetLaddersFailClosed() {
        let r = rig(), sink = r.show.director.assistPreparation, shot = DirectorShot(preset: .stage(.fullBody))
        #expect(sink.enqueue(.init(preset: .webcam(.tight)), configuration: configuration()) == nil)
        for value in [Double.nan, .infinity, -1] {
            #expect(sink.enqueue(shot, configuration: configuration(age: value)) == nil)
            r.clock.now = value
            #expect(sink.enqueue(shot, configuration: configuration()) == nil)
            r.clock.now = 100
        }
    }
    @Test func manualPresetEpochBehaviorIsUnchanged() {
        let r = rig(), b = r.show.channel(.b)!, before = b.revisions
        #expect(b.dispatch(b.makeCommand(.selectPreset(.stage(.fullBody)))) == .accepted)
        #expect(b.revisions.controlEpoch == before.controlEpoch + 2)
        #expect(r.show.director.authority.paused)
    }
}
