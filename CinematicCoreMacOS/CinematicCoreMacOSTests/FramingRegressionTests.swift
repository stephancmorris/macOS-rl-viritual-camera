//
//  FramingRegressionTests.swift
//  CinematicCoreMacOSTests
//

import CoreGraphics
import Foundation
import Testing
import CoreVideo
import SwiftUI
import AppKit
@testable import Alfie

/// Regression coverage for operator-visible framing semantics and validation
/// clip timing. These tests deliberately use geometry rather than labels from
/// the legacy `ShotFraming` setting: the stage/webcam presets are what the
/// operator selects and what the program crop represents.
@MainActor
struct FramingRegressionTests {
    private func engine(height: CGFloat = 0.5, center: CGPoint = CGPoint(x: 0.5, y: 0.5)) throws -> CropEngine {
        let engine = try #require(CropEngine())
        engine.qualityFloor = .forSource(height: 2160)
        engine.setTargetCrop(.init(center: center, size: CGSize(width: height, height: height)))
        engine.jumpToTarget()
        return engine
    }

    @Test func commandsRejectOldEpochExpiryWrongTargetAndLateCancel() {
        let dispatcher = CommandDispatcher()
        let begin = OperatorCommand(epoch: dispatcher.epoch, expiry: 10, action: .beginZoom(.pushIn))
        #expect(dispatcher.rejection(for: begin, now: 1) == nil)
        dispatcher.accept(begin)
        let release = OperatorCommand(epoch: dispatcher.epoch, expiry: 10, action: .endZoom)
        let manual = OperatorCommand(epoch: dispatcher.epoch, expiry: 10, action: .setMode(.manualCrop))
        dispatcher.accept(manual)
        #expect(dispatcher.rejection(for: release, now: 2) != nil)
        #expect(dispatcher.epoch != release.epoch)
        #expect(dispatcher.rejection(for: .init(epoch: dispatcher.epoch, expiry: 1, action: .detect), now: 2) != nil)
        #expect(dispatcher.rejection(for: .init(target: .session, epoch: dispatcher.epoch, expiry: 10, action: .detect), now: 2) != nil)
        let stop = OperatorCommand(target: .session, origin: .safety, epoch: dispatcher.epoch, expiry: 10, action: .stopSession)
        #expect(dispatcher.rejection(for: stop, now: 2) == nil)
        dispatcher.accept(stop)
        #expect(dispatcher.rejection(for: stop, now: 2) != nil)
    }

    @Test func operatorOwnershipRejectsAllTrackingRecoveryEffects() {
        let manager = CameraManager()
        manager.commands.setTrackingOwnership(true)
        manager.applyLockOutcome(.acquired)
        #expect(manager.activeMode == .autoTracking)
        for mode: CameraManager.OperationMode in [.manualCrop, .autoPan] {
            manager.setOperationMode(mode)
            for outcome: ShotComposer.TickOutcome in [.pullBackToWide, .resumeTracking, .acquired] {
                manager.applyLockOutcome(outcome)
                #expect(manager.activeMode == mode)
            }
        }
    }

