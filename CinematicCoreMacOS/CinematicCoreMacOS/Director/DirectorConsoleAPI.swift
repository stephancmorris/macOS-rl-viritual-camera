//
//  DirectorConsoleAPI.swift
//  CinematicCoreMacOS
//
//  S3 A-04: what the operator console shows about the Auto Director and the
//  verbs it may send. The status is a plain value with operator-facing text
//  for every state (plain words; codes, ages and revisions belong in the
//  inspector). Views talk only to `DirectorConsoleControlling`; the engine
//  (B-03) implements it, and the gallery uses a fake.
//

import CoreGraphics
import Foundation

extension NextShotStatus {
    /// The Director's status for the console (U1/U2).
    nonisolated struct DirectorSection: Equatable, Sendable {
        /// The four modes the operator sees. Shadow mode is internal and shows as Manual.
        enum Level: String, CaseIterable, Equatable, Sendable {
            case manual, assist, auto, backup

            var title: String {
                switch self {
                case .manual: return "Manual"
                case .assist: return "Assist"
                case .auto: return "Auto"
                case .backup: return "Backup"
                }
            }
        }

        enum Activity: Equatable, Sendable {
            case active(ActiveReason)
            case paused(PauseReason)
            case inhibited(InhibitReason)
            case abstaining(AbstainReason)

            enum Kind: String, CaseIterable, Equatable, Sendable { case active, paused, inhibited, abstaining }

            var kind: Kind {
                switch self {
                case .active: return .active
                case .paused: return .paused
                case .inhibited: return .inhibited
                case .abstaining: return .abstaining
                }
            }

            /// The sentence the operator reads.
            var text: String {
                switch self {
                case .active(let reason): return reason.text
                case .paused(let reason): return reason.text
                case .inhibited(let reason): return reason.text
                case .abstaining(let reason): return reason.text
                }
            }
        }

        enum ActiveReason: Equatable, Sendable {
            /// Shadow / Suggest: Alfie is deciding but not changing anything.
            case watching
            case preparing(input: ChannelID, shot: DirectorShot, settled: Bool)
            case ready(input: ChannelID, shot: DirectorShot)
            /// The operator cut (a nudge): Alfie keeps that shot for a while.
            case holdingOperatorShot(input: ChannelID)

            var text: String {
                switch self {
                case .watching:
                    return "Watching · Alfie is not changing shots"
                case .preparing(let input, let shot, let settled):
                    return "Preparing \(input.cameraLabel) \(shot.title)" + (settled ? " · subject settled" : "")
                case .ready(let input, let shot):
                    return "Ready · \(input.cameraLabel) \(shot.title)"
                case .holdingOperatorShot(let input):
                    return "Holding your shot on \(input.cameraLabel)"
                }
            }
        }

        enum PauseReason: Equatable, Sendable {
            case manualMode, operatorTookOver, editLive, sourceLost(ChannelID), outputProblem
            case setupChanged, subjectLost(ChannelID), afterFallback, styleChanged, subjectChanged, showStopped

            var text: String {
                switch self {
                case .manualMode: return "Manual · Alfie is not directing"
                case .operatorTookOver: return "Paused: you took over"
                case .editLive: return "Paused: editing Program live"
                case .sourceLost(let input): return "Paused: \(input.cameraLabel) lost"
                case .outputProblem: return "Paused: output problem"
                case .setupChanged: return "Paused: camera setup changed"
                case .subjectLost(let input): return "Paused: subject lost on \(input.cameraLabel)"
                case .afterFallback: return "Paused after fallback · Hand to Alfie when ready"
                case .styleChanged: return "Paused: style changed"
                case .subjectChanged: return "Paused: subject changed"
                case .showStopped: return "Show stopped"
                }
            }
        }

        enum InhibitReason: Equatable, Sendable {
            case operatorAdjusting(ChannelID), learningSubject(ChannelID), recoveringSubject(ChannelID)
            case noFreshView(ChannelID), cameraNotReady

            var text: String {
                switch self {
                case .operatorAdjusting(let input): return "Waiting: you're adjusting \(input.cameraLabel)"
                case .learningSubject(let input): return "Waiting: learning the subject on \(input.cameraLabel)"
                case .recoveringSubject(let input): return "Waiting: \(input.cameraLabel) is finding the subject again"
                case .noFreshView(let input): return "Waiting: no clear view of the subject on \(input.cameraLabel)"
                case .cameraNotReady: return "Waiting: a camera is not ready"
                }
            }
        }

        enum AbstainReason: Equatable, Sendable {
            case noPreview, previewIsSafeWide, moreThanOnePerson(ChannelID), justUsed, holdingCurrentShot
            case subjectMoving, nothingBetter, cannotDecide, notSureEnough, previewAlreadyPrepared

            var text: String {
                switch self {
                case .previewAlreadyPrepared: return "Preview is prepared · keeping its shot"
                case .noPreview: return "No Preview camera"
                case .previewIsSafeWide: return "Preview is the wide camera · nothing to prepare"
                case .moreThanOnePerson(let input): return "More than one person on \(input.cameraLabel) · staying wide"
                case .justUsed: return "Holding off: that shot was just used"
                case .holdingCurrentShot: return "Holding the current shot"
                case .subjectMoving: return "Waiting for the subject to settle"
                case .nothingBetter: return "Nothing better ready"
                case .cannotDecide: return "Can't decide: check the cameras"
                case .notSureEnough: return "Not sure enough · keeping the current shot"
                }
            }
        }

        struct PreparedShot: Equatable, Sendable {
            let input: ChannelID
            let shot: DirectorShot
            /// e.g. "Cam B · Waist Up"
            var line: String { "\(input.cameraLabel) · \(shot.title)" }
        }

        /// The cut Alfie will make. `countdown == nil` is Backup's notice: the
        /// next cut is named and no duration is shown. The length is a
        /// parameter (A4 is open); there is no built-in value.
        struct NextCut: Equatable, Sendable {
            let input: ChannelID
            let countdown: TimeInterval?
            let cancellable: Bool

            /// e.g. "Next: Cam B · 2 s · Esc to cancel"
            var line: String {
                var parts = ["Next: \(input.cameraLabel)"]
                if let countdown, countdown.isFinite, countdown >= 0 {
                    parts.append(Self.seconds(countdown))
                }
                if cancellable { parts.append("Esc to cancel") }
                return parts.joined(separator: " · ")
            }

            static func seconds(_ value: TimeInterval) -> String {
                let whole = value.rounded()
                if abs(value - whole) < 0.05, let integer = Int(exactly: whole) {
                    return "\(integer) s"
                }
                // Display rounding must not overflow either Int or Double.
                // Extremely large finite supplied values remain representable
                // as text; formatting never chooses a valid notice duration.
                let tenths = value * 10
                let display = tenths.isFinite ? tenths.rounded() / 10 : value
                return "\(display) s"
            }
        }

        /// B-12 reports facts only. This alert never authorizes a fallback or
        /// changes authority; a successful fallback remains paused.
        enum BackupAlert: Equatable, Sendable {
            case switchedTo(ChannelID)
            case bothInputsStale
            case pausedAfterFallback

            var title: String {
                switch self {
                case .switchedTo(let channel): return "Program lost → switched to \(channel.cameraLabel)"
                case .bothInputsStale: return "Both inputs stale"
                case .pausedAfterFallback: return "Paused after fallback"
                }
            }

            var detail: String {
                switch self {
                case .switchedTo, .pausedAfterFallback:
                    return "Paused after fallback · Hand to Alfie when ready"
                case .bothInputsStale:
                    return "No safe input is ready. Check the cameras and output."
                }
            }

            var accessibilityLabel: String {
                switch self {
                case .switchedTo(let channel):
                    return "Program lost. Switched to \(channel.cameraLabel). \(detail)"
                case .bothInputsStale, .pausedAfterFallback:
                    return "\(title). \(detail)"
                }
            }
        }

        /// Per-level qualification on this rig. Manual is always allowed.
        struct Qualification: Equatable, Sendable {
            var assist: Bool
            var auto: Bool
            var backup: Bool

            static let none = Qualification(assist: false, auto: false, backup: false)

            func allows(_ level: Level) -> Bool {
                switch level {
                case .manual: return true
                case .assist: return assist
                case .auto: return auto
                case .backup: return backup
                }
            }
        }

        /// Display labels only (the run-sheet model is A-13).
        struct RunSheetLine: Equatable, Sendable {
            let current: String
            let next: String?
        }

        static let notQualifiedCaption = "not qualified"
        static let autoBadge = "AUTO"

        var level: Level
        var activity: Activity
        var prepared: PreparedShot?
        var nextCut: NextCut?
        /// Inputs whose current shot Alfie set; their tiles show AUTO (truthful preview).
        var alfieSetShot: Set<ChannelID>
        var qualified: Qualification
        /// False at every launch and after any takeover.
        var handedToAlfie: Bool
        var runSheet: RunSheetLine?
        var backupAlert: BackupAlert? = nil
        /// Source-bound selection facts, sampled with the existing console refresh.
        /// Empty means the Director supplies no subject selection display.
        var subjectPicks: [ChannelID: DirectorSubjectPick] = [:]

        /// Every launch: Manual, not handed to Alfie, nothing prepared or badged.
        static func atLaunch(qualified: Qualification) -> DirectorSection {
            DirectorSection(level: .manual, activity: .paused(.manualMode), prepared: nil, nextCut: nil,
                            alfieSetShot: [], qualified: qualified, handedToAlfie: false, runSheet: nil)
        }

        var statusLine: String { activity.text }
        var preparedLine: String { prepared?.line ?? "No shot prepared" }

        /// A level the operator may choose right now.
        func canSelect(_ level: Level) -> Bool { qualified.allows(level) }

        func showsAutoBadge(on channel: ChannelID) -> Bool { alfieSetShot.contains(channel) }
    }
}

