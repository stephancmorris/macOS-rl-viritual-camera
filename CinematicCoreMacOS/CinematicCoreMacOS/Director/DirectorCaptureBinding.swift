import Foundation

extension DirectorShadowRecorder {
    /// Actual installed study inputs. The provider names this exact group; it
    /// cannot replace any execution setting or manufacture missing inputs.
    nonisolated struct CaptureKey: Equatable, Sendable {
        let policyRevision: UInt64
        let preferencesVersion: Int
        let style: DirectorStyle
        let readiness: DirectorReadiness.Parameters
        let adapter: DirectorEvidenceAdapter.Parameters
        let judgeMaximumAge: Double?
        let minimumProbability: Double?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.policyRevision == rhs.policyRevision && lhs.preferencesVersion == rhs.preferencesVersion &&
                lhs.style == rhs.style &&
                DirectorShadowRecord.ReadinessParameters(lhs.readiness) == DirectorShadowRecord.ReadinessParameters(rhs.readiness) &&
                DirectorShadowRecord.AdapterParameters(lhs.adapter) == DirectorShadowRecord.AdapterParameters(rhs.adapter) &&
                lhs.judgeMaximumAge == rhs.judgeMaximumAge && lhs.minimumProbability == rhs.minimumProbability
        }
    }
    typealias CaptureBindingProvider = (CaptureKey) -> CaptureBinding?
}
