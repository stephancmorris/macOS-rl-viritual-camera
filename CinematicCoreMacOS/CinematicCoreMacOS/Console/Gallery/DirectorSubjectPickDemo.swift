#if DEBUG
import Combine
import CoreGraphics
import Foundation
import SwiftUI

enum DirectorSubjectPickGallery {
    enum Scenario: String, CaseIterable, Identifiable, Sendable {
        case alfieSuggested, alfieAcquiring, operatorTracking, ambiguous, recovering, lost, unavailable
        var id: String { rawValue }
        var title: String {
            switch self {
            case .alfieSuggested: return "Alfie's pick · select to acquire"
            case .alfieAcquiring: return "Alfie's pick · acquiring"
            case .operatorTracking: return "Your subject · tracking"
            case .ambiguous: return "Ambiguous · no pick"
            case .recovering: return "Recovering · last position"
            case .lost: return "Subject lost"
            case .unavailable: return "No current view"
            }
        }
    }

    static let imageSize = CGSize(width: 1920, height: 1080)
    static let candidates: [DirectorSubjectPick.Candidate] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
              bounds: CGRect(x: 0.23, y: 0.12, width: 0.18, height: 0.66)),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
              bounds: CGRect(x: 0.64, y: 0.16, width: 0.16, height: 0.56))
    ]

    static func pick(_ scenario: Scenario, revision: UInt64 = 1) -> DirectorSubjectPick {
        let phase: DirectorSubjectPick.Phase
        let selected: UUID?
        let provenance: DirectorSubjectPick.Provenance?
        var boxes = candidates
        switch scenario {
        case .alfieSuggested:
            phase = .suggested; selected = boxes[0].id; provenance = .alfie(.centralPresenter)
        case .alfieAcquiring:
            phase = .acquiring; selected = boxes[0].id; provenance = .alfie(.centralPresenter)
        case .operatorTracking:
            phase = .tracking; selected = boxes[1].id; provenance = .operatorNomination
        case .ambiguous:
            phase = .ambiguous; selected = nil; provenance = nil
        case .recovering:
            phase = .recovering; selected = boxes[0].id; provenance = .operatorNomination
            boxes = [boxes[0]]
        case .lost:
            phase = .lost; selected = nil; provenance = nil; boxes = []
        case .unavailable:
            phase = .unavailable; selected = nil; provenance = nil; boxes = []
        }
        return .init(channel: .b, sourceGeneration: 7, selectionRevision: revision, routeGeneration: 3,
                     phase: phase, selectedCandidateID: selected, candidates: boxes,
                     provenance: provenance, canOverride: scenario != .unavailable)
    }
}

/// Isolated interaction model: acceptance is a synthetic nomination event,
/// never a camera operation, stored identity or qualification.
final class DirectorSubjectPickGalleryController: ObservableObject, DirectorConsoleControlling {
    @Published private(set) var directorSection = NextShotStatus.DirectorSection.atLaunch(qualified: .none)
    @Published private(set) var nominationChanges = 0
    private var revision: UInt64 = 0

    init() { load(.alfieAcquiring) }

    var pick: DirectorSubjectPick { directorSection.subjectPicks[.b]! }

    func load(_ scenario: DirectorSubjectPickGallery.Scenario) {
        revision += 1
        directorSection = .atLaunch(qualified: .none)
        directorSection.subjectPicks[.b] = DirectorSubjectPickGallery.pick(scenario, revision: revision)
    }

    func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult { .refused("not qualified") }
    func handToAlfie() -> DirectorControlResult { .refused("Synthetic subject example") }
    func takeOver() {}
    func cancelNextCut() {}
    func advanceSegment() {}
    func overrideSubject(on channel: ChannelID, at point: CGPoint) {}

    func overrideSubject(_ request: DirectorSubjectOverrideRequest) -> DirectorControlResult {
        guard request.matches(pick) else { return .refused("The subject view changed. Choose again.") }
        guard let person = pick.candidates.first(where: { $0.bounds.contains(request.point) }) else {
            return .refused("No person at that point in this synthetic example")
        }
        revision += 1
        directorSection.subjectPicks[.b] = .init(channel: .b, sourceGeneration: pick.sourceGeneration,
            selectionRevision: revision, routeGeneration: pick.routeGeneration, phase: .acquiring,
            selectedCandidateID: person.id, candidates: pick.candidates,
            provenance: .operatorNomination, canOverride: true)
        nominationChanges += 1
        return .accepted
    }
}

struct DirectorSubjectPickDemo: View {
    @StateObject private var controller = DirectorSubjectPickGalleryController()
    @State private var scenario = DirectorSubjectPickGallery.Scenario.alfieAcquiring

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Synthetic source only. Click either person to nominate; no camera, readiness decision or qualification is involved.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Picker("Subject example", selection: $scenario) {
                ForEach(DirectorSubjectPickGallery.Scenario.allCases) { scenario in
                    Text(scenario.title).tag(scenario)
                }
            }
            .frame(width: 310)
            .onChange(of: scenario) { _, value in controller.load(value) }
            DirectorSubjectPickGalleryPicture(pick: controller.pick, onOverride: controller.overrideSubject)
                .frame(width: 600, height: 338)
            Text("Synthetic nomination changes: \(controller.nominationChanges)")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(DirectorSubjectPickGallery.Scenario.allCases) { scenario in
                VStack(alignment: .leading, spacing: 6) {
                    Text(scenario.title).font(ConsoleStyle.label(11))
                    DirectorSubjectPickGalleryPicture(pick: DirectorSubjectPickGallery.pick(scenario))
                        .frame(width: 600, height: 338)
                }
            }
        }
    }
}

struct DirectorSubjectPickGalleryPicture: View {
    let pick: DirectorSubjectPick
    var onOverride: ((DirectorSubjectOverrideRequest) -> DirectorControlResult)? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.12)
                ForEach(DirectorSubjectPickGallery.candidates) { candidate in
                    if let rect = DirectorSourceCoordinates.rect(candidate.bounds, viewSize: geometry.size,
                        imageSize: DirectorSubjectPickGallery.imageSize) {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: rect.width * 0.8, height: rect.height * 0.95)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                DirectorSubjectPickView(pick: pick, imageSize: DirectorSubjectPickGallery.imageSize,
                                        onOverride: onOverride)
            }
        }
        .overlay(Rectangle().strokeBorder(ConsoleStyle.previewGreen, lineWidth: 3))
    }
}
#endif
