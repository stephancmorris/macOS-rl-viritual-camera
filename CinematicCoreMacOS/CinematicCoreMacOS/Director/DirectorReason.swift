import Foundation

/// Decision core, stage 4: one set of reasons. Every refusal, abstention and
/// stale result in the Director maps to one (domain, code) from the shadow
/// record's vocabulary, and every (domain, code) has one sentence for the
/// operator. The same cause from different sources shares a code; different
/// causes never share a code or a sentence.
nonisolated struct DirectorReason: Equatable, Hashable, Sendable {
    typealias Domain = DirectorShadowRecord.ReasonDomain
    typealias Code = DirectorShadowRecord.ReasonCode

    let domain: Domain
    let code: Code

    init(_ domain: Domain, _ code: Code) { self.domain = domain; self.code = code }

    /// The record's own reason value.
    var record: DirectorShadowRecord.Reason { .init(domain: domain, code: code) }

    /// One short sentence in the operator's terms.
    var words: String { Self.words(for: self) }
}

// MARK: Mappings (total: every case of every source)

nonisolated extension DirectorReason {
    init(_ reason: DirectorProposalValidator.StaleReason) {
        switch reason {
        case .authorityRevoked: self.init(.proposalStale, .authorityRevoked)
        case .routeChanged: self.init(.proposalStale, .routeChanged)
        case .sourceRestarted: self.init(.proposalStale, .sourceRestarted)
        case .shotChangedByOperator: self.init(.proposalStale, .shotChangedByOperator)
        case .targetBecameProgram: self.init(.proposalStale, .targetBecameProgram)
        case .sourceMissing: self.init(.proposalStale, .sourceMissing)
        case .expired: self.init(.proposalStale, .expired)
        case .requestReplaced: self.init(.proposalStale, .requestReplaced)
        case .policyChanged: self.init(.proposalStale, .policyChanged)
        case .nominationChanged: self.init(.proposalStale, .nominationChanged)
        case .evidenceUnavailable: self.init(.proposalStale, .evidenceUnavailable)
        }
    }

    init(_ reason: DirectorReadiness.Reason) {
        switch reason {
        case .compositionUnavailable: self.init(.readiness, .compositionUnavailable)
        case .evidenceUnavailable: self.init(.readiness, .evidenceUnavailable)
        case .takeUnavailable: self.init(.readiness, .takeUnavailable)
        case .invalidParameters: self.init(.readiness, .invalidParameters)
        case .invalidEvidence: self.init(.readiness, .invalidEvidence)
        case .identityUncertain: self.init(.readiness, .identityUncertain)
        case .framingUnsettled: self.init(.readiness, .framingUnsettled)
        case .moving: self.init(.readiness, .moving)
        case .cropMoving: self.init(.readiness, .cropMoving)
        }
    }

    init(_ reason: DirectorShotPolicy.Abstention) {
        switch reason {
        case .invalidInput: self.init(.policy, .invalidInput)
        case .minimumDuration: self.init(.policy, .minimumDuration)
        case .noEligibleCandidate: self.init(.policy, .noEligibleCandidate)
        case .repetition: self.init(.policy, .repetition)
        case .movement: self.init(.policy, .movement)
        case .noPreview: self.init(.policy, .noPreview)
        }
    }

    init(_ reason: DirectorJudgement.Abstention) {
        switch reason {
        case .policy(let policy): self.init(policy)
        case .lowConfidence: self.init(.judge, .lowConfidence)
        case .notRecorded: self.init(.judge, .notRecorded)
        case .nothingAllowed: self.init(.judge, .nothingAllowed)
        case .invalidJudgement: self.init(.judge, .invalidJudgement)
        }
    }

    /// An Assist abstention may carry several readiness causes; each keeps its
    /// own code, in order.
    static func reasons(_ abstention: DirectorShotPolicy.AssistAbstention) -> [DirectorReason] {
        switch abstention {
        case .invalidInput: [.init(.policy, .invalidInput)]
        case .noPreview: [.init(.policy, .noPreview)]
        case .previewIsSafeWide: [.init(.policy, .previewIsSafeWide)]
        case .alreadyPrepared: [.init(.policy, .alreadyPrepared)]
        case .operatorAdjusting: [.init(.readiness, .operatorAdjusting)]
        case .learningSubject: [.init(.readiness, .learningSubject)]
        case .recoveringSubject: [.init(.readiness, .recoveringSubject)]
        case .evidenceUnavailable: [.init(.readiness, .evidenceUnavailable)]
        // An empty list carries no cause; it is still "not ready".
        case .notReady(let causes): causes.isEmpty ? [.init(.readiness, .previewNotReady)] : causes.map(DirectorReason.init)
        case .movement: [.init(.policy, .movement)]
        case .policy(let policy): [.init(policy)]
        case .judge(let judge): [.init(judge)]
        case .judgementStale: [.init(.observation, .judgementStale)]
        }
    }

    init(_ reason: CutPolicy.Abstention) {
        switch reason {
        case .invalidInput: self.init(.policy, .invalidInput)
        case .authority: self.init(.authorityRefusal, .takeNotAllowed)
        case .minimumDwell: self.init(.policy, .minimumDuration)
        case .notReady: self.init(.readiness, .previewNotReady)
        case .nothingBetter: self.init(.policy, .noCutDue)
        case .judge: self.init(.judge, .judgeDeclined)
        }
    }

    /// Why a cut is due now.
    init(_ reason: CutPolicy.Reason) {
        switch reason {
        case .preferredLength: self.init(.selection, .preferredLength)
        case .programUncertain: self.init(.selection, .programUncertain)
        case .wideDue: self.init(.selection, .wideDue)
        }
    }

    init(_ rejection: SpeechRejection) {
        switch rejection {
        case .noWakePrefix: self.init(.speech, .noWakePrefix)
        case .unrecognized: self.init(.speech, .unrecognized)
        case .subjectNotLocked: self.init(.speech, .subjectNotLocked)
        case .lowConfidence: self.init(.speech, .lowConfidence)
        case .duplicateUtterance: self.init(.speech, .duplicateUtterance)
        case .cancelledByManualCommand: self.init(.speech, .cancelledByManualCommand)
        case .targetUnavailable: self.init(.speech, .targetUnavailable)
        case .missingUtteranceStart: self.init(.speech, .missingUtteranceStart)
        case .invalidToken: self.init(.speech, .invalidToken)
        case .muted: self.init(.speech, .muted)
        case .stopped: self.init(.speech, .stopped)
        case .sessionChanged: self.init(.speech, .sessionChanged)
        case .roleChanged: self.init(.speech, .roleChanged)
        case .targetRebound: self.init(.speech, .targetRebound)
        case .sourceChanged: self.init(.speech, .sourceChanged)
        case .expired: self.init(.speech, .expired)
        case .cancelledByWide: self.init(.speech, .cancelledByWide)
        case .cancelledByTake: self.init(.speech, .cancelledByTake)
        case .cancelledByMute: self.init(.speech, .cancelledByMute)
        }
    }

    /// The world model's "unknown". Its payload (a region, an age, track IDs)
    /// is for rules only and never becomes part of a reason.
    init(_ unknown: WorldModel.Unknown) {
        switch unknown {
        case .notAssigned: self.init(.worldModel, .notAssigned)
        case .sourceMissing: self.init(.worldModel, .sourceMissing)
        case .notObserved: self.init(.worldModel, .notObserved)
        case .partialView: self.init(.worldModel, .partialView)
        case .stale: self.init(.worldModel, .stale)
        case .ambiguous: self.init(.worldModel, .ambiguous)
        }
    }
}

