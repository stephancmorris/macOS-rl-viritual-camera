//
//  ChannelCommandTests.swift
//  CinematicCoreMacOSTests
//
//  CHANNEL-CMD card: commands bind a ChannelID and that channel's epoch at
//  gesture start; a target switch mid-action rejects the old gesture instead
//  of retargeting it; stale epochs on one channel do not affect the other;
//  Program only takes live edits in Edit Live; control selection never routes.
//

import Foundation
import Testing
@testable import Alfie

@MainActor
struct ChannelCommandTests {
    /// Show with A (Program) and B (Preview), both marked running.
    private func twoChannelShow() -> ShowCoordinator {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        let b = show.addChannel(.b)
        show.channelA.setRunningForTesting(true)
        b.setRunningForTesting(true)
        return show
    }

    @Test func commandsAreAddressedToTheirOwnChannel() {
        let show = twoChannelShow()
        let b = show.channel(.b)!
        #expect(b.makeCommand(.returnToWide).target == .channel(.b))
        #expect(show.channelA.makeCommand(.returnToWide).target == .channel(.a))
        // A channel refuses a command addressed to another channel.
        #expect(show.channelA.dispatch(b.makeCommand(.returnToWide)) == .rejected("Wrong command target"))
    }

    @Test func controlTargetIsPreviewUntilEditLive() {
        let show = twoChannelShow()
        #expect(show.previewChannel == .b)
        #expect(show.controlTarget == .b)
        show.setEditLive(true)
        #expect(show.controlTarget == .a)
        show.setEditLive(false)
        #expect(show.controlTarget == .b)
    }

    @Test func singleChannelShowTargetsProgram() {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        #expect(show.previewChannel == nil)
        #expect(show.controlTarget == .a)
    }

    @Test func manualAndReturnWideOnPreviewAffectOnlyB() {
        let show = twoChannelShow()
        let a = show.channelA
        let b = show.channel(.b)!
        let aMode = a.activeMode
        #expect(show.dispatch(show.makeCommand(.setMode(.manualCrop))) == .accepted)
        #expect(b.activeMode == .manualCrop)
        #expect(show.dispatch(show.makeCommand(.returnToWide)) == .accepted)
        #expect(a.activeMode == aMode)
    }

    @Test func targetSwitchMidGestureRejectsInsteadOfRetargeting() {
        let show = twoChannelShow()
        let a = show.channelA
        let aRevision = a.shotRevision
        // Gesture starts while B is the target…
        let pending = show.makeCommand(.selectPreset(.stage(.fullBody)))
        #expect(pending.command.target == .channel(.b))
        // …the operator enters Edit Live before it lands.
        show.setEditLive(true)
        #expect(show.dispatch(pending) == .rejected("Control target changed"))
        // It did not land on A (now the target) either.
        #expect(a.shotRevision == aRevision)
    }

    @Test func programRejectsLiveEditsWithoutEditLive() {
        let show = twoChannelShow()
        // A command addressed to Program under the current revision.
        let live = ShowCoordinator.ShowCommand(
            command: show.channelA.makeCommand(.returnToWide),
            controlTargetRevision: show.controlTargetRevision)
        #expect(show.dispatch(live) == .rejected("Program changes need Edit Live"))
        show.setEditLive(true)
        #expect(show.dispatch(show.makeCommand(.returnToWide)) == .accepted)
    }

    @Test func staleEpochOnAIsIndependentOfBsValidEpoch() {
        let show = twoChannelShow()
        let a = show.channelA
        let b = show.channel(.b)!
        let staleA = a.makeCommand(.returnToWide)
        a.cancelOperatorMotion()          // A's epoch moves on
        let validB = b.makeCommand(.returnToWide)
        #expect(a.dispatch(staleA) == .rejected("Superseded command"))
        #expect(b.dispatch(validB) == .accepted)
    }

    @Test func stopShowRetiresEveryChannel() {
        let show = twoChannelShow()
        let a = show.channelA
        let b = show.channel(.b)!
        let aBefore = a.revisions
        let bBefore = b.revisions
        let pending = show.makeCommand(.returnToWide)
        show.stopShow()
        #expect(a.revisions.sourceGeneration > aBefore.sourceGeneration)
        #expect(b.revisions.sourceGeneration > bBefore.sourceGeneration)
        #expect(!show.dispatch(pending).wasAccepted)
    }

    @Test func recoveryAuthorityIsPerChannel() {
        let show = twoChannelShow()
        show.channel(.b)!.commands.setTrackingOwnership(true)
        #expect(show.channel(.b)!.commands.trackingOwnsControl)
        #expect(!show.channelA.commands.trackingOwnsControl)
    }

    @Test func controlSelectionNeverChangesRouting() {
        let show = twoChannelShow()
        let port = show.channelA.outputPort
        show.setEditLive(true)
        show.setEditLive(false)
        _ = show.dispatch(show.makeCommand(.setMode(.autoPan)))
        #expect(show.programChannel == .a)
        #expect(show.channelA.outputPort === port)
        #expect(show.router.routeGeneration == 0)
    }

    @Test func leavingControlCancelsPendingGesturesOnlyOnTheFormerTarget() {
        let show = twoChannelShow()
        let b = show.channel(.b)!
        b.detectionDiscoveryActive = true     // B armed Detect, not admitted yet
        show.channelA.detectionDiscoveryActive = true
        show.setEditLive(true)                // control moves B → A
        #expect(!b.detectionDiscoveryActive)
        #expect(show.channelA.detectionDiscoveryActive)
    }
}
