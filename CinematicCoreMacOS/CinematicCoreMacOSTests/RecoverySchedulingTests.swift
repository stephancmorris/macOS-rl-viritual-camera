import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import Alfie

private actor PausedRecoveryWorker {
    private var result: CheckedContinuation<[ShotComposer.ReacquisitionScore], Never>?
    private var request: [UUID]?
    private var observer: CheckedContinuation<[UUID], Never>?

    func score(_ ids: [UUID]) async -> [ShotComposer.ReacquisitionScore] {
        await withCheckedContinuation { continuation in
            precondition(result == nil)
            result = continuation
            request = ids
            observer?.resume(returning: ids)
            observer = nil
        }
    }
    func started() async -> [UUID] {
        if let request { return request }
        return await withCheckedContinuation { observer = $0 }
    }
    /// Releases the paused batch. Candidates absent from `distances` win at 0.10.
    func release(_ distances: [UUID: Float] = [:]) {
        let scores = (request ?? []).map {
            ShotComposer.ReacquisitionScore(id: $0, printDistance: distances[$0] ?? 0.10, landmarkDistance: 0.01)
        }
        let continuation = result
        result = nil; request = nil
        continuation?.resume(returning: scores)
    }
}

@MainActor
struct RecoverySchedulingTests {
    @MainActor private final class Fixture {
        let composer = ShotComposer()
        let worker = PausedRecoveryWorker()
        let subject = UUID(), a = UUID(), b = UUID()
        let pixels: CVPixelBuffer
        var time = 1000.0
        var observation: UInt64 = 0