// MARK: Words

nonisolated extension DirectorReason {
    /// Every (domain, code) the record accepts in its newest schema.
    static var all: [DirectorReason] {
        DirectorShadowRecord.ReasonDomain.allCases.flatMap { domain in
            DirectorShadowRecord.ReasonCode.allCases.compactMap { code in
                DirectorShadowRecord.Reason(domain: domain, code: code).isValid(in: DirectorShadowRecord.currentSchemaVersion)
                    ? DirectorReason(domain, code) : nil
            }
        }
    }

    /// One short sentence for each reason the record accepts. Where the app
    /// already says it (the console, the voice grammar), the same words are used.
    static func words(for reason: DirectorReason) -> String {
        switch reason.domain {
        case .proposalStale:
            switch reason.code {
            case .authorityRevoked: return "Alfie's permission changed, so this was dropped."
            case .routeChanged: return "Program changed, so this was dropped."
            case .sourceRestarted: return "The camera restarted, so this was dropped."
            case .shotChangedByOperator: return "You changed the shot, so this was dropped."
            case .targetBecameProgram: return "That camera is on Program now. Use Edit Live."
            case .sourceMissing: return "The camera's source went missing, so this was dropped."
            case .expired: return "This waited too long and expired."
            case .requestReplaced: return "A newer request replaced this one."
            case .policyChanged: return "The style changed, so this was dropped."
            case .nominationChanged: return "The subject changed, so this was dropped."
            case .evidenceUnavailable: return "The subject could no longer be seen, so this was dropped."
            default: break
            }
        case .policy:
            switch reason.code {
            case .invalidInput: return "Can't decide: check the cameras."
            case .minimumDuration: return "Holding the current shot."
            case .noEligibleCandidate: return "Nothing better ready."
            case .repetition: return "Holding off: that shot was just used."
            case .movement: return "Waiting for the subject to settle."
            case .noPreview: return "No Preview camera."
            case .previewIsSafeWide: return "Preview is the wide camera, so there is nothing to prepare."
            case .alreadyPrepared: return "Preview is prepared, so Alfie keeps its shot."
            case .noCutDue: return "No cut is due yet."
            default: break
            }
        case .judge:
            switch reason.code {
            case .lowConfidence: return "Not sure enough, so Alfie keeps the current shot."
            case .notRecorded: return "The recorded judge has nothing for this moment."
            case .nothingAllowed: return "The judge found no allowed shot."
            case .invalidJudgement: return "The judge's answer was not usable."
            case .judgeDeclined: return "The judge did not pick the prepared shot."
            default: break
            }
        case .readiness:
            switch reason.code {
            case .compositionUnavailable: return "The framing could not be read."
            case .evidenceUnavailable: return "Waiting: no clear view of the subject."
            case .takeUnavailable: return "Take is not available right now."
            case .invalidParameters: return "The study settings are not valid."
            case .invalidEvidence: return "The camera's readings were not usable."
            case .identityUncertain: return "Not sure it is the right person."
            case .framingUnsettled: return "Waiting for the framing to settle."
            case .moving: return "The subject is moving too much."
            case .cropMoving: return "The frame is still moving."
            case .operatorAdjusting: return "Waiting: you're adjusting the camera."
            case .learningSubject: return "Waiting: learning the subject."
            case .recoveringSubject: return "Waiting: finding the subject again."
            case .previewNotReady: return "Preview is not ready to cut to."
            default: break
            }
        case .selection:
            switch reason.code {
            case .advisoryWideReminder: return "A wide shot is due."
            case .advisoryMaximumDwell: return "The current shot has run long."
            case .subjectEvidence: return "The subject is clear on Preview."
            case .unclassified: return "Chosen for a reason Alfie did not record."
            case .preferredLength: return "The current shot has run its length."
            case .programUncertain: return "Program's subject is no longer certain."
            case .wideDue: return "It is time for the wide."
            default: break
            }
        case .observation:
            switch reason.code {
            case .parametersUnavailable: return "No study settings were in use."
            case .parametersInvalid: return "The study settings were not valid."
            case .judgementStale: return "The judge's answer was too old."
            case .cutPolicyUnavailable: return "No cut rules are running."
            case .unclassified: return "No reason was recorded."
            default: break
            }
        case .authorityRefusal:
            switch reason.code {
            case .notQualified: return "This level is not signed off for this rig."
            case .prerequisites: return "Something Alfie needs is not ready."
            case .paused: return "Alfie is paused."
            case .exhausted: return "Alfie has used up its permits."
            case .takeNotAllowed: return "Alfie is not allowed to cut at this level."
            default: break
            }
        case .speech:
            switch reason.code {
            case .noWakePrefix: return "Say Alfie first."
            case .unrecognized: return "Command not recognized."
            case .subjectNotLocked: return "Pick a subject."
            case .lowConfidence: return "Speech uncertain."
            case .duplicateUtterance: return "Already handled."
            case .cancelledByManualCommand: return "Cancelled by manual control."
            case .targetUnavailable: return "Camera unavailable."
            case .missingUtteranceStart: return "Utterance start missing."
            case .invalidToken: return "Voice context invalid."
            case .muted: return "Voice is muted."
            case .stopped: return "Show stopped."
            case .sessionChanged: return "Show session changed."
            case .roleChanged: return "Camera roles changed."
            case .targetRebound: return "Control target changed."
            case .sourceChanged: return "Camera changed."
            case .expired: return "Voice command expired."
            case .cancelledByWide: return "Cancelled by Return to Wide."
            case .cancelledByTake: return "Cancelled by Take."
            case .cancelledByMute: return "Cancelled because voice was muted."
            default: break
            }
        case .worldModel:
            switch reason.code {
            case .notAssigned: return "No camera is assigned there."
            case .sourceMissing: return "That camera's source is missing."
            case .notObserved: return "That camera has not looked for people yet."
            case .partialView: return "Alfie can only see part of that camera right now."
            case .stale: return "That camera's view of people is out of date."
            case .ambiguous: return "Two people are too close together to tell apart."
            default: break
            }
        }
        // Not a reason the record accepts.
        return "Alfie can't say why."
    }
}
