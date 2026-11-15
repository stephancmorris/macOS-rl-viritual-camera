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
    func release() {
        let scores = (request ?? []).map {
            ShotComposer.ReacquisitionScore(id: $0, printDistance: 0.10, landmarkDistance: 0.01)
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
        func complete() async {
            let task = composer.reacquisitionTaskForTesting
            await worker.release()
            await task?.value
            #expect(!composer.reacquisitionBatchInFlightForTesting)
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
}
