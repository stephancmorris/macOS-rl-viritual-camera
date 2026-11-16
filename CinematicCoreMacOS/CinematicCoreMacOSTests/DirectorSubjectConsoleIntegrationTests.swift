import CoreGraphics
import CoreVideo
import Foundation
import Testing
import Vision
@testable import Alfie

@MainActor struct DirectorSubjectConsoleIntegrationTests {
    private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    private func rig() throws -> (ShowCoordinator, DirectorController) {
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { 100 }
        show.channelA.setRunningForTesting(true)
        let b = show.addChannel(.b); b.setRunningForTesting(true)
        for channel in [show.channelA, b] {
            var buffer: CVPixelBuffer?
            #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 9, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
            channel.setLatestRenderedFrameForTesting(.init(channelID: channel.channelID, revisions: channel.revisions,
                sourceTimestamp: 100, processingStartedAt: 100, renderedAt: 100,
                crop: .init(center: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 1, height: 1)),
                outputSize: CGSize(width: 16, height: 9), isRepeat: false, pixelBuffer: try #require(buffer)))
        }
        let controller = DirectorController(show: show, ticker: Ticker(), clock: { 100 }, log: { _ in })
        controller.attach()
        return (show, controller)
    }

    @Test func aSingleBoundClickArmsOrdinaryAcquisitionAndRecordsNomination() throws {
        let (show, controller) = try rig()
        let pick = try #require(controller.directorSection.subjectPicks[.b])
        #expect(pick.phase == .unavailable && pick.canOverride && pick.selectedCandidateID == nil)
        let request = try #require(pick.overrideRequest(at: CGPoint(x: 0.4, y: 0.6)))
        let before = controller.nominationRevision
        #expect(controller.overrideSubject(request) == .accepted)
        #expect(show.channel(.b)?.operatorGestureInProgress == true)
        #expect(controller.nominationRevision == before + 1)
        #expect(controller.appliedEvents.contains(.nominationChanged))
        #expect(controller.directorSection.subjectPicks[.b]?.selectedCandidateID == nil)
        #expect(controller.overrideSubject(request) != .accepted)
    }

    /// A live identity veto holds the lock while the vetoed person is still a
    /// candidate. The pick reads like any hold with the subject out of sight.
    @Test func aVetoHeldTrackIsNotTheSelectedSubject() throws {
        let (show, controller) = try rig()
        let channel = try #require(show.channel(.b))
        channel.personDetector.updateTracking(
            rectObservations: [VNHumanObservation(boundingBox: CGRect(x: 0.45, y: 0.25, width: 0.07, height: 0.30))],
            poseObservations: [], faceObservations: [], timestamp: 100)
        var person = try #require(channel.personDetector.detectedPersons.first)
        person = PersonDetector.DetectedPerson(id: person.id, boundingBox: person.boundingBox, confidence: 1,
            timestamp: 100, poseKeypoints: nil,
            faceBoundingBox: CGRect(x: 0.47, y: 0.48, width: 0.03, height: 0.04), faceLandmarkRatios: nil)
        let composer = channel.shotComposer
        var requests: [IdentityEvidenceRequest] = []
        composer.identityVetoEnabledForTesting = true
        composer.identityEvidenceSchedulerForTesting = { requests.append($0) }
        composer.lockTarget(person.id)
        composer.forceTrackingForTesting(readyGallery: true)
        controller.tick()
        let tracking = try #require(controller.directorSection.subjectPicks[.b])
        #expect(tracking.selectedCandidateID == person.id && tracking.phase == .tracking)

        var observation: UInt64 = 0
        func tick(ambiguous: Bool) {
            observation += 1
            _ = composer.tick(detections: [person], timestamp: 100, pixelBuffer: nil, observationID: observation,
                              observationTimestamp: 100, lockAmbiguityOpen: ambiguous)
        }
        tick(ambiguous: true)
        for _ in 0..<3 {
            composer.finishIdentityEvidence(try #require(requests.last), tier: .strongMismatch)
            tick(ambiguous: false)
        }
        #expect(composer.isIdentityVetoHeld)
        controller.tick()
        let held = try #require(controller.directorSection.subjectPicks[.b])
        #expect(held.candidates.map(\.id) == [person.id])
        #expect(held.selectedCandidateID == nil && held.phase == .recovering)
    }

    @Test(arguments: ["source", "selection", "route", "point", "program", "stop", "mode"])
    func staleOrProtectedRequestsRefuseWithoutAnAcquisition(_ change: String) throws {
        let (show, controller) = try rig()
        let pick = try #require(controller.directorSection.subjectPicks[.b])
        var request = try #require(pick.overrideRequest(at: CGPoint(x: 0.4, y: 0.6)))
        switch change {
        case "source": request = .init(channel: .b, sourceGeneration: request.sourceGeneration + 1,
            selectionRevision: request.selectionRevision, routeGeneration: request.routeGeneration, point: request.point)
        case "selection": request = .init(channel: .b, sourceGeneration: request.sourceGeneration,
            selectionRevision: request.selectionRevision + 1, routeGeneration: request.routeGeneration, point: request.point)
        case "route": request = .init(channel: .b, sourceGeneration: request.sourceGeneration,
            selectionRevision: request.selectionRevision, routeGeneration: request.routeGeneration + 1, point: request.point)
        case "point": request = .init(channel: .b, sourceGeneration: request.sourceGeneration,
            selectionRevision: request.selectionRevision, routeGeneration: request.routeGeneration, point: CGPoint(x: .nan, y: 0.5))
        case "program":
            let program = try #require(controller.directorSection.subjectPicks[.a])
            request = .init(channel: .a, sourceGeneration: program.sourceGeneration, selectionRevision: program.selectionRevision,
                routeGeneration: program.routeGeneration, point: request.point)
        case "stop": show.channel(.b)?.setRunningForTesting(false)
        case "mode": _ = show.dispatch(show.makeCommand(.setMode(.manualCrop)))
        default: break
        }
        let before = controller.nominationRevision
        #expect(controller.overrideSubject(request) != .accepted)
        #expect(controller.nominationRevision == before)
        #expect(show.channel(.b)?.operatorGestureInProgress == false)
    }

    @Test func retargetUsesOneNormalCommandAndRetainsLockUntilRoiConfirms() throws {
        let (show, controller) = try rig()
        let camera = try #require(show.channel(.b))
        let old = UUID(); camera.shotComposer.lockTarget(old)
        let pick = try #require(controller.sampleSectionForConsole().subjectPicks[.b])
        let request = try #require(pick.overrideRequest(at: CGPoint(x: 0.7, y: 0.5)))
        #expect(controller.overrideSubject(request) == .accepted)
        #expect(camera.manualLockedTargetID == old && camera.operatorGestureInProgress)
        #expect(controller.directorSection.subjectPicks[.b]?.phase != .tracking)
    }

    @Test func aSingleInputKeepsItsExistingManualNominationPath() throws {
        let (show, controller) = try rig()
        show.removeChannel(.b)
        let pick = try #require(controller.sampleSectionForConsole().subjectPicks[.a])
        #expect(pick.canOverride && show.previewChannel == nil)
        let request = try #require(pick.overrideRequest(at: CGPoint(x: 0.5, y: 0.5)))
        #expect(controller.overrideSubject(request) == .accepted)
        #expect(show.channelA.operatorGestureInProgress)
    }

    @Test func explicitStudyConfigurationDoesNotGrantAuthorityOrBootstrapANomination() throws {
        let (show, controller) = try rig()
        let configuration = DirectorSubjectDiscovery.Configuration(revision: 1, maximumStartsPerSecond: 1,
            maximumResultAge: 2, maximumStableSpeed: 0.1,
            selectorParameters: .init(lecternZone: .init(minX: 0, minY: 0, maxX: 1, maxY: 1),
                maximumCentreDistance: 0.5, minimumStableDuration: 0, maximumObservationAge: 2, maximumSampleAge: 2),
            positionHintZone: nil)
        controller.configureSubjectDiscoveryForStudy(configuration, on: .b)
        #expect(show.channel(.b)?.currentDetectionPlan(detectionRunsThisFrame: true).mode == .off)
        #expect(controller.authority.level == .off && show.channel(.b)?.manualLockedTargetID == nil)
    }

    @Test func unsupportedSourceGeometryNeverBecomesASelectedPerson() throws {
        let (show, controller) = try rig()
        show.channel(.b)?.setLatestRenderedFrameForTesting(nil)
        #expect(controller.sampleSectionForConsole().subjectPicks[.b] == nil)
        controller.detach()
        let request = DirectorSubjectOverrideRequest(channel: .b, sourceGeneration: 0, selectionRevision: 0,
            routeGeneration: 0, point: CGPoint(x: 0.5, y: 0.5))
        #expect(controller.overrideSubject(request) != .accepted)
    }
}
