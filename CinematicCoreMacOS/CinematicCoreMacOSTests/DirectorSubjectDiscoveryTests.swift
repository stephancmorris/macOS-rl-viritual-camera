import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Synthetic software evidence only. No workload budget or rig qualification.
struct DirectorSubjectDiscoveryTests {
    private func configuration(rate: Double = 2, stable: TimeInterval = 0) -> DirectorSubjectDiscovery.Configuration {
        .init(revision: 4, maximumStartsPerSecond: rate, maximumResultAge: 2, maximumStableSpeed: 0.05,
              selectorParameters: .init(lecternZone: .init(minX: 0, minY: 0, maxX: 1, maxY: 1),
                  maximumCentreDistance: 0.5, minimumStableDuration: stable, maximumObservationAge: 2, maximumSampleAge: 2),
              positionHintZone: nil)
    }
    private func binding(program: ChannelID = .a, source: UInt64 = 7, epoch: UInt64 = 2,
                         permitted: Bool = true, acquire: Bool = false) -> DirectorSubjectDiscovery.Binding {
        .init(channel: .b, sourceGeneration: source, controlEpoch: 1, shotRevision: 3, configurationRevision: 4,
              context: .init(program: program, routeGeneration: 9, authorityEpoch: epoch,
                  policyRevision: 1, nominationRevision: 1, permitted: permitted, mayAcquire: acquire))
    }
    private func candidate(_ id: UUID = UUID(), x: CGFloat = 0.45) -> DirectorSubjectDiscovery.Candidate {
        .init(id: id, bounds: .init(x: x, y: 0.2, width: 0.1, height: 0.5))
    }

    @Test func missingInvalidAndProgramBudgetsNeverRequestWork() {
        var state = DirectorSubjectDiscovery.State()
        let observation1 = state.request(binding: binding(), configuration: configuration(), now: 10)
        #expect(observation1 == nil)
        for rate in [0, -1, Double.nan, Double.infinity, Double.leastNonzeroMagnitude] {
            let invalid = configuration(rate: rate)
            state.configure(invalid)
            #expect(!invalid.isValid)
            let observation2 = state.request(binding: binding(), configuration: invalid, now: 10)
            #expect(observation2 == nil)
        }
        state.configure(configuration())
        let observation3 = state.request(binding: binding(program: .b), configuration: configuration(), now: 10)
        #expect(observation3 == nil)
        let observation4 = state.request(binding: binding(permitted: false), configuration: configuration(), now: 10)
        #expect(observation4 == nil)
    }

    @Test func actualStartsDoNotBurstAfterPermitDelayOrRetirement() throws {
        var state = DirectorSubjectDiscovery.State()
        state.configure(configuration())
        let firstRequest = state.request(binding: binding(), configuration: configuration(), now: 10)
        let first = try #require(firstRequest)
        let observation5 = state.request(binding: binding(), configuration: configuration(), now: 10.1)
        #expect(observation5 == nil)
        // A scheduler stall delays the actual first start by ninety seconds.
        #expect(first.begin(at: 100))
        first.finish(at: 100.01)
        let secondRequest = state.request(binding: binding(), configuration: configuration(), now: 100.1)
        let second = try #require(secondRequest)
        #expect(!second.begin(at: 100.1))
        state.retire()
        let thirdRequest = state.request(binding: binding(epoch: 3), configuration: configuration(), now: 100.2)
        let third = try #require(thirdRequest)
        #expect(!third.begin(at: 100.2))
        let fourthRequest = state.request(binding: binding(epoch: 3), configuration: configuration(), now: 101)
        let fourth = try #require(fourthRequest)
        #expect(fourth.begin(at: 101))
    }

    @Test func pendingCancellationAndRunningOverlapAreDifferentTerminalOutcomes() {
        let gate = DirectorSubjectDiscovery.StartGate(maximumStartsPerSecond: 2)
        let pending = DirectorSubjectDiscovery.WorkToken(startGate: gate)
        #expect(pending.retire() == .pending)
        #expect(!pending.begin(at: 10))
        let running = DirectorSubjectDiscovery.WorkToken(startGate: gate)
        #expect(running.begin(at: 10))
        #expect(running.retire() == .running)
        running.finish(at: 11)
        #expect(!running.mayPublish)
        #expect(running.retire() == .alreadyRetired)
        var state = DirectorSubjectDiscovery.State()
        state.recordRetirement(.pending); state.recordRetirement(.running); state.recordRetirement(.alreadyRetired)
        #expect(state.snapshot.statistics.cancelledBeforeStart == 1)
        #expect(state.snapshot.statistics.retiredWhileRunning == 1)
    }

