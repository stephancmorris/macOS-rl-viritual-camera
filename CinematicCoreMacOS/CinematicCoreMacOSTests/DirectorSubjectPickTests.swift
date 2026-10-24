import Combine
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct DirectorSubjectPickTests {
    private let person = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func pick(source: UInt64 = 7, selection: UInt64 = 2, route: UInt64 = 3,
                      phase: DirectorSubjectPick.Phase = .tracking,
                      provenance: DirectorSubjectPick.Provenance? = .operatorNomination,
                      canOverride: Bool = true) -> DirectorSubjectPick {
        .init(channel: .b, sourceGeneration: source, selectionRevision: selection, routeGeneration: route,
              phase: phase, selectedCandidateID: person,
              candidates: [.init(id: person, bounds: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))],
              provenance: provenance, canOverride: canOverride)
    }

    private final class Controller: ObservableObject, DirectorConsoleControlling {
        @Published var directorSection = NextShotStatus.DirectorSection.atLaunch(qualified: .none)
        var requests: [DirectorSubjectOverrideRequest] = []
        var legacyCalls = 0
        func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult { .refused("not qualified") }
        func handToAlfie() -> DirectorControlResult { .refused("not qualified") }
        func takeOver() {}
        func cancelNextCut() {}
        func advanceSegment() {}
        func overrideSubject(on channel: ChannelID, at point: CGPoint) { legacyCalls += 1 }
        func overrideSubject(_ request: DirectorSubjectOverrideRequest) -> DirectorControlResult {
            requests.append(request)
            return .accepted
        }
    }

    private final class LegacyController: DirectorConsoleControlling {
        var directorSection = NextShotStatus.DirectorSection.atLaunch(qualified: .none)
        var legacyCalls = 0
        func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult { .refused("not qualified") }
        func handToAlfie() -> DirectorControlResult { .refused("not qualified") }
        func takeOver() {}
        func cancelNextCut() {}
        func advanceSegment() {}
        func overrideSubject(on channel: ChannelID, at point: CGPoint) { legacyCalls += 1 }
    }

    @Test func requestsCarryThePaintedSourceSelectionAndRouteBinding() throws {
        let displayed = pick()
        let request = try #require(displayed.overrideRequest(at: CGPoint(x: 0.4, y: 0.6)))
        #expect(request.channel == .b && request.sourceGeneration == 7)
        #expect(request.selectionRevision == 2 && request.routeGeneration == 3)
        #expect(request.matches(displayed))
        #expect(!request.matches(pick(source: 8)))
        #expect(!request.matches(pick(selection: 3)))
        #expect(!request.matches(pick(route: 4)))
        #expect(!request.matches(pick(canOverride: false)))
        #expect(pick(canOverride: false).overrideRequest(at: .zero) == nil)
        #expect(displayed.overrideRequest(at: CGPoint(x: CGFloat.nan, y: 0.5)) == nil)
        #expect(displayed.overrideRequest(at: CGPoint(x: 0.5, y: 1.01)) == nil)
    }

    @Test func invalidCandidatesNeverBecomePaintedTargetsOrOverrideRequests() {
        let badBounds: [CGRect] = [
            CGRect(x: CGFloat.nan, y: 0, width: 0.2, height: 0.2),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 0.2),
            CGRect(x: -0.1, y: 0, width: 0.2, height: 0.2),
            CGRect(x: 0.9, y: 0, width: 0.2, height: 0.2),
            CGRect(x: 0, y: 0, width: 0, height: 0.2)
        ]
        for bounds in badBounds {
            let value = DirectorSubjectPick(channel: .b, sourceGeneration: 7, selectionRevision: 2,
                routeGeneration: 3, phase: .tracking, selectedCandidateID: person,
                candidates: [.init(id: person, bounds: bounds)], provenance: .operatorNomination,
                canOverride: true)
            #expect(!value.isValid)
            #expect(DirectorSubjectPickPresentation(pick: value).candidates.isEmpty)
            #expect(DirectorSubjectPickPresentation(pick: value).line == "Subject view unavailable")
            #expect(value.overrideRequest(at: .zero) == nil)
        }
        let candidate = pick().candidates[0]
        let duplicate = DirectorSubjectPick(channel: .b, sourceGeneration: 7, selectionRevision: 2,
            routeGeneration: 3, phase: .tracking, selectedCandidateID: person,
            candidates: [candidate, candidate], provenance: .operatorNomination, canOverride: true)
        #expect(!duplicate.isValid)
        let excessive = DirectorSubjectPick(channel: .b, sourceGeneration: 7, selectionRevision: 2,
            routeGeneration: 3, phase: .unavailable, selectedCandidateID: nil,
            candidates: (0...DirectorSubjectPick.maximumCandidates).map { _ in
                .init(id: UUID(), bounds: candidate.bounds)
            }, provenance: nil, canOverride: true)
        #expect(!excessive.isValid)
        #expect(DirectorSubjectPickPresentation(pick: excessive).candidates.isEmpty)
    }

    @Test func ambiguityAndMissingCandidatesNeverDisplayASelectedPerson() {
        for phase in [DirectorSubjectPick.Phase.ambiguous, .unavailable, .lost] {
            #expect(!pick(phase: phase).isValid)
        }
        let value = DirectorSubjectPick(channel: .b, sourceGeneration: 7, selectionRevision: 2,
            routeGeneration: 3, phase: .ambiguous, selectedCandidateID: nil,
            candidates: pick().candidates, provenance: nil, canOverride: true)
        #expect(value.isValid && value.selectedCandidate == nil)
        #expect(DirectorSubjectPickPresentation(pick: value).line == "More than one possible subject")
        let missing = DirectorSubjectPick(channel: .b, sourceGeneration: 7, selectionRevision: 2,
            routeGeneration: 3, phase: .tracking, selectedCandidateID: UUID(),
            candidates: pick().candidates, provenance: .operatorNomination, canOverride: true)
        #expect(!missing.isValid && missing.selectedCandidate == nil)
    }

    @Test func suggestionsAcquisitionAndRecoveryRemainDistinctFromTracking() {
        let suggested = DirectorSubjectPickPresentation(pick: pick(phase: .suggested,
            provenance: .alfie(.centralPresenter)))
        let acquiring = DirectorSubjectPickPresentation(pick: pick(phase: .acquiring,
            provenance: .alfie(.positionHint)))
        let recovering = DirectorSubjectPickPresentation(pick: pick(phase: .recovering))
        #expect(suggested.line == "Alfie's pick · select to acquire")
        #expect(suggested.reason == "Central presenter")
        #expect(acquiring.line == "Alfie's pick · acquiring")
        #expect(acquiring.reason == "Position hint")
        #expect(recovering.line == "Recovering subject · last position")
        #expect(DirectorSubjectPickPresentation(pick: pick()).line == "Your subject · tracking")
        #expect(![suggested.line, acquiring.line, recovering.line].contains { $0.localizedCaseInsensitiveContains("ready") })
    }

    @Test func sourceCoordinatesRoundTripAndExcludeLetterboxAndMalformedInput() throws {
        let view = CGSize(width: 600, height: 400), image = CGSize(width: 1920, height: 1080)
        let rect = try #require(DirectorSourceCoordinates.rect(pick().candidates[0].bounds,
            viewSize: view, imageSize: image))
        #expect(rect == CGRect(x: 150, y: 115.625, width: 300, height: 168.75))
        #expect(DirectorSourceCoordinates.normalizedPoint(CGPoint(x: rect.midX, y: rect.midY),
            viewSize: view, imageSize: image) == CGPoint(x: 0.5, y: 0.5))
        #expect(DirectorSourceCoordinates.normalizedPoint(CGPoint(x: 300, y: 10),
            viewSize: view, imageSize: image) == nil)
        #expect(DirectorSourceCoordinates.normalizedPoint(CGPoint(x: 300, y: 390),
            viewSize: view, imageSize: image) == nil)
        #expect(DirectorSourceCoordinates.normalizedPoint(.zero,
            viewSize: view, imageSize: .zero) == nil)
        #expect(DirectorSourceCoordinates.normalizedPoint(CGPoint(x: CGFloat.nan, y: 200),
            viewSize: view, imageSize: image) == nil)
        #expect(DirectorSourceCoordinates.rect(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 1),
            viewSize: view, imageSize: image) == nil)
    }

    @Test func proxyRejectsAnOldSourceRouteOrSelectionWithoutCallingAnyControllerVerb() throws {
        let controller = Controller()
        controller.directorSection.subjectPicks[.b] = pick()
        let request = try #require(pick().overrideRequest(at: CGPoint(x: 0.5, y: 0.5)))
        let proxy = LiveDirectorConsoleProxy(enabled: true, controller: { controller })
        for replacement in [pick(source: 8), pick(selection: 3), pick(route: 4), pick(canOverride: false)] {
            controller.directorSection.subjectPicks[.b] = replacement
            #expect(proxy.overrideSubject(request) == .refused("The subject view changed. Choose again."))
        }
        #expect(controller.requests.isEmpty && controller.legacyCalls == 0)
        controller.directorSection.subjectPicks[.b] = pick()
        #expect(proxy.overrideSubject(request) == .accepted)
        #expect(controller.requests == [request] && controller.legacyCalls == 0)
    }

    @Test func legacyControllersAndUnavailableProxiesCannotDowngradeABoundRequest() throws {
        let request = try #require(pick().overrideRequest(at: .zero))
        let legacy = LegacyController()
        #expect(legacy.overrideSubject(request) == .refused("Subject selection is unavailable"))
        #expect(legacy.legacyCalls == 0)
        var reads = 0
        let proxy = LiveDirectorConsoleProxy(enabled: false, controller: { reads += 1; return legacy })
        #expect(proxy.overrideSubject(request) == .refused("Subject selection is unavailable"))
        #expect(reads == 0)
    }

    @Test func oneClickEmitsOneBoundIntentAndInvalidClicksNeverReachTheOwner() {
        var requests: [DirectorSubjectOverrideRequest] = []
        let view = DirectorSubjectPickView(pick: pick(), imageSize: CGSize(width: 1920, height: 1080),
            onOverride: { requests.append($0); return .accepted })
        #expect(view.nominate(at: CGPoint(x: 0.5, y: 0.5)) == .accepted)
        #expect(requests.count == 1 && requests[0].selectionRevision == 2)
        #expect(view.nominate(at: CGPoint(x: -0.1, y: 0.5)) == .refused("Subject selection is unavailable"))
        #expect(requests.count == 1)
        let readOnly = DirectorSubjectPickView(pick: pick(canOverride: false), imageSize: .zero,
            onOverride: { requests.append($0); return .accepted })
        #expect(readOnly.nominate(at: .zero) == .refused("Subject selection is unavailable"))
        #expect(requests.count == 1)
    }

    #if DEBUG
    @Test func pickAppearsOnTheNextConsoleRefreshWithoutChangingTheCameraSnapshot() {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        var section = NextShotStatus.DirectorSection.atLaunch(qualified: .none)
        let model = LiveConsoleModel(show: show, directorStatusEnabled: true, directorStatus: { section })
        let cameraSnapshot = model.snapshot
        section.subjectPicks[.b] = pick(phase: .suggested, provenance: .alfie(.centralPresenter))
        #expect(model.directorSection?.subjectPicks.isEmpty == true)
        model.refresh()
        #expect(model.directorSection?.subjectPicks[.b] == section.subjectPicks[.b])
        #expect(model.snapshot == cameraSnapshot)
    }
    #endif

    #if DEBUG
    @Test func galleryNominationChangesOnceAndTheOldPaintedRequestIsRetired() throws {
        let controller = DirectorSubjectPickGalleryController()
        let second = try #require(controller.pick.candidates.last)
        let request = try #require(controller.pick.overrideRequest(at: CGPoint(x: second.bounds.midX, y: second.bounds.midY)))
        #expect(controller.overrideSubject(request) == .accepted)
        #expect(controller.nominationChanges == 1)
        #expect(controller.pick.selectedCandidateID == second.id)
        #expect(controller.pick.provenance == .operatorNomination && controller.pick.phase == .acquiring)
        #expect(controller.overrideSubject(request) == .refused("The subject view changed. Choose again."))
        #expect(controller.nominationChanges == 1)
    }

    @Test(arguments: DirectorSubjectPickGallery.Scenario.allCases)
    func everyGalleryPhaseRendersWithinTheExistingPane(scenario: DirectorSubjectPickGallery.Scenario) {
        let pick = DirectorSubjectPickGallery.pick(scenario)
        #expect(pick.isValid)
        let renderer = ImageRenderer(content: DirectorSubjectPickGalleryPicture(pick: pick)
            .frame(width: 600, height: 338))
        #expect(renderer.nsImage?.size == CGSize(width: 600, height: 338))
    }
    #endif
}
