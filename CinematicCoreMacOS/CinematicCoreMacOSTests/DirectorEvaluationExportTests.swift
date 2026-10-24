import Foundation
import Testing
@testable import Alfie

/// Optional, explicit synthetic measurement export. Never reads or writes app stores.
@MainActor struct DirectorEvaluationExportTests {
    private func levelName(_ level: DirectorAuthority.Level) -> String {
        switch level {
        case .off: "off"
        case .suggest: "suggest"
        case .assist: "assist"
        case .auto: "auto"
        case .backup: "backup"
        }
    }

    private func staleName(_ reason: DirectorProposalValidator.StaleReason) -> String {
        switch reason {
        case .authorityRevoked: "authorityRevoked"
        case .routeChanged: "routeChanged"
        case .sourceRestarted: "sourceRestarted"
        case .shotChangedByOperator: "shotChangedByOperator"
        case .targetBecameProgram: "targetBecameProgram"
        case .sourceMissing: "sourceMissing"
        case .expired: "expired"
        case .requestReplaced: "requestReplaced"
        case .policyChanged: "policyChanged"
        case .nominationChanged: "nominationChanged"
        case .evidenceUnavailable: "evidenceUnavailable"
        }
    }

    @Test func exportFiveActualSyntheticReplayReportsWhenExplicitlyRequested() throws {
        guard let destination = ProcessInfo.processInfo.environment["ALFIE_DIRECTOR_EVALUATION_EXPORT"] else { return }
        let url = URL(fileURLWithPath: destination).standardizedFileURL
        // Limit the opt-in harness to a new JSON artifact in the system temp tree.
        let temporaryRoots = ["/private/tmp/", "/tmp/", FileManager.default.temporaryDirectory.standardizedFileURL.path + "/"]
        try #require(destination.hasPrefix("/") && url.pathExtension == "json"
            && temporaryRoots.contains(where: { url.path.hasPrefix($0) }))
        try #require(!FileManager.default.fileExists(atPath: url.path))
        let policy = DirectorShotPolicy.Parameters.policyStudy
        let readiness = DirectorReadiness.Parameters.replayStudy
        let maximumProposalAge = 5.0, maximumEvidenceAge = 5.0
        let parameters: [String: Any] = [
            "shotPolicy": ["minimumShotDuration": policy.minimumShotDuration,
                "maximumShotDuration": policy.maximumShotDuration,
                "wideCadence": policy.wideCadence, "repetitionWindow": policy.repetitionWindow,
                "maximumMovement": policy.maximumMovement, "cutOnMotionAllowed": policy.cutOnMotionAllowed],
            "readiness": ["minimumSettledTime": readiness.minimumSettledTime,
                "maximumMotion": readiness.maximumMotion, "cutOnMotionAllowed": readiness.cutOnMotionAllowed,
                "minimumCutSettledTime": readiness.minimumCutSettledTime,
                "maximumCutMotion": readiness.maximumCutMotion],
            "replay": ["maximumProposalAge": maximumProposalAge, "maximumEvidenceAge": maximumEvidenceAge]
        ]
        let scenarioIDs = ["calm-presenter", "walking-presenter", "panel-of-three", "camera-b-drops", "operator-intervention"]
        var runs: [[String: Any]] = []
        for (index, fixture) in DirectorReplayFixtures.all.enumerated() {
            let report = DirectorReplay.run(fixture, parameters: policy,
                maximumProposalAge: maximumProposalAge, maximumEvidenceAge: maximumEvidenceAge,
                readinessParameters: readiness)
            #expect(report.evidence == .synthetic)
            let reasons = Dictionary(uniqueKeysWithValues: report.staleProposalsRejected.map { (staleName($0.key), $0.value) })
            let latencies: [Any] = report.manualOverrideLatencies.map { value in
                if let value { return value as Any }
                return NSNull()
            }
            let metrics: [String: Any] = [
                "cutsPerMinute": report.cutsPerMinute,
                "minimumDurationViolations": report.minimumDurationViolations,
                "oscillations": report.oscillations,
                "staleProposalsRejected": reasons,
                "manualOverridesHonoured": report.manualOverridesHonoured,
                "manualOverrideLatencies": latencies,
                "proposalCount": report.proposalCount,
                "directorAttemptCount": report.directorAttemptCount,
                "directorCuts": report.directorCuts,
                "operatorTakeAttempts": report.operatorTakeAttempts,
                "operatorCuts": report.operatorCuts,
                "duplicateCallbacks": report.duplicateCallbacks,
                "failedEffects": report.failedEffects,
                "rejectedAttempts": report.rejectedAttempts,
                "preparationsCommitted": report.preparationsCommitted,
                "acknowledgementsAccepted": report.acknowledgementsAccepted,
                "acknowledgementsRejected": report.acknowledgementsRejected,
                "readyEvaluations": report.readyEvaluations,
                "staleEffectsCommitted": report.staleEffectsCommitted,
                "unqualifiedRefusals": report.unqualifiedRefusals,
                "finalLevel": levelName(report.finalLevel),
                "finalPaused": report.finalPaused,
                "clockAnomalies": report.clockAnomalies,
                "wrongSubjectAttempts": report.wrongSubjectAttempts,
                "labelledSubjectAttempts": report.labelledSubjectAttempts,
                "proposalsMadeWhilePaused": report.proposalsMadeWhilePaused,
                "programChangesWithoutAuthority": report.programChangesWithoutAuthority,
                "wrongSubjectProposals": report.wrongSubjectProposals,
                "labelledSubjectProposals": report.labelledSubjectProposals
            ]
            runs.append([
                "scenarioID": scenarioIDs[index], "sessionID": UUID().uuidString,
                "evidenceClass": "synthetic", "level": "assist", "executionMode": "observing",
                "route": "none", "configurationID": "replay-study-1", "parameterVersion": "1",
                "judgeKind": "rules", "modelVersion": NSNull(), "durationSeconds": fixture.duration,
                "parameters": parameters,
                "opportunities": ["eligible": NSNull(), "useful": NSNull(), "unverified": NSNull()],
                "metrics": metrics
            ])
        }
        #expect(runs.count == 5)
        let envelope: [String: Any] = ["evaluationSchemaVersion": 1, "producer": "DirectorReplay",
                                       "runs": runs, "shadowBindings": []]
        let bytes = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
        try bytes.write(to: url, options: .withoutOverwriting)
    }
}