        init() throws {
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, 2, 2,
                kCVPixelFormatType_32BGRA, nil, &buffer)
            #expect(status == kCVReturnSuccess)
            pixels = try #require(buffer)
            composer.reacquisitionScoringForTesting = { [worker] ids in await worker.score(ids) }
            composer.lockTarget(subject)
            composer.forceTrackingForTesting(readyGallery: true)
            _ = composer.tick(detections: [], timestamp: time, pixelBuffer: pixels)
        }
        func tick(_ ids: [UUID], excluded: Set<UUID> = []) {
            time += 0.04; observation += 1
            let persons = ids.map { id in
                PersonDetector.DetectedPerson(id: id,
                    boundingBox: CGRect(x: 0.4, y: 0.25, width: 0.07, height: 0.3),
                    confidence: 1, timestamp: time, poseKeypoints: nil,
                    faceBoundingBox: CGRect(x: 0.42, y: 0.5, width: 0.03, height: 0.04),
                    faceLandmarkRatios: nil)
            }
            _ = composer.tick(detections: persons, timestamp: time, pixelBuffer: pixels,
                observationID: observation, observationTimestamp: time,
                excludedFromReacquisition: excluded)
        }
        func complete(_ distances: [UUID: Float] = [:]) async {
            let task = composer.reacquisitionTaskForTesting
            await worker.release(distances)
            await task?.value
            #expect(!composer.reacquisitionBatchInFlightForTesting)
        }
        /// The candidates of the batch the last tick started. Records an issue
        /// instead of waiting forever when no batch was scheduled.
        func nextBatch() async -> [UUID]? {
            guard composer.reacquisitionBatchInFlightForTesting else {
                Issue.record("Expected a scoring batch to be in flight")
                return nil
            }
            return await worker.started()
        }
        func recoverB() async {
            for _ in 0..<3 {
                tick([a, b], excluded: [a])
                guard composer.reacquisitionBatchInFlightForTesting else {
                    Issue.record("Legitimate B did not get a scoring slot")
                    return
                }
                let ids = await worker.started()
                #expect(ids == [b])
                await complete()
            }
            tick([b], excluded: [a])
            #expect(composer.manualLockedTargetID == b)
        }
        func expectNoA() {
            #expect(composer.manualLockedTargetID != a)
            switch composer.lockState {
            case .hold, .wideWaiting: break
            default: Issue.record("Expected recovery to remain unbound")
            }
        }
    }

    @Test func excludedCandidateNeverReachesWorker() async throws {
        let f = try Fixture()
        f.tick([f.a], excluded: [f.a])
        #expect(f.composer.reacquisitionTaskForTesting == nil)
        #expect(!f.composer.reacquisitionBatchInFlightForTesting)
        f.expectNoA()
        if f.composer.reacquisitionTaskForTesting != nil {
            _ = await f.worker.started()
            await f.complete()
        }
    }

    @Test(arguments: [false, true])
    func witnessChangeRejectsPausedJob(andWiden: Bool) async throws {
        let f = try Fixture()
        f.tick([f.a])
        #expect(await f.worker.started() == [f.a])
        let revision = f.composer.recoveryVisibilityRevisionForTesting
        if andWiden { f.time += ShotComposer.holdDuration }
        f.tick([f.a], excluded: [f.a])
        #expect(f.composer.recoveryVisibilityRevisionForTesting != revision)
        if andWiden {
            guard case .wideWaiting = f.composer.lockState else { Issue.record("Expected wide-waiting") ; await f.complete(); return }
        }
        await f.complete()
        f.expectNoA()
        await f.recoverB()
    }

    @Test func deliveredWinnerDiscardedWhenWitnessChanges() async throws {
        let f = try Fixture()
        for _ in 0..<3 {
            f.tick([f.a])
            #expect(await f.worker.started() == [f.a])
            await f.complete()
        }
        f.tick([f.a], excluded: [f.a])
        f.expectNoA()
        // No old decision should spring back when exclusion disappears.
        f.tick([])
        f.expectNoA()
        await f.recoverB()
    }

    @Test func newLockRejectsPausedJobAndReleasesSlot() async throws {
        let f = try Fixture()
        f.tick([f.a])
        #expect(await f.worker.started() == [f.a])
        let generation = f.composer.identityGenerationForTesting
        let newSubject = UUID()
        f.composer.lockTarget(newSubject)
        f.composer.forceTrackingForTesting(readyGallery: true)
        #expect(f.composer.identityGenerationForTesting != generation)
        await f.complete()
        #expect(f.composer.manualLockedTargetID == newSubject)
        f.tick([])
        await f.recoverB()
    }

    // A stale batch delivered just after an evidence reset would otherwise be
    // accepted (`ReacquisitionEvidence` forgets its last observation on reset)
    // and count as one win, so the candidate would bind one batch early.
    @Test func staleVisibilityResultIsNotCounted() async throws {
        let f = try Fixture()
        let c = UUID()
        f.tick([f.a])
        #expect(await f.nextBatch() == [f.a])
        // C appears while A's batch is paused: the visible set changes, the
        // revision bumps and the evidence resets.
        f.tick([f.a, c])
        await f.complete()
        for _ in 0..<2 {
            f.tick([f.a, c])
            #expect(await f.nextBatch() == [f.a, c])
            await f.complete([c: 0.60])
        }
        // This tick would drain a pending winner; two fresh wins are not enough.
        f.tick([f.a, c])
        #expect(f.composer.manualLockedTargetID != f.a)
        #expect(await f.nextBatch() == [f.a, c])
        await f.complete([c: 0.60])
        f.tick([f.a, c])
        #expect(f.composer.manualLockedTargetID == f.a)
    }

    // Through real scheduling, a lock change bumps the generation and the
    // visibility revision together (`invalidateIdentityWork`), so either check
    // rejects this batch. `staleGenerationAloneIsRejected` covers the
    // generation check on its own.
    @Test func staleGenerationResultIsNotCounted() async throws {
        let f = try Fixture()
        f.tick([f.a])
        #expect(await f.nextBatch() == [f.a])
        let generation = f.composer.identityGenerationForTesting
        f.composer.lockTarget(UUID())
        f.composer.forceTrackingForTesting(readyGallery: true)
        f.tick([])
        #expect(f.composer.identityGenerationForTesting != generation)
        await f.complete()
        for _ in 0..<2 {
            f.tick([f.a])
            #expect(await f.nextBatch() == [f.a])
            await f.complete()
        }
        f.tick([f.a])
        #expect(f.composer.manualLockedTargetID != f.a)
        #expect(await f.nextBatch() == [f.a])
        await f.complete()
        f.tick([f.a])
        #expect(f.composer.manualLockedTargetID == f.a)
    }

    // Production never changes the generation without the revision, so this
    // drives the completion gate directly: a result carrying a retired
    // generation but the current revision must still be refused.
    @Test func staleGenerationAloneIsRejected() async throws {
        let f = try Fixture()
        f.tick([f.a])
        #expect(await f.nextBatch() == [f.a])
        await f.complete()
        let revision = f.composer.recoveryVisibilityRevisionForTesting
        let current = f.composer.identityGenerationForTesting
        let winning = [ShotComposer.ReacquisitionScore(id: f.a, printDistance: 0.10, landmarkDistance: 0.01)]
        for observation: UInt64 in 100..<103 {
            #expect(!f.composer.finishReacquisitionScoring(generation: current &- 1,
                visibilityRevision: revision, observationID: observation, scores: winning))
        }
        f.tick([f.a])
        #expect(f.composer.manualLockedTargetID != f.a)
        if f.composer.reacquisitionBatchInFlightForTesting {
            _ = await f.nextBatch()
            await f.complete()
        }
    }
}
