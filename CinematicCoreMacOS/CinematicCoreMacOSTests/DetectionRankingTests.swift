import CoreGraphics
import Testing
@testable import Alfie

struct DetectionRankingTests {
    private func candidate(_ index: Int, x: CGFloat, size: CGFloat = 0.1,
                           confidence: Float = 0.9) -> PersonDetector.RectangleCandidate {
        .init(index: index, box: CGRect(x: x - size / 2, y: 0.5 - size / 2,
                                       width: size, height: size), confidence: confidence)
    }

    @Test func sixthBoxNearestTheLockSurvivesEveryInputOrder() {
        let reference = CGRect(x: 0.75, y: 0.45, width: 0.1, height: 0.1)
        let candidates = (0..<6).map { candidate($0, x: CGFloat($0) * 0.15 + 0.05) }
        for offset in candidates.indices {
            let rotated = Array(candidates[offset...]) + Array(candidates[..<offset])
            let chosen = PersonDetector.preferredRectangleIndices(rotated, referenceBox: reference, limit: 5)
            #expect(chosen.count == 5)
            #expect(chosen.first == 5)
            #expect(!chosen.contains(0))
        }
    }

    @Test func unlockedCandidatesPreferAreaThenConfidence() {
        let candidates = [candidate(0, x: 0.5), candidate(1, x: 0.5, size: 0.2, confidence: 0.7),
                          candidate(2, x: 0.5, size: 0.2, confidence: 0.95)]
        #expect(PersonDetector.preferredRectangleIndices(candidates, referenceBox: nil, limit: 2) == [2, 1])
    }

    @Test func equalDistancePrefersAreaThenConfidenceThenOriginalIndex() {
        let reference = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        let candidates = [candidate(0, x: 0.5), candidate(1, x: 0.5, size: 0.2, confidence: 0.7),
                          candidate(2, x: 0.5, size: 0.2, confidence: 0.95),
                          candidate(3, x: 0.5, size: 0.2, confidence: 0.95)]
        #expect(PersonDetector.preferredRectangleIndices(candidates, referenceBox: reference, limit: 5) == [2, 3, 1, 0])
    }

    @Test func zeroLimitRetainsNothing() {
        #expect(PersonDetector.preferredRectangleIndices([candidate(0, x: 0.5)], referenceBox: nil, limit: 0).isEmpty)
    }
}