    @Test func staleSourceAuthorityAndMalformedResultsCannotReplaceCurrentPick() throws {
        let config = configuration(), person = candidate()
        var state = DirectorSubjectDiscovery.State()
        state.configure(config)
        let requested = state.request(binding: binding(), configuration: config, now: 10)
        _ = try #require(requested)
        let observation6 = state.ingest([person], capturedAt: 10, now: 10, binding: binding(), configuration: config)
        #expect(observation6 != nil)
        let observation7 = state.ingest([candidate()], capturedAt: 10, now: 10, binding: binding(source: 8), configuration: config)
        #expect(observation7 == nil)
        let observation8 = state.ingest([candidate()], capturedAt: 10, now: 10, binding: binding(epoch: 3), configuration: config)
        #expect(observation8 == nil)
        let observation9 = state.ingest([candidate()], capturedAt: 10, now: 12.1, binding: binding(), configuration: config)
        #expect(observation9 == nil)
        let bad = DirectorSubjectDiscovery.Candidate(id: UUID(), bounds: .init(x: -1, y: 0, width: 2, height: 1))
        let observation10 = state.ingest([bad], capturedAt: 10, now: 10, binding: binding(), configuration: config)
        #expect(observation10 == nil)
        #expect(state.snapshot.selected?.subject == person.id)
        let revision = state.snapshot.selectionRevision
        state.expireSnapshot(at: 12.01, maximumAge: 2)
        #expect(state.snapshot.selected == nil && state.snapshot.candidates.isEmpty)
        #expect(state.snapshot.selectionRevision > revision)
    }

    @Test func retirementIsIdempotentAndNewAuthorityCannotReuseAnOldSelectionBinding() throws {
        let config = configuration(), original = candidate(), replacement = candidate()
        var state = DirectorSubjectDiscovery.State()
        state.configure(config)
        let emptyRevision = state.snapshot.selectionRevision
        state.retire()
        #expect(state.snapshot.selectionRevision == emptyRevision)
        let oldRequest = state.request(binding: binding(), configuration: config, now: 10)
        let oldToken = try #require(oldRequest)
        _ = state.ingest([original], capturedAt: 10, now: 10, binding: binding(), configuration: config)
        let selectedRevision = state.snapshot.selectionRevision
        oldToken.retire()
        state.retire()
        let retiredRevision = state.snapshot.selectionRevision
        #expect(retiredRevision > selectedRevision && state.snapshot.selected == nil)
        for _ in 0..<50 { state.retire() }
        #expect(state.snapshot.selectionRevision == retiredRevision)
        let nextRequest = state.request(binding: binding(epoch: 3), configuration: config, now: 11)
        _ = try #require(nextRequest)
        _ = state.ingest([replacement], capturedAt: 11, now: 11, binding: binding(epoch: 3), configuration: config)
        #expect(state.snapshot.selectionRevision > retiredRevision)
        #expect(state.snapshot.selected?.subject == replacement.id)
        let stale = state.ingest([original], capturedAt: 11, now: 11, binding: binding(), configuration: config)
        #expect(stale == nil && state.snapshot.selected?.subject == replacement.id)
        #expect(!oldToken.mayPublish)
    }

    @Test func stabilityIsMeasuredMotionAndSeveralPlausiblePeopleRemainAmbiguous() throws {
        let config = configuration(stable: 1), id = UUID()
        var state = DirectorSubjectDiscovery.State()
        state.configure(config)
        let requested = state.request(binding: binding(), configuration: config, now: 10)
        _ = try #require(requested)
        let observation11 = state.ingest([candidate(id)], capturedAt: 10, now: 10, binding: binding(), configuration: config)
        #expect(observation11 == .abstain(.noPlausibleSubject))
        let selected = state.ingest([candidate(id)], capturedAt: 11, now: 11, binding: binding(), configuration: config)
        if case .selected(let value) = selected { #expect(value.subject == id) } else { Issue.record("Stable presenter was not selected") }
        let observation12 = state.ingest([candidate(id, x: 0.7)], capturedAt: 12, now: 12, binding: binding(), configuration: config)
        #expect(observation12 == .abstain(.noPlausibleSubject))
        let two = [candidate(), candidate(x: 0.6)]
        _ = state.ingest(two, capturedAt: 13, now: 13, binding: binding(), configuration: config)
        if case .ambiguous(let ids) = state.ingest(two, capturedAt: 14, now: 14, binding: binding(), configuration: config) {
            #expect(ids.count == 2)
        } else { Issue.record("Several plausible people must remain ambiguous") }
    }
}

@MainActor struct DirectorSubjectDiscoveryIntegrationTests {
    private final class ContextBox {
        var program: ChannelID = .a
        var acquire = false
        var permitted = true
        var context: DirectorSubjectDiscovery.Context {
            .init(program: program, routeGeneration: 1, authorityEpoch: 1, policyRevision: 1,
                  nominationRevision: 1, permitted: permitted, mayAcquire: acquire)
        }
    }
    private func configuration(observationAge: TimeInterval = 2) -> DirectorSubjectDiscovery.Configuration {
        .init(revision: 1, maximumStartsPerSecond: 1, maximumResultAge: 2, maximumStableSpeed: 0.1,
              selectorParameters: .init(lecternZone: .init(minX: 0, minY: 0, maxX: 1, maxY: 1),
                  maximumCentreDistance: 0.5, minimumStableDuration: 0, maximumObservationAge: observationAge, maximumSampleAge: 2),
              positionHintZone: nil)
    }
    private func person() -> PersonDetector.DetectedPerson {
        .init(id: UUID(), boundingBox: .init(x: 0.4, y: 0.1, width: 0.2, height: 0.7), confidence: 0.9,
              timestamp: 100, poseKeypoints: nil, faceBoundingBox: nil, faceLandmarkRatios: nil)
    }
    private func rig() -> (ShowCoordinator, CameraManager, ContextBox) {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        let b = show.addChannel(.b), context = ContextBox()
        b.setRunningForTesting(true)
        b.configureSubjectDiscoveryForStudy(configuration(), eligibility: { context.context })
        return (show, b, context)
    }