/// The only verbs the console sends to the Director. Implementations refuse
/// rather than substitute (choosing an unqualified level never picks another).
@MainActor
protocol DirectorConsoleControlling: AnyObject {
    var directorSection: NextShotStatus.DirectorSection { get }

    @discardableResult
    func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult
    /// The one action that gives control back to Alfie (A1).
    @discardableResult
    func handToAlfie() -> DirectorControlResult
    /// Manual: Alfie stops preparing and cutting at once.
    func takeOver()
    func cancelNextCut()
    func advanceSegment()
    /// One tap on an input: the operator nominates the subject there (E1).
    func overrideSubject(on channel: ChannelID, at point: CGPoint)
    /// UI nomination bound to the source and route that were actually painted.
    /// Implementations must revalidate every binding before dispatching.
    @discardableResult
    func overrideSubject(_ request: DirectorSubjectOverrideRequest) -> DirectorControlResult
}

extension DirectorConsoleControlling {
    /// Old controllers must never silently downgrade a bound UI request.
    @discardableResult
    func overrideSubject(_ request: DirectorSubjectOverrideRequest) -> DirectorControlResult {
        .refused("Subject selection is unavailable")
    }
}

/// C-08 selection facts only. No pixels, identity probabilities or readiness
/// thresholds. Rectangles use normalized Vision coordinates (bottom-left).
nonisolated struct DirectorSubjectPick: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case unavailable, ambiguous, suggested, acquiring, tracking, recovering, lost
    }

    enum Rule: Equatable, Sendable {
        case positionHint, centralPresenter
    }

    enum Provenance: Equatable, Sendable {
        case operatorNomination
        case alfie(Rule)
    }

    struct Candidate: Equatable, Sendable, Identifiable {
        let id: UUID
        let bounds: CGRect

        var isValid: Bool {
            Self.validBounds(bounds)
        }

        static func validBounds(_ bounds: CGRect) -> Bool {
            let values = [bounds.minX, bounds.minY, bounds.width, bounds.height,
                          bounds.maxX, bounds.maxY]
            return values.allSatisfy(\.isFinite) && bounds.minX >= 0 && bounds.minY >= 0 &&
                bounds.width > 0 && bounds.height > 0 && bounds.maxX <= 1 && bounds.maxY <= 1
        }
    }

    /// A defensive UI bound, not a detector workload or qualification budget.
    static let maximumCandidates = 32

    let channel: ChannelID
    let sourceGeneration: UInt64
    let selectionRevision: UInt64
    let routeGeneration: UInt64
    let phase: Phase
    let selectedCandidateID: UUID?
    let candidates: [Candidate]
    let provenance: Provenance?
    /// The controller's current permission to nominate; the effect rechecks it.
    let canOverride: Bool

    var isValid: Bool {
        candidates.count <= Self.maximumCandidates && candidates.allSatisfy(\.isValid) &&
            Set(candidates.map(\.id)).count == candidates.count &&
            (selectedCandidateID == nil || candidates.contains { $0.id == selectedCandidateID }) &&
            (!(phase == .ambiguous || phase == .unavailable || phase == .lost) || selectedCandidateID == nil)
    }

    var selectedCandidate: Candidate? {
        guard isValid, let selectedCandidateID else { return nil }
        return candidates.first { $0.id == selectedCandidateID }
    }

    func overrideRequest(at point: CGPoint) -> DirectorSubjectOverrideRequest? {
        guard isValid, canOverride, DirectorSubjectOverrideRequest.isValid(point) else { return nil }
        return .init(channel: channel, sourceGeneration: sourceGeneration,
                     selectionRevision: selectionRevision, routeGeneration: routeGeneration, point: point)
    }
}

nonisolated struct DirectorSubjectOverrideRequest: Equatable, Sendable {
    let channel: ChannelID
    let sourceGeneration: UInt64
    let selectionRevision: UInt64
    let routeGeneration: UInt64
    let point: CGPoint

    var isValid: Bool { Self.isValid(point) }

    static func isValid(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    func matches(_ pick: DirectorSubjectPick) -> Bool {
        isValid && pick.isValid && pick.canOverride && channel == pick.channel &&
            sourceGeneration == pick.sourceGeneration && selectionRevision == pick.selectionRevision &&
            routeGeneration == pick.routeGeneration
    }
}

nonisolated enum DirectorControlResult: Equatable, Sendable {
    case accepted
    case refused(String)
}