    @Test func panSuspendsPerceptionUntilExplicitTrackAndWideClearsTheLock() {
        let manager = CameraManager()
        let subjectID = UUID()
        manager.shotComposer.lockTarget(subjectID)
        manager.shotComposer.forceTrackingForTesting()
        manager.setOperationMode(.autoTracking)
        #expect(manager.currentDetectionPlan(detectionRunsThisFrame: false).mode == .lockedROI)

        let oldDetectionGeneration = manager.detectionGenerationForTesting
        let oldIdentityGeneration = manager.shotComposer.identityGenerationForTesting
        let staleCommand = manager.makeCommand(.setMode(.autoTracking))
        manager.setOperationMode(.autoPan)
        #expect(manager.activeMode == .autoPan)
        #expect(manager.shotComposer.manualLockedTargetID == subjectID)
        #expect(manager.detectionGenerationForTesting != oldDetectionGeneration)
        #expect(manager.shotComposer.identityGenerationForTesting != oldIdentityGeneration)
        #expect(manager.commands.rejection(for: staleCommand, now: 0) != nil)
        #expect(manager.currentDetectionPlan(detectionRunsThisFrame: true).mode == .off)
        #expect(!manager.shotComposer.finishReacquisitionScoring(
            generation: oldIdentityGeneration, visibilityRevision: 0,
            observationID: 1, scores: []
        ))
        manager.applyLockOutcome(.resumeTracking)
        #expect(manager.activeMode == .autoPan)

        manager.setOperationMode(.manualCrop)
        #expect(manager.currentDetectionPlan(detectionRunsThisFrame: true).mode == .off)
        manager.setOperationMode(.autoTracking)
        #expect(manager.currentDetectionPlan(detectionRunsThisFrame: false).mode == .lockedROI)

        manager.returnToWide()
        #expect(manager.shotComposer.manualLockedTargetID == nil)
        #expect(manager.currentDetectionPlan(detectionRunsThisFrame: true).mode == .off)
        manager.setOperationMode(.autoPan)
        manager.setOperationMode(.autoTracking)
        #expect(manager.activeMode == .autoPan, "Track needs an explicit selected subject")
        #expect(manager.currentDetectionPlan(detectionRunsThisFrame: true).mode == .off)
    }

    @Test func returnToWideRetiresResumeAndClearsRecoveryEligibility() {
        let manager = CameraManager()
        let subjectID = UUID()
        manager.shotComposer.lockTarget(subjectID)
        manager.shotComposer.forceTrackingForTesting()
        let staleResume = manager.makeCommand(.resumeTracking)

        manager.returnToWide()

        #expect(manager.recoveryState.phase == .inactive)
        #expect(!manager.recoveryState.canResume)
        #expect(manager.recoveryState.statusLabel == "Pick subject")
        #expect(manager.commands.rejection(for: staleResume, now: 0) == "Superseded command")
        manager.resumeTracking()
        #expect(manager.activeMode == .wide)
    }

    @Test func panReentryPreservesSweepPhaseWithoutAdvancingWhileInactive() {
        let manager = CameraManager()
        manager.shotComposer.config.autoPanSpeed = 0.03
        manager.setOperationMode(.autoPan)
        _ = manager.advanceAutoPan(now: 100, width: 0.5)
        let before = manager.advanceAutoPan(now: 100.1, width: 0.5)
        #expect(before > 0.5)
        manager.setOperationMode(.manualCrop)
        manager.setOperationMode(.autoPan)
        let resumed = manager.advanceAutoPan(now: 200, width: 0.5)
        #expect(abs(resumed - before) < 0.000001)
        #expect(manager.advanceAutoPan(now: 200.1, width: 0.5) > resumed)
    }

    @Test func pillFits1280PointWindowWithoutHidingControls() {
        let manager = CameraManager()
        manager.shotComposer.config.cinematicFormat = .stage
        let view = NSHostingView(rootView: OperatorPill(cameraManager: manager))
        let width = view.fittingSize.width
        #expect(width > 800)
        #expect(width <= 1232, "Pill width \(width) must fit 1280 with 24pt margins")
    }

    @Test func focusLossAndStopCancelTheShotMove() throws {
        let manager = CameraManager()
        let engine = try #require(manager.cropEngine)
        manager.selectPreset(.stage(.fullBody))
        manager.setOperationMode(.manualCrop)
        manager.beginZoom(.pushIn)
        #expect(manager.zoomMoveDirection == .pushIn)
        let epoch = manager.commands.epoch
        manager.cancelOperatorMotion()
        #expect(engine.zoomDirection == nil)
        #expect(manager.zoomMoveDirection == nil)
        #expect(manager.commands.epoch != epoch)
        manager.beginZoom(.pushIn)
        #expect(manager.zoomMoveDirection == .pushIn)
        manager.stopCapture()
        #expect(engine.zoomDirection == nil)
        #expect(manager.zoomMoveDirection == nil)
        #expect(!engine.hasZoomAdjustment)
    }

    @Test func zoomCanSeedLastRenderedSizeInsteadOfInFlightPose() throws {
        let engine = try engine(height: 0.3)
        let visible = CropEngine.CropRect(center: CGPoint(x: 0.4, y: 0.5), size: CGSize(width: 0.6, height: 0.6))
        engine.beginZoom(.pushIn, to: 0.3, visibleCrop: visible)
        #expect(engine.currentCrop == visible)
        #expect(engine.adjustedHeight == 0.6)
    }

    @Test func adjustedTrackingFitsAfterResizingAtSensorEdge() throws {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .wide
        composer.setVisibleZoomHeight(0.25)
        let edge = PersonDetector.DetectedPerson(
            id: UUID(), boundingBox: CGRect(x: 0.85, y: 0.2, width: 0.1, height: 0.5),
            confidence: 0.95, timestamp: 0, poseKeypoints: nil,
            faceBoundingBox: nil, faceLandmarkRatios: nil)
        let crop = try #require(composer.compose(person: edge))
        #expect(abs(crop.size.height - 0.25) < 0.0001)
        #expect(abs(crop.origin.x + crop.size.width - 1) < 0.0001)
    }

    @Test func retiredFailedRenderCannotCancelNewZoom() async throws {
        enum RenderFailure: Error { case injected }
        let manager = CameraManager()
        let engine = try #require(manager.cropEngine)
        let frame = await manager.renderProgramFrame(crop: .fullFrame, timestamp: 0) {
            manager.cancelOperatorMotion() // a newer operator epoch while rendering
            engine.beginZoom(.pushIn, to: 0.25)
            throw RenderFailure.injected
        }
        #expect(frame == nil)
        #expect(engine.zoomDirection == .pushIn)
        #expect(!manager.isProgramHolding)
    }

    @Test func holdRecoveryCancelsZoomAndRequestsWideWithoutSnapping() throws {
        let manager = CameraManager()
        let engine = try #require(manager.cropEngine)
        engine.setTargetCrop(.init(center: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 0.5, height: 0.5)))
        engine.jumpToTarget()
        manager.commands.setTrackingOwnership(true)
        manager.applyLockOutcome(.acquired)
        engine.beginZoom(.pushIn, to: 0.25)
        let epoch = manager.commands.epoch
        manager.applyLockOutcome(.pullBackToWide)
        #expect(manager.activeMode == .wide)
        #expect(engine.zoomDirection == nil)
        #expect(!engine.hasZoomAdjustment)
        #expect(engine.currentCrop.size.height == 0.5)
        #expect(manager.controlStatus == "Subject lost · widening")
        #expect(manager.commands.epoch != epoch)
        // Automatic wide retains authority, explicit recovery revokes it.
        manager.returnToWide()
        manager.applyLockOutcome(.resumeTracking)
        #expect(manager.activeMode == .wide)
        #expect(engine.currentCrop == .fullFrame)
    }

    @Test func zoomSeedsVisibleShotAndIsIndependentOfFollowStiffness() throws {
        let slow = try engine()
        let fast = try engine()
        for engine in [slow, fast] {
            engine.setTargetCrop(.init(center: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 0.25, height: 0.25)))
            engine.beginZoom(.pushIn, to: 0.25)
            #expect(engine.adjustedHeight == 0.5)
        }
        slow.config.transitionSmoothing = 0.05
        fast.config.transitionSmoothing = 0.25
        for frame in 0...150 {
            let time = 100 + Double(frame) / 50
            for engine in [slow, fast] {
                engine.advanceZoom(now: time, aspect: 1)
                _ = engine.tickInterpolation(now: time)
            }
            #expect(abs(slow.currentCrop.size.height - fast.currentCrop.size.height) < 0.000001)
        }
        #expect(slow.currentCrop.size.height < 0.4)
    }

    @Test func stationarySubjectZoomsWhileSteadyFollowEmitsNil() throws {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .waistUp
        let subject = person(height: 0.6)
        composer.lockTarget(subject.id)
        let engine = try engine(height: 0.6)
        var accepted: CropEngine.CropRect?
        for frame in 0...50 {
            if let crop = composer.compose(person: subject, observationTimestamp: Double(frame) / 50) { accepted = crop }
        }
        let initial = try #require(accepted)
        #expect(composer.steadyBand != nil)
        engine.setTargetCrop(initial)
        engine.jumpToTarget()
        engine.zoomUsesTopAnchor = true
        let originalTop = engine.currentCrop.origin.y + engine.currentCrop.size.height
        engine.beginZoom(.pushIn, to: 0.25)
        for frame in 0...100 {
            let time = 100 + Double(frame) / 50
            engine.advanceZoom(now: time, aspect: composer.normalizedAspect)
            composer.setVisibleZoomHeight(engine.adjustedHeight)
            #expect(composer.compose(person: subject, observationTimestamp: time) == nil)
            _ = engine.tickInterpolation(now: time)
        }
        #expect(engine.currentCrop.size.height < initial.size.height)
        #expect(abs(engine.currentCrop.origin.y + engine.currentCrop.size.height - originalTop) < 0.0001)
        #expect(composer.manualLockedTargetID == subject.id)
        #expect(abs(try #require(composer.steadyBand).width - engine.currentCrop.size.width * composer.config.steadyBandWidth) < 0.0001)
        engine.clearZoomAdjustment()
        composer.reapplyFraming()
        #expect(composer.compose(person: subject) != nil)
        #expect(composer.manualLockedTargetID == subject.id)
    }

    @Test(arguments: [1.0, 9.0 / 16.0, 16.0 / 9.0])
    func zoomStaysInsideFrameAndFloorAtEdges(aspect: CGFloat) throws {
        let engine = try engine(center: CGPoint(x: 0.95, y: 0.95))
        engine.advanceZoom(now: 100, aspect: aspect)
        engine.beginZoom(.pushIn, to: 0.1)
        for frame in 0...1000 {
            let time = 101 + Double(frame) / 50
            engine.advanceZoom(now: time, aspect: aspect)
            let crop = engine.tickInterpolation(now: time).crop
            #expect(crop.origin.x >= 0 && crop.origin.y >= 0)
            #expect(crop.origin.x + crop.size.width <= 1.000001)
            #expect(crop.origin.y + crop.size.height <= 1.000001)
            #expect(crop.size.height >= 0.25)
            #expect(abs(crop.size.width / crop.size.height - aspect) < 0.000001)
        }
        #expect(engine.isZoomLimited)
        let height = engine.currentCrop.size.height
        engine.beginZoom(.pullOut, to: 0.8)
        for frame in 0...10 { engine.advanceZoom(now: 122 + Double(frame) / 50, aspect: aspect) }
        #expect(try #require(engine.adjustedHeight) > height)
        #expect(!engine.isZoomLimited)
    }

    private func settle(_ manager: CameraManager, start: Double = 100) {
        for frame in 0...1000 { manager.advanceShotMove(now: start + Double(frame) / 50) }
    }

    @Test func repeatedSameDirectionTapDoesNotRestartAnActiveRung() throws {
        let baseline = CameraManager()
        let repeated = CameraManager()
        for manager in [baseline, repeated] {
            manager.selectPreset(.stage(.wide))
            manager.setOperationMode(.manualCrop)
            manager.beginZoom(.pushIn)
        }
        for frame in 0...45 {
            let time = 100 + Double(frame) / 50
            baseline.advanceShotMove(now: time)
            repeated.advanceShotMove(now: time)
        }
        let before = try #require(repeated.cropEngine).currentCrop
        repeated.beginZoom(.pushIn)
        #expect(try #require(repeated.cropEngine).currentCrop == before)
        for frame in 46...400 {
            let time = 100 + Double(frame) / 50
            baseline.advanceShotMove(now: time)
            repeated.advanceShotMove(now: time)
            #expect(try #require(repeated.cropEngine).currentCrop == #require(baseline.cropEngine).currentCrop)
            #expect(repeated.zoomMoveDirection == baseline.zoomMoveDirection)
        }
        #expect(repeated.shotComposer.config.shotPreset == .fullBody)
    }

    @Test func tapsLandOnOneStageRungAndEnableOnlyLegalDirections() throws {
        let manager = CameraManager()
        let engine = try #require(manager.cropEngine)
        manager.shotComposer.config.cinematicFormat = .stage
        manager.selectPreset(.stage(.wide))
        manager.setOperationMode(.manualCrop)
        #expect(!manager.canBeginZoom(.pullOut))
        #expect(manager.canBeginZoom(.pushIn))
        manager.beginZoom(.pushIn)
        #expect(!manager.canBeginZoom(.pushIn))
        #expect(manager.canBeginZoom(.pullOut))
        manager.advanceShotMove(now: 100)
        manager.advanceShotMove(now: 100.1)
        #expect(engine.currentCrop.size.height > 0.98) // no preset-size jump
        manager.beginZoom(.pushIn) // repeated direction cannot skip a rung
        settle(manager, start: 100.1)
        #expect(manager.shotComposer.config.shotPreset == .fullBody)
        #expect(abs(engine.currentCrop.size.height - 0.8) < 0.00001)
        #expect(!engine.hasZoomAdjustment && manager.zoomMoveDirection == nil)
        #expect(manager.canBeginZoom(.pushIn) && manager.canBeginZoom(.pullOut))
        manager.beginZoom(.pushIn)
        settle(manager, start: 130)
        #expect(manager.shotComposer.config.shotPreset == .waistUp)
        #expect(abs(engine.currentCrop.size.height - 0.5) < 0.00001)
        #expect(!manager.canBeginZoom(.pushIn) && manager.canBeginZoom(.pullOut))
        manager.beginZoom(.pullOut)
        settle(manager, start: 160)
        #expect(manager.shotComposer.config.shotPreset == .fullBody)
        #expect(abs(engine.currentCrop.size.height - 0.8) < 0.00001)
        manager.beginZoom(.pullOut)
        settle(manager, start: 190)
        #expect(manager.shotComposer.config.shotPreset == .wide)
        #expect(manager.activeMode == .manualCrop)
        #expect(abs(engine.currentCrop.size.height - 1) < 0.00001)
    }

    @Test func oppositeTapReversesToOriginAndSafetyActionsCancel() throws {
        let manager = CameraManager()
        let engine = try #require(manager.cropEngine)
        manager.selectPreset(.stage(.wide))
        manager.beginZoom(.pushIn) // uncropped enters Manual, heads to Full Body
        #expect(manager.activeMode == .manualCrop)
        for frame in 0...50 { manager.advanceShotMove(now: 100 + Double(frame) / 50) }
        #expect(engine.currentCrop.size.height < 1 && engine.currentCrop.size.height > 0.8)
        let visible = engine.currentCrop.size.height
        manager.beginZoom(.pullOut)
        #expect(engine.currentCrop.size.height == visible)
        settle(manager, start: 102)
        #expect(manager.shotComposer.config.shotPreset == .wide)
        #expect(abs(engine.currentCrop.size.height - 1) < 0.00001)
        manager.beginZoom(.pushIn)
        manager.selectPreset(.stage(.waistUp))
        #expect(manager.zoomMoveDirection == nil && !engine.hasZoomAdjustment)
        manager.beginZoom(.pullOut)
        manager.returnToWide()
        #expect(manager.zoomMoveDirection == nil && !engine.hasZoomAdjustment)
        #expect(manager.activeMode == .wide && engine.currentCrop == .fullFrame)
        #expect(!manager.canBeginZoom(.pullOut) && manager.canBeginZoom(.pushIn))
    }

    @Test(arguments: [ShotComposer.Config.ShotPreset.fullBody, .waistUp])
    func reverseFromUncroppedReturnsToTheViewNotTheSelectedPreset(preset: ShotComposer.Config.ShotPreset) throws {
        let manager = CameraManager()
        manager.shotComposer.config.cinematicFormat = .stage
        let engine = try #require(manager.cropEngine)
        manager.selectPreset(.stage(preset))
        manager.returnToWide()
        manager.beginZoom(.pushIn)
        for frame in 0...50 { manager.advanceShotMove(now: 100 + Double(frame) / 50) }
        manager.beginZoom(.pullOut)
        settle(manager, start: 102)
        #expect(manager.activeMode == .wide)
        #expect(engine.currentCrop == .fullFrame)
        #expect(manager.shotComposer.config.shotPreset == preset)
        #expect(!manager.canBeginZoom(.pullOut))
    }

    @Test func webcamUsesOnlyWideAndTight() throws {
        let manager = CameraManager()
        let engine = try #require(manager.cropEngine)
        manager.shotComposer.config.cinematicFormat = .webcam
        manager.selectPreset(.webcam(.wide))
        #expect(manager.canBeginZoom(.pushIn) && !manager.canBeginZoom(.pullOut))
        manager.beginZoom(.pushIn)
        settle(manager)
        #expect(manager.shotComposer.config.webcamPreset == .tight)
        #expect(manager.canBeginZoom(.pullOut) && !manager.canBeginZoom(.pushIn))
        #expect(abs(engine.currentCrop.size.height - 0.5) < 0.00001)
        #expect(abs(manager.manualCropSize().height - 0.5) < 0.00001)
        manager.beginZoom(.pullOut)
        settle(manager, start: 130)
        #expect(manager.shotComposer.config.webcamPreset == .wide)
        #expect(manager.canBeginZoom(.pushIn) && !manager.canBeginZoom(.pullOut))
    }

    @Test func trackingMoveLandsOnComposerSizeWithoutResettingIdentity() throws {
        let manager = CameraManager()
        let composer = manager.shotComposer
        let engine = try #require(manager.cropEngine)
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .fullBody
        let subject = person(height: 0.4)
        composer.lockTarget(subject.id)
        manager.setOperationMode(.autoTracking)
        let initial = try #require(composer.compose(person: subject, observationTimestamp: 0))
        engine.setTargetCrop(initial)
        engine.jumpToTarget()
        for frame in 1...50 { _ = composer.compose(person: subject, observationTimestamp: Double(frame) / 50) }
        let destination = try #require(composer.destinationHeight(for: .stage(.waistUp)))
        manager.beginZoom(.pushIn)
        for frame in 0...1000 {
            let time = 100 + Double(frame) / 50
            manager.advanceShotMove(now: time)
            if let crop = composer.compose(person: subject, observationTimestamp: time) { engine.setTargetCrop(crop) }
            _ = engine.tickInterpolation(now: time)
            #expect(composer.manualLockedTargetID == subject.id)
        }
        #expect(composer.config.shotPreset == .waistUp)
        #expect(abs(engine.currentCrop.size.height - destination) < 0.00001)
        #expect(!engine.hasZoomAdjustment)
        #expect(manager.activeMode == .autoTracking)
    }

    @Test func manualAndPanExposeTheSameHardQualityBound() throws {
        let engine = try engine()
        engine.qualityFloor = .init(minCropHeightFraction: 0.8)
        let requested = CropEngine.CropRect(center: .init(x: 0.9, y: 0.9), size: .init(width: 0.5, height: 0.5))
        engine.setTargetCrop(requested)
        #expect(engine.isZoomLimited && engine.targetCrop.size.height == 0.8)
        engine.placePan(center: requested.center, baseSize: requested.size)
        #expect(engine.isZoomLimited && engine.currentCrop.size.height == 0.8)
        #expect(engine.currentCrop.origin.x + engine.currentCrop.size.width <= 1)
        engine.placePan(center: requested.center, baseSize: .init(width: 1, height: 1))
        #expect(!engine.isZoomLimited)
    }

    @Test func cancelStopsSizeWithoutLandingOnTheDestination() throws {
        let engine = try engine()
        engine.beginZoom(.pushIn, to: 0.25)
        for frame in 0...100 { engine.advanceZoom(now: 100 + Double(frame) / 50, aspect: 1) }
        engine.endZoom()
        let stopped = engine.currentCrop
        for frame in 0...100 { engine.advanceZoom(now: 103 + Double(frame) / 50, aspect: 1) }
        #expect(engine.currentCrop == stopped)
        #expect(engine.zoomDirection == nil && engine.hasZoomAdjustment)
    }

    @Test func panRetainsPhaseAcrossZeroTravelAndBothDwells() {
        let manager = CameraManager()
        manager.shotComposer.config.autoPanSpeed = 0.03
        _ = manager.advanceAutoPan(now: 100, width: 0.5)
        var rightReached: Double?
        for i in 1...100 {
            let t = 100 + Double(i) * 0.1
            if manager.advanceAutoPan(now: t, width: 0.5) >= 0.75 - 0.00001 { rightReached = t; break }
        }
        let right = rightReached ?? 0
        #expect(right > 100)
        // Dwell survives a mid-dwell envelope change and full-width frame.
        #expect(abs(manager.advanceAutoPan(now: right + 0.2, width: 0.4) - 0.8) < 0.0001)
        #expect(manager.advanceAutoPan(now: right + 0.3, width: 1) == 0.5)
        #expect(abs(manager.advanceAutoPan(now: right + 0.4, width: 0.4) - 0.8) < 0.0001)
        var leftReached: Double?
        for i in 1...160 {
            let t = right + 0.4 + Double(i) * 0.1
            if manager.advanceAutoPan(now: t, width: 0.4) <= 0.2 + 0.00001 { leftReached = t; break }
        }
        let left = leftReached ?? 0
        #expect(left > right)
        #expect(abs(manager.advanceAutoPan(now: left + 0.2, width: 0.6) - 0.3) < 0.0001)
        #expect(manager.advanceAutoPan(now: left + 0.3, width: 1) == 0.5)
        #expect(abs(manager.advanceAutoPan(now: left + 0.4, width: 0.6) - 0.3) < 0.0001)
    }

    @Test func panZoomHasNoSizeJumpAndIdlePanRetainsConstantSpeed() throws {
        let manager = CameraManager()
        manager.shotComposer.config.autoPanSpeed = 0.02
        let engine = try engine()
        var prior: CropEngine.CropRect?
        engine.beginZoom(.pushIn, to: 0.25)
        for frame in 0...100 {
            let t = 100 + Double(frame) / 50
            engine.advanceZoom(now: t, aspect: 1)
            let width = try #require(engine.adjustedHeight)
            let x = manager.advanceAutoPan(now: t, width: width)
            engine.placePan(center: CGPoint(x: x, y: 0.5), baseSize: CGSize(width: 0.5, height: 0.5))
            let crop = engine.tickInterpolation(now: t).crop
            if let prior {
                #expect(abs(crop.center.x - prior.center.x) <= 0.09 / 50 + 0.00001)
                #expect(abs(log(crop.size.height / prior.size.height)) <= 0.18 / 50 + 0.00001)
            }
            prior = crop
        }
        let a = manager.advanceAutoPan(now: 103, width: 0.5)
        let b = manager.advanceAutoPan(now: 103.02, width: 0.5)
        let c = manager.advanceAutoPan(now: 103.04, width: 0.5)
        #expect(abs((b - a) - 0.5 * 0.06 * 0.02) < 0.000001)
        #expect(abs((c - b) - (b - a)) < 0.000001)
    }

    @Test(arguments: [false, true])
    func shotMoveDuringEitherPanDwellKeepsTheVisibleEdge(left: Bool) throws {
        let manager = CameraManager()
        manager.shotComposer.config.cinematicFormat = .stage
        manager.shotComposer.config.autoPanSpeed = 0.03
        let engine = try #require(manager.cropEngine)
        manager.selectPreset(.stage(.fullBody))
        manager.setOperationMode(.autoPan)
        engine.setTargetCrop(.init(center: .init(x: 0.5, y: 0.5), size: manager.manualCropSize()))
        engine.jumpToTarget()
        var time = 100.0
        var reached = false
        for _ in 0...1500 {
            let x = manager.advanceAutoPan(now: time, width: 0.8)
            engine.placePan(center: .init(x: x, y: 0.5), baseSize: manager.manualCropSize())
            if left ? x <= 0.400001 : x >= 0.599999 { reached = true; break }
            time += 0.02
        }
        #expect(reached)
        manager.beginZoom(.pushIn)
        for frame in 0...50 {
            let now = time + Double(frame) / 50
            manager.advanceShotMove(now: now)
            let size = manager.manualCropSize()
            let x = manager.advanceAutoPan(now: now, width: size.width)
            engine.placePan(center: .init(x: x, y: 0.5), baseSize: size)
            let crop = engine.tickInterpolation(now: now).crop
            #expect(left ? abs(crop.origin.x) < 0.000001 : abs(crop.origin.x + crop.size.width - 1) < 0.000001)
        }
        #expect(engine.currentCrop.size.height < 0.8)
        settle(manager, start: time + 1)
        #expect(manager.shotComposer.config.shotPreset == .waistUp)
        #expect(manager.activeMode == .autoPan)
        #expect(abs(manager.manualCropSize().height - 0.5) < 0.00001)
    }

    @Test func failedRenderKeepsPriorProgramAndNeverInventsFirstFrame() async throws {
        enum RenderFailure: Error { case injected }
        let manager = CameraManager()
        let first = await manager.renderProgramFrame(crop: .fullFrame, timestamp: 0) { throw RenderFailure.injected }
        #expect(first == nil)
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        let rendered = try #require(buffer)
        let good = await manager.renderProgramFrame(crop: .fullFrame, timestamp: 1) { rendered }
        #expect(good === rendered)
        for i in 0..<5 {
            let held = await manager.renderProgramFrame(crop: .fullFrame, timestamp: Double(i + 2)) { throw RenderFailure.injected }
            #expect(held === rendered)
        }
        #expect(manager.isProgramHolding)
        manager.stopCapture()
        #expect(manager.selectProgramBuffer(rendered: nil) == nil)
    }

    private func person(height: CGFloat = 0.70) -> PersonDetector.DetectedPerson {
        PersonDetector.DetectedPerson(
            id: UUID(),
            boundingBox: CGRect(x: 0.40, y: 0.10, width: 0.20, height: height),
            confidence: 0.95,
            timestamp: 0,
            poseKeypoints: nil,
            faceBoundingBox: nil,
            faceLandmarkRatios: nil
        )
    }

    private func cropHeight(
        preset: ShotComposer.Config.ShotPreset,
        profile: ShotComposer.Config.FrameProfile,
        subject: PersonDetector.DetectedPerson
    ) throws -> CGFloat {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.frameProfile = profile
        composer.config.shotPreset = preset
        return try #require(composer.compose(person: subject)?.size.height)
    }

    private func stagePerson(y: CGFloat, height: CGFloat) -> PersonDetector.DetectedPerson {
        PersonDetector.DetectedPerson(
            id: UUID(), boundingBox: CGRect(x: 0.4, y: y, width: 0.2, height: height),
            confidence: 0.95, timestamp: 0, poseKeypoints: nil,
            faceBoundingBox: nil, faceLandmarkRatios: nil
        )
    }

    @Test(arguments: [ShotComposer.Config.ShotPreset.fullBody, .waistUp])
    func stageHeadroomUsesFloorAdjustedOutputHeight(preset: ShotComposer.Config.ShotPreset) throws {
        let composer = ShotComposer()
        composer.config.shotPreset = preset
        composer.config.steadyFollowingEnabled = false
        composer.qualityFloorHeightFraction = 0.65
        let subject = stagePerson(y: 0.45, height: 0.20)

        let crop = try #require(composer.compose(person: subject))
        let headroom = (crop.origin.y + crop.size.height - subject.boundingBox.maxY) / crop.size.height
        #expect(abs(crop.size.height - 0.65) < 0.0001)
        #expect(abs(headroom - composer.config.headroom(for: preset)) < 0.0001)
        #expect(crop.origin.y <= subject.boundingBox.minY)
    }

    @Test func editingHeadroomMovesAStationaryWaistUpShot() throws {
        let composer = ShotComposer()
        composer.config.shotPreset = .waistUp
        composer.config.steadyFollowingEnabled = false
        composer.qualityFloorHeightFraction = 0.65
        let subject = stagePerson(y: 0.45, height: 0.20)
        let first = try #require(composer.compose(person: subject))

        composer.config.waistUpHeadroom = 0.15
        let changed = try #require(composer.compose(person: subject))
        #expect(changed.origin.y > first.origin.y)
        #expect(abs((changed.origin.y + changed.size.height - subject.boundingBox.maxY) / changed.size.height - 0.15) < 0.0001)
    }

    @Test func fullBodyKeepsFeetWhenRequestedHeadroomBarelyFits() throws {
        let composer = ShotComposer()
        composer.config.shotPreset = .fullBody
        composer.config.steadyFollowingEnabled = false
        // A close subject plus the 85% context-shot cap leaves less space
        // than the requested headroom and shoe margin combined.
        let subject = stagePerson(y: 0.1, height: 0.80)
        let crop = try #require(composer.compose(person: subject))
        #expect(crop.origin.y <= subject.boundingBox.minY + 0.0001)
        #expect(crop.origin.y + crop.size.height >= subject.boundingBox.maxY - 0.0001)
    }

    @Test func stageHeadroomPersistsSeparatelyAndResets() throws {
        let suite = "AlfieHeadroomTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var edited = ShotComposer.Config()
        edited.setHeadroom(0.12, for: .fullBody, defaults: defaults)
        edited.setHeadroom(0.18, for: .waistUp, defaults: defaults)
        var restored = ShotComposer.Config()
        restored.restoreStageHeadroom(from: defaults)
        #expect(abs(restored.fullBodyHeadroom - 0.12) < 0.0001)
        #expect(abs(restored.waistUpHeadroom - 0.18) < 0.0001)

        restored.setHeadroom(0.90, for: .waistUp, defaults: defaults)
        #expect(restored.waistUpHeadroom == ShotComposer.Config.stageHeadroomRange.upperBound)
        restored.resetStageHeadroom(defaults: defaults)
        var reset = ShotComposer.Config()
        reset.restoreStageHeadroom(from: defaults)
        #expect(reset.fullBodyHeadroom == ShotComposer.Config.defaultFullBodyHeadroom)
        #expect(reset.waistUpHeadroom == ShotComposer.Config.defaultWaistUpHeadroom)
    }

    @Test func stagePresetNamesDescribeTheActiveFormat() {
        var config = ShotComposer.Config()
        config.cinematicFormat = .stage
        config.shotPreset = .waistUp
        #expect(config.activeFramingTitle == "Waist Up")

        config.cinematicFormat = .webcam
        config.webcamPreset = .tight
        #expect(config.activeFramingTitle == "Tight")
    }

    @Test func tallStageSubjectNeverReversesPresetOrderAcrossProfiles() throws {
        // A close/tall subject exercises the maximum-crop caps where the
        // previous regression made Full Body wider than Wide. Equality is
        // permitted when a physical crop cap is reached; inversion is not.
        let subject = person()
        for profile in ShotComposer.Config.FrameProfile.allCases {
            let wide = try cropHeight(preset: .wide, profile: profile, subject: subject)
            let fullBody = try cropHeight(preset: .fullBody, profile: profile, subject: subject)
            let waistUp = try cropHeight(preset: .waistUp, profile: profile, subject: subject)

            #expect(wide + 0.0001 >= fullBody,
                    "Wide must not crop tighter than Full Body for \(profile)")
            #expect(fullBody + 0.0001 >= waistUp,
                    "Full Body must not crop tighter than Waist Up for \(profile)")
        }
    }

    @Test func steadyFollowBandScalesToTheVisibleProgramCrop() throws {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .waistUp
        let subject = person(height: 0.40)

        // The first observation applies the initial framing; the next twelve
        // distinct observations settle the Steady Follow state and establish
        // the displayed band. The band is an operator-facing amount
        // of movement inside the *program* view, so it must shrink with a
        // tighter crop instead of remaining a fixed fraction of the source.
        var crop: CropEngine.CropRect?
        for frame in 0..<14 {
            crop = composer.compose(
                person: subject,
                isFresh: true,
                observationTimestamp: Double(frame) / 50.0
            )
        }

        let settledCrop = try #require(crop)
        let band = try #require(composer.steadyBand)
        let maximumViewportRelativeWidth = settledCrop.size.width * composer.config.steadyBandWidth
        #expect(
            band.width <= maximumViewportRelativeWidth + 0.0001,
            "the source-space band must not consume more than its configured share of the program crop"
        )
    }

    @Test(arguments: [25.0, 50.0, 60.0])
    func steadyFollowSettlesByCaptureTimeAtEverySupportedRate(fps: Double) throws {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .waistUp
        let subject = person(height: 0.40)

        // The first observation applies the initial crop. Measure from the
        // first actual settle observation so rates can differ only by their
        // sampling granularity, not by the number of compositor invocations.
        _ = composer.compose(person: subject, isFresh: true, observationTimestamp: 0)
        let firstSettleObservation = 1.0 / fps
        var settledAt: Double?
        for frame in 1...Int(fps) {
            let timestamp = Double(frame) / fps
            _ = composer.compose(
                person: subject,
                isFresh: true,
                observationTimestamp: timestamp
            )
            if composer.steadyBand != nil {
                settledAt = timestamp
                break
            }
        }

        let time = try #require(settledAt)
        let elapsed = time - firstSettleObservation
        // The intended settle period is 12/50 s. A sampled detector may cross
        // it up to one observation later, but must not become a rate-dependent
        // 12-frame wait (0.48 s at 25 fps or 0.20 s at 60 fps).
        #expect(elapsed >= 0.24 - 0.0001)
        #expect(elapsed <= 0.24 + (1.0 / fps) + 0.0001)
    }

    @Test(arguments: [25.0, 50.0, 60.0])
    func bandExitRequiresFreshElapsedEvidence(fps: Double) throws {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .waistUp
        let still = person(height: 0.40)
        for frame in 0...Int(fps) {
            _ = composer.compose(person: still, observationTimestamp: Double(frame) / fps)
        }
        #expect(composer.steadyBand != nil)
        let moving = PersonDetector.DetectedPerson(
            id: still.id, boundingBox: still.boundingBox.offsetBy(dx: 0.10, dy: 0),
            confidence: still.confidence, timestamp: still.timestamp, poseKeypoints: nil,
            faceBoundingBox: nil, faceLandmarkRatios: nil)
        let start = 1.0 + 1.0 / fps
        _ = composer.compose(person: moving, observationTimestamp: start)
        // Re-displaying one observation must never confirm an exit.
        for _ in 0..<10 {
            _ = composer.compose(person: moving, isFresh: false, observationTimestamp: start)
        }
        #expect(composer.steadyBand != nil)
        var releasedAt: Double?
        for frame in 1...Int(fps) {
            let time = start + Double(frame) / fps
            _ = composer.compose(person: moving, observationTimestamp: time)
            if composer.steadyBand == nil { releasedAt = time; break }
        }
        let elapsed = try #require(releasedAt) - start
        #expect(elapsed >= 0.04 - 0.0001)
        #expect(elapsed <= 0.04 + 1.0 / fps + 0.0001)
    }

    @Test func validationPlaybackUsesAbsolutePresentationTime() {
        let start = 100.0
        #expect(CameraManager.playbackDelay(
            sourceTimestamp: 42.0, firstTimestamp: 42.0, playbackStart: start, now: start
        ) == 0)

        // 400 ms of source time must be scheduled from the original playback
        // epoch. Accounting for 100 ms spent processing prior frames leaves
        // exactly 300 ms, rather than a new 400 ms delay from "now".
        #expect(abs(CameraManager.playbackDelay(
            sourceTimestamp: 42.4, firstTimestamp: 42.0, playbackStart: start, now: 100.1
        ) - 0.3) < 0.000_001)

        // Slow processing never adds a compensating sleep, and malformed
        // non-monotonic timestamps cannot schedule a frame before playback.
        #expect(CameraManager.playbackDelay(
            sourceTimestamp: 42.4, firstTimestamp: 42.0, playbackStart: start, now: 100.8
        ) == 0)
        #expect(CameraManager.playbackDelay(
            sourceTimestamp: 41.9, firstTimestamp: 42.0, playbackStart: start, now: start
        ) == 0)
    }
}