    @Test func normalAppRemainsPassiveAndExplicitScanPermissionDoesNotAcquire() {
        let (show, b, context) = rig()
        #expect(show.channelA.currentDetectionPlan(detectionRunsThisFrame: true).mode == .off)
        #expect(b.currentDetectionPlan(detectionRunsThisFrame: true).mode == .discovery)
        #expect(!b.acceptSubjectDiscoveryForTesting([person()], capturedAt: 100, now: 100))
        #expect(b.manualLockedTargetID == nil && b.subjectDiscoverySnapshot.selected != nil)
        context.program = .b
        #expect(b.currentDetectionPlan(detectionRunsThisFrame: true).mode == .off)
        #expect(!b.acceptSubjectDiscoveryForTesting([person()], capturedAt: 101, now: 101))
    }

    @Test func snapshotExpiresAtTheShorterObservationBoundWithoutAnotherFrame() {
        let (show, b, context) = rig()
        defer { _ = show.channel(.b) }
        b.configureSubjectDiscoveryForStudy(configuration(observationAge: 0.2), eligibility: { context.context })
        // It already took 150 ms to obtain this candidate. UI lifetime must
        // count from capturedAt, not start a fresh expiry at completion.
        let acquired = b.acceptSubjectDiscoveryForTesting([person()], capturedAt: 100, now: 100.15)
        #expect(!acquired && b.subjectDiscoverySnapshot(at: 100.19).selected != nil)
        let expired = b.subjectDiscoverySnapshot(at: 100.21)
        #expect(expired.selected == nil && expired.candidates.isEmpty)
        let retiredRevision = expired.selectionRevision
        #expect(b.subjectDiscoverySnapshot(at: 101).selectionRevision == retiredRevision)
    }

    @Test func allowedPickUsesNormalAcquisitionAndManualNominationSupersedesItsOrigin() throws {
        let (show, b, context) = rig()
        defer { _ = show.channel(.b) }
        context.acquire = true
        let picked = person()
        #expect(b.acceptSubjectDiscoveryForTesting([picked], capturedAt: 100, now: 100))
        #expect(b.manualLockedTargetID == picked.id)
        #expect(b.directorDiscoveredSubject?.subject == picked.id)
        #expect(b.recoveryState.phase == .acquiring)
        #expect(!b.recoveryState.galleryReady)
        #expect(b.currentDetectionPlan(detectionRunsThisFrame: true).mode == .acquiring)
        b.retireSubjectDiscovery() // A Take retires discovery, not the acquired tracking identity.
        #expect(b.directorDiscoveredSubject?.subject == picked.id)
        b.retargetSubject(at: .init(x: 0.8, y: 0.5))
        #expect(b.directorDiscoveredSubject == nil && b.operatorGestureInProgress)
        #expect(!b.acceptSubjectDiscoveryForTesting([person()], capturedAt: 101, now: 101))
    }

    @Test func gestureSourceLossStopAndExpiredResultRefuseTheAcquireBoundary() {
        let (show, b, context) = rig()
        defer { _ = show.channel(.b) }
        context.acquire = true
        b.setOperatorGestureForTesting(true)
        #expect(!b.acceptSubjectDiscoveryForTesting([person()], capturedAt: 100, now: 100))
        b.setOperatorGestureForTesting(false)
        b.setSourceMissingForTesting(true)
        #expect(!b.acceptSubjectDiscoveryForTesting([person()], capturedAt: 100, now: 100))
        b.setSourceMissingForTesting(false)
        #expect(!b.acceptSubjectDiscoveryForTesting([person()], capturedAt: 100, now: 103))
        b.stopCapture()
        #expect(!b.acceptSubjectDiscoveryForTesting([person()], capturedAt: 104, now: 104))
        #expect(b.directorDiscoveredSubject == nil)
    }

