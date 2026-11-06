//
//  TrackAPillTests.swift
//  CinematicCoreMacOSTests
//
//  Track A (UX J4, J12, keyboard-map.md): the pill's groups, what the live
//  single-camera view publishes, why a control is unavailable, and what
//  Stop says it stops.
//

import CoreGraphics
import Testing
@testable import Alfie

@MainActor
struct TrackAPillTests {
    // MARK: Clusters (J4)

    @Test func stagePillReadsAsSubjectShotMoveSession() {
        let sections = OperatorPill.sections(isWebcam: false, showsTargetChip: false, showsStopSession: true)
        let groups = OperatorPill.clusters(sections)
        #expect(groups.map(\.cluster) == [.subject, .shot, .move, .session])
        #expect(groups[0].sections == [.lockState, .detect])
        #expect(groups[1].sections == [.stageShots])
        #expect(groups[2].sections == [.crop, .manual, .autoPan, .zoom, .returnToWide])
        #expect(groups[3].sections == [.stopSession])
        // Every control appears once, in pill order.
        #expect(groups.flatMap(\.sections) == sections)
    }

    @Test func webcamPillKeepsTheSameGroups() {
        let groups = OperatorPill.clusters(
            OperatorPill.sections(isWebcam: true, showsTargetChip: false, showsStopSession: true))
        #expect(groups.map(\.cluster) == [.subject, .shot, .move, .session])
        #expect(groups[1].sections == [.webcamShots])
        #expect(groups[2].sections == [.crop, .zoom, .returnToWide])
    }

    @Test func consolePillHasItsChipInSubjectAndNoSession() {
        let groups = OperatorPill.clusters(
            OperatorPill.sections(isWebcam: false, showsTargetChip: true, showsStopSession: false))
        #expect(groups.first?.sections == [.targetChip, .lockState, .detect])
        #expect(!groups.contains { $0.cluster == .session })
    }

    @Test func groupsAreTwelvePointsApart() {
        #expect(OperatorPill.clusterGap == 12)
        #expect(OperatorPill.controlSpacing < OperatorPill.clusterGap)
    }

    // MARK: Published commands (keyboard-map.md)

    private func state(running: Bool = true, webcam: Bool = false, discovering: Bool = false,
                       detect: Bool = true, push: Bool = true, pull: Bool = false) -> PillCommandState {
        PillCommandState(isRunning: running, isWebcam: webcam, isDiscovering: discovering,
                         detectEnabled: detect, canPushIn: push, canPullOut: pull)
    }

    @Test func stoppedPillPublishesNothing() {
        #expect(state(running: false).published.isEmpty)
    }

    @Test func liveStagePublishesDetectShotsZoomAndStop() {
        #expect(state().published == [.detect, .stopSession, .wide, .fullBody, .waistUp, .pushIn])
        #expect(state(push: false, pull: true).published.contains(.pullOut))
        #expect(!state(push: false, pull: true).published.contains(.pushIn))
    }

    @Test func escapeIsCancelDetectOnlyWhileDetectWaits() {
        let waiting = state(discovering: true).published
        #expect(waiting.contains(.cancel))
        #expect(!waiting.contains(.detect))
        #expect(!state().published.contains(.cancel))
    }

    @Test func unavailableDetectIsWithdrawn() {
        #expect(!state(detect: false).published.contains(.detect))
    }

    @Test func webcamHasNoFullBodyOrWaistUp() {
        let ids = state(webcam: true).published
        #expect(ids.contains(.wide))
        #expect(!ids.contains(.fullBody))
        #expect(!ids.contains(.waistUp))
    }

    @Test func pillNeverPublishesTakeOrCueKeys() {
        let everything = state(discovering: false, push: true, pull: true).published
            .union(state(discovering: true).published)
        for id in [AlfieCommandCatalog.ID.take, .cuePreview1, .cuePreview2, .cuePreview3, .cuePreview4] {
            #expect(!everything.contains(id))
        }
        #expect(AlfieCommandCatalog.definition(for: .take).shortcut == nil)
    }

    @Test func menuListsThePillKeys() {
        let title = { (id: AlfieCommandCatalog.ID) in
            AlfieCommands.menuTitle(for: AlfieCommandCatalog.definition(for: id), action: nil)
        }
        #expect(title(.detect) == "Detect (key D)")
        #expect(title(.wide) == "Wide (key W)")
        #expect(title(.fullBody) == "Full Body (key F)")
        #expect(title(.waistUp) == "Waist Up (key U)")
        #expect(title(.pushIn) == "Push In (key ])")
        #expect(title(.pullOut) == "Pull Out (key [)")
    }

    // MARK: Unavailable reasons (J4)

    @Test func detectSaysWhyItIsUnavailable() {
        #expect(PillUnavailableReason.detect(isRunning: false, operatorGeometry: false, isLocked: false,
                                             canReacquire: false, isAcquiring: false) == "Start the session first.")
        #expect(PillUnavailableReason.detect(isRunning: true, operatorGeometry: true, isLocked: false,
                                             canReacquire: false, isAcquiring: false)
                == "Turn off Manual or Auto Pan to detect.")
        #expect(PillUnavailableReason.detect(isRunning: true, operatorGeometry: false, isLocked: true,
                                             canReacquire: false, isAcquiring: false) == "Unlock the subject first.")
        #expect(PillUnavailableReason.detect(isRunning: true, operatorGeometry: false, isLocked: true,
                                             canReacquire: true, isAcquiring: false) == nil)
    }

    @Test func zoomSaysWhyItIsUnavailable() {
        #expect(PillUnavailableReason.zoom(.pushIn, isRunning: true, canBegin: false, movingDirection: nil,
                                           isZoomLimited: true) == "Zoom limited by the source.")
        #expect(PillUnavailableReason.zoom(.pushIn, isRunning: true, canBegin: false, movingDirection: nil,
                                           isZoomLimited: false) == "Already at the tightest shot.")
        #expect(PillUnavailableReason.zoom(.pullOut, isRunning: true, canBegin: false, movingDirection: nil,
                                           isZoomLimited: false) == "Already at the widest shot.")
        #expect(PillUnavailableReason.zoom(.pushIn, isRunning: true, canBegin: false, movingDirection: .pushIn,
                                           isZoomLimited: false) == "Already pushing in.")
        #expect(PillUnavailableReason.zoom(.pushIn, isRunning: true, canBegin: true, movingDirection: nil,
                                           isZoomLimited: true) == nil)
    }

    @Test func cropNeedsALock() {
        #expect(PillUnavailableReason.crop(isRunning: true, isOn: false, hasLock: false) == "Lock a subject first.")
        #expect(PillUnavailableReason.crop(isRunning: true, isOn: false, hasLock: true) == nil)
    }

    // MARK: Stop (stop.md)

    @Test func stopConfirmationNamesTheActiveRoute() {
        #expect(StopRouteCopy.confirmation(for: .virtualCamera)
                == "This stops the cameras and Program output to Alfie camera.")
        #expect(StopRouteCopy.confirmation(for: .display) == "This stops the cameras and Direct Program output.")
        #expect(StopRouteCopy.confirmation(for: .rehearsal)
                == "This stops the rehearsal cameras. No external output is active.")
        #expect(StopRouteCopy.helper(for: .virtualCamera) == "Stops Program output to Alfie camera.")
        #expect(StopRouteCopy.helper(for: .display) == "Stops Program on Direct output.")
        #expect(StopRouteCopy.helper(for: .rehearsal) == "Stops the rehearsal cameras.")
    }

    @Test func stopHoldStillTakesPointEightSeconds() {
        #expect(HoldToStop.duration == 0.8)
    }
}