    @Test(arguments: [TakeOrigin.operatorUI, .director, .fallback])
    func everyRealTakeOriginRetiresDiscoveryWithoutRetiringAcquiredIdentity(_ origin: TakeOrigin) {
        let (show, camera, context) = rig()
        let proposed = person()
        let didAcquire = camera.acceptSubjectDiscoveryForTesting([proposed], capturedAt: 100, now: 100)
        #expect(!didAcquire && camera.subjectDiscoverySnapshot.selected?.subject == proposed.id)
        _ = show.take(origin: origin)
        #expect(camera.subjectDiscoverySnapshot.selected == nil && camera.subjectDiscoverySnapshot.candidates.isEmpty)
        context.acquire = true
        let acquired = camera.acceptSubjectDiscoveryForTesting([proposed], capturedAt: 101, now: 101)
        #expect(acquired && camera.manualLockedTargetID == proposed.id)
        _ = show.take(origin: origin)
        #expect(camera.manualLockedTargetID == proposed.id && camera.recoveryState.phase == .acquiring)
        #expect(camera.directorDiscoveredSubject?.subject == proposed.id)
    }

    private final class Work: @unchecked Sendable {
        let stream: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation
        private let finish = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var count = 0
        init() {
            let values = AsyncStream<Void>.makeStream()
            stream = values.stream; continuation = values.continuation
        }
        func run() {
            lock.lock(); count += 1; lock.unlock()
            continuation.yield(())
            finish.wait()
        }
        func release() { finish.signal() }
        var starts: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
    private func pixels() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        return try #require(buffer)
    }

    @Test(.timeLimit(.minutes(1))) func cancellingDiscoveryWaiterPreservesRenderWaiterAndRunningPermits() async throws {
        let scheduler = FrameWorkScheduler()
        let perceptionGrant = await scheduler.acquire(.perception, for: .a)
        let renderGrant = await scheduler.acquire(.render, for: .a)
        let perception = try #require(perceptionGrant)
        let render = try #require(renderGrant)
        let discoveryWaiter = Task { await scheduler.acquire(.perception, for: .b) }
        let renderWaiter = Task { await scheduler.acquire(.render, for: .b) }
        while (scheduler.waitingChannels(.perception) != [.b] || scheduler.waitingChannels(.render) != [.b]), !Task.isCancelled {
            await Task.yield()
        }
        scheduler.cancelWaiting(.perception, for: .b)
        let cancelled = await discoveryWaiter.value
        #expect(cancelled == nil)
        #expect(scheduler.waitingChannels(.perception).isEmpty)
        #expect(scheduler.waitingChannels(.render) == [.b])
        #expect(scheduler.runningPermit(.perception) == perception)
        #expect(scheduler.runningPermit(.render) == render)
        scheduler.release(perception)
        scheduler.release(render)
        let renderNext = await renderWaiter.value
        #expect(renderNext?.channel == .b)
        if let renderNext { scheduler.release(renderNext) }
        #expect(scheduler.runningPermit(.perception) == nil && scheduler.runningPermit(.render) == nil)
        #expect(scheduler.waitingChannels(.perception).isEmpty && scheduler.waitingChannels(.render).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func detectorExecutorSkipsRetiredPendingCallAndRejectsRunningCompletion() async throws {
        let detector = PersonDetector(), work = Work()
        detector.discoveryVisionForTesting = { work.run() }
        let gate = DirectorSubjectDiscovery.StartGate(maximumStartsPerSecond: 1000)
        let retired = DirectorSubjectDiscovery.WorkToken(startGate: gate)
        #expect(retired.retire() == .pending)
        let first = await detector.processFrame(try pixels(), plan: .init(mode: .discovery, roi: nil), discoveryToken: retired)
        #expect(first.isEmpty && work.starts == 0 && retired.outcome.startedAt == nil)
        let token = DirectorSubjectDiscovery.WorkToken(startGate: gate), buffer = try pixels()
        let task = Task { await detector.processFrame(buffer, plan: .init(mode: .discovery, roi: nil), discoveryToken: token) }
        for await _ in work.stream { break }
        #expect(token.retire() == .running)
        work.release()
        let result = await task.value
        #expect(result.isEmpty && work.starts == 1 && !token.mayPublish)
        #expect(detector.stats.totalFramesProcessed == 0)
    }
}
