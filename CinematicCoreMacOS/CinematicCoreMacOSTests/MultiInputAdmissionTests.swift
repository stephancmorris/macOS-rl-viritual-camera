//
//  MultiInputAdmissionTests.swift
//  CinematicCoreMacOSTests
//
//  ADMISSION card: fixtures for capture, render, perception, CPU, memory and
//  heat bottlenecks and for no evidence; unknown ≠ supported; certified only
//  via MULTI-QA; fingerprint changes invalidate; the output rate never moves.
//

import Combine
import Foundation
import Testing
@testable import Alfie

private func window(admitted: Int = 250, gateSkipped: UInt64 = 0, frameMS: Double = 8, mainMS: Double = 4,
                    detections: Int = 125, observationMS: Double = 40, footprint: Double = 500,
                    captureDropped: Int = 0) -> DiagnosticsWindow {
    var w = DiagnosticsWindow()
    w.windowSeconds = 5
    w.footprintMB = footprint
    w.frameMeanMS = frameMS
    w.frameMaxMS = frameMS * 2
    w.mainMeanMS = mainMS
    w.detections = detections
    w.visionMeanMS = 16
    w.observationMeanMS = observationMS
    w.window = PipelineCounters(admitted: admitted, gateSkipped: gateSkipped, captureDropped: captureDropped,
                                routed: admitted, handoffAccepted: admitted)
    return w
}

private let context = PairAdmissionContext(
    program: CapabilityContext(captureFPS: 50, showStandard: "1080p50", showFPS: 50, belowShowRate: false,
                               source: "Cam A", route: "Program Display"),
    previewCaptureFPS: 50)

private func evaluate(_ program: DiagnosticsWindow = window(), thermal: ThermalLevel = .nominal,
                      previewFrames: Int = 250, windows: Int = 4) -> PairAdmissionResult {
    PairAdmission.evaluate(
        program: Array(repeating: CapabilitySample(window: program, thermal: thermal), count: windows),
        preview: Array(repeating: PreviewAdmissionSample(windowSeconds: 5, renderedFrames: previewFrames), count: windows),
        context: context)
}

private func bottlenecks(_ result: PairAdmissionResult) -> Set<AdmissionBottleneck> {
    Set(result.reasons.map(\.bottleneck))
}

struct PairAdmissionTests {
    @Test func healthyPairIsProvisionalNotCertified() {
        let result = evaluate()
        #expect(result.status == .provisional)
        #expect(result.reasons.isEmpty)
        #expect(abs(result.previewFPS - 50) < 0.01)
    }

    @Test(arguments: [nil, Double.nan, -Double.infinity, 0, -1] as [Double?])
    func invalidPreviewCaptureRateStaysUnknown(_ captureFPS: Double?) {
        let result = evaluatePreviewRate(captureFPS)
        #expect(result.programReport.verdict == .supported)
        #expect(result.previewFPS == 50)
        #expect(result.status == .unknown)
        #expect(result.reasons.contains { $0.code == "preview.rateUnknown" && $0.bottleneck == .evidence })
    }

    @Test(arguments: [25.0, 30.0, 60.0])
    func validPreviewCaptureRateUsesItsOwnCadence(_ captureFPS: Double) {
        var ownRate = context
        ownRate.previewCaptureFPS = captureFPS
        let result = PairAdmission.evaluate(
            program: Array(repeating: CapabilitySample(window: window(), thermal: .nominal), count: 4),
            preview: Array(repeating: PreviewAdmissionSample(windowSeconds: 5, renderedFrames: Int(captureFPS * 5)), count: 4),
            context: ownRate)
        #expect(result.status == .provisional)
        #expect(result.reasons.isEmpty)
        #expect(result.previewFPS == captureFPS)
    }

    private func evaluatePreviewRate(_ captureFPS: Double?) -> PairAdmissionResult {
        var unknownRate = context
        unknownRate.previewCaptureFPS = captureFPS
        return PairAdmission.evaluate(
            program: Array(repeating: CapabilitySample(window: window(), thermal: .nominal), count: 4),
            preview: Array(repeating: PreviewAdmissionSample(windowSeconds: 5, renderedFrames: 250), count: 4),
            context: unknownRate)
    }

    @Test func pairWithoutDetectionIsJudgedWhenNoInputDetects() {
        var wideAndPan = context
        wideAndPan.program.expectsDetection = false
        let samples = Array(repeating: CapabilitySample(window: window(detections: 0), thermal: .nominal), count: 4)
        let preview = Array(repeating: PreviewAdmissionSample(windowSeconds: 5, renderedFrames: 250), count: 4)
        #expect(PairAdmission.evaluate(program: samples, preview: preview, context: wideAndPan).status == .provisional)
        // Tracking configurations still need the detection load measured.
        #expect(PairAdmission.evaluate(program: samples, preview: preview, context: context).status == .unknown)
    }

    @Test func captureBottleneck() {
        let result = evaluate(window(admitted: 200, captureDropped: 3))
        guard case .unsupported = result.status else { Issue.record("expected unsupported"); return }
        #expect(bottlenecks(result).contains(.capture))
    }

    @Test func renderBottleneckOnProgram() {
        let result = evaluate(window(gateSkipped: 40, frameMS: 19))
        #expect(bottlenecks(result).contains(.render))
    }

    @Test func renderBottleneckOnPreview() {
        let result = evaluate(previewFrames: 150)       // 30 fps against a 50 fps source
        #expect(result.reasons.contains { $0.code == "preview.render" && $0.bottleneck == .render })
    }

    @Test func perceptionBottleneck() {
        #expect(bottlenecks(evaluate(window(observationMS: 220))).contains(.perception))
    }

    @Test func cpuBottleneck() {
        #expect(bottlenecks(evaluate(window(mainMS: 14))).contains(.cpu))
    }

    @Test func memoryBottleneck() {
        let program = (0..<4).map { CapabilitySample(window: window(footprint: 500 + Double($0) * 10), thermal: .nominal) }
        let result = PairAdmission.evaluate(
            program: program,
            preview: Array(repeating: PreviewAdmissionSample(windowSeconds: 5, renderedFrames: 250), count: 4),
            context: context)
        #expect(bottlenecks(result).contains(.memory))
    }

    @Test func heatBottleneck() {
        #expect(bottlenecks(evaluate(thermal: .serious)).contains(.heat))
    }

    @Test func noEvidenceStaysUnknown() {
        #expect(evaluate(windows: 2).status == .unknown)
        let noPreview = PairAdmission.evaluate(
            program: Array(repeating: CapabilitySample(window: window(), thermal: .nominal), count: 4),
            preview: [], context: context)
        #expect(noPreview.status == .unknown)
        #expect(noPreview.reasons.contains { $0.bottleneck == .evidence })
    }

    @Test func decisionsNeverTreatUnknownAsSupported() {
        #expect(AdmissionDecision.decide(.unknown) == .trialOnly)
        #expect(AdmissionDecision.decide(.provisional) == .allowed(certified: false))
        #expect(AdmissionDecision.decide(.certified) == .allowed(certified: true))
        let reason = AdmissionReason(code: "x", bottleneck: .render, message: "x")
        #expect(AdmissionDecision.decide(.unsupported([reason])) == .refused([reason]))
    }
}

// Select this suite only after the repair; the old formatter traps on Int(infinity).
struct PairAdmissionInfiniteRateTests {
    @Test func finiteRateBeyondIntegerRangeReportsRefusalWithoutTrapping() {
        var enormousRate = context
        enormousRate.previewCaptureFPS = 1e20
        let result = PairAdmission.evaluate(
            program: Array(repeating: CapabilitySample(window: window(), thermal: .nominal), count: 4),
            preview: Array(repeating: PreviewAdmissionSample(windowSeconds: 5, renderedFrames: 250), count: 4),
            context: enormousRate)
        guard case .unsupported = result.status else { Issue.record("Expected a measured cadence refusal"); return }
        #expect(result.reasons.contains {
            $0.code == "preview.render" && $0.message.contains("100000000000000000000.00")
        })
        #expect(CapabilityReport.rate(50) == "50")
        #expect(CapabilityReport.rate(59.94) == "59.94")
    }

    @Test func positiveInfinitePreviewCaptureRateStaysUnknown() {
        var infiniteRate = context
        infiniteRate.previewCaptureFPS = .infinity
        let result = PairAdmission.evaluate(
            program: Array(repeating: CapabilitySample(window: window(), thermal: .nominal), count: 4),
            preview: Array(repeating: PreviewAdmissionSample(windowSeconds: 5, renderedFrames: 250), count: 4),
            context: infiniteRate)
        #expect(result.programReport.verdict == .supported)
        #expect(result.previewFPS == 50)
        #expect(result.status == .unknown)
        #expect(result.reasons.contains { $0.code == "preview.rateUnknown" && $0.bottleneck == .evidence })
    }
}

@MainActor
struct AdmissionRecordTests {
    private func store() -> AdmissionRecordStore {
        AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-admission-\(UUID().uuidString)")!)
    }

    private func fingerprint(mode: String = "track", fps: Double = 50, route: String = "Program Display") -> AdmissionFingerprint {
        AdmissionFingerprint(
            machineModel: "Mac16,1", osVersion: "26.0", showStandard: "1080p50", route: route,
            inputs: [
                .init(channel: "A", deviceModelID: "Elgato", deliveredWidth: 3840, deliveredHeight: 2160,
                      captureFPS: 50, captureProfile: "stage", mode: "track"),
                .init(channel: "B", deviceModelID: "Elgato", deliveredWidth: 1920, deliveredHeight: 1080,
                      captureFPS: fps, captureProfile: "stage", mode: mode),
            ])
    }

    @Test func unmeasuredConfigurationIsUnknown() {
        #expect(store().status(for: fingerprint()) == .unknown)
    }

    @Test func recordedResultIsReturnedForTheSameFingerprintOnly() {
        let store = store()
        store.record(.provisional, for: fingerprint())
        #expect(store.status(for: fingerprint()) == .provisional)
        #expect(store.status(for: fingerprint(mode: "pan")) == .unknown)     // Track+Pan ≠ Track+Track
        #expect(store.status(for: fingerprint(fps: 60)) == .unknown)
        #expect(store.status(for: fingerprint(route: "Virtual Camera")) == .unknown)
    }

    @Test func shortSampleNeverDowngradesACertifiedRecord() {
        let store = store()
        store.markCertified(fingerprint())
        store.record(.provisional, for: fingerprint())
        #expect(store.status(for: fingerprint()) == .certified)
    }

    @Test func recordsFromAnotherPolicyVersionAreIgnored() throws {
        let defaults = UserDefaults(suiteName: "alfie-admission-\(UUID().uuidString)")!
        let old = [fingerprint().key: AdmissionRecordStore.Record(status: .provisional, measuredAt: Date(),
                                                                   policyVersion: AdmissionPolicy.version - 1)]
        defaults.set(try JSONEncoder().encode(old), forKey: "admissionRecords.v1")
        #expect(AdmissionRecordStore(defaults: defaults).status(for: fingerprint()) == .unknown)
    }

    @Test func showAdmissionFollowsTheChannelCount() {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []), admissionRecords: store())
        #expect(show.admissionDecision == .allowed(certified: false))    // one input: nothing to admit
        show.addChannel(.b)
        #expect(show.admissionDecision == .trialOnly)
        show.admissionRecords.record(evaluate().status, for: show.admissionFingerprint())
        #expect(show.admissionDecision == .allowed(certified: false))
        // Changing B's mode changes the fingerprint: back to unknown.
        show.channel(.b)!.setOperationMode(.autoPan)
        #expect(show.admissionDecision == .trialOnly)
    }

    @Test func liveCheckDiscardsWarmUpAndMeasuresPreviewFrames() {
        let check = MultiInputCheck(warmUpSeconds: 5, sampleWindows: 3)
        check.begin(now: 100, previewCount: 1000)
        check.ingest(window(), previewCount: 1250, thermal: .nominal, now: 104, context: context)   // warm-up
        #expect(check.phase == .warmingUp)
        check.ingest(window(), previewCount: 1500, thermal: .nominal, now: 110, context: context)
        check.ingest(window(), previewCount: 1750, thermal: .nominal, now: 115, context: context)
        check.ingest(window(), previewCount: 2000, thermal: .nominal, now: 120, context: context)
        guard case .finished(let result) = check.phase else { Issue.record("expected finished"); return }
        #expect(abs(result.previewFPS - 50) < 0.01)
        #expect(result.status == .provisional)
    }

    @Test func liveCheckCancelsWhenCaptureStops() {
        let check = MultiInputCheck(warmUpSeconds: 0, sampleWindows: 3)
        check.begin(now: 0, previewCount: 0)
        var partial = window()
        partial.kind = .partial
        check.ingest(partial, previewCount: 10, thermal: .nominal, now: 3, context: context)
        #expect(check.phase == .cancelled("Capture stopped during the check."))
    }

    @Test func admissionNeverChangesTheShowStandard() {
        let before = ShowStandard.activeOrCurrent
        _ = evaluate(window(admitted: 100, frameMS: 30), thermal: .critical)
        #expect(ShowStandard.activeOrCurrent == before)
    }
}

#if DEBUG
@MainActor
struct PairCheckProvenanceTests {
    @MainActor
    private struct Rig {
        let suite: String
        let defaults: UserDefaults
        let show: ShowCoordinator
        let check: MultiInputCheck
        let frames: Int

        init() {
            suite = "alfie-pair-provenance-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suite)!
            show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
                                   admissionRecords: AdmissionRecordStore(defaults: defaults))
            check = MultiInputCheck(warmUpSeconds: 0, sampleWindows: 3, clock: { 0 })
            frames = Int(ShowStandard.activeOrCurrent.frameRate * 5)
            for channel in [show.channelA, show.addChannel(.b)] {
                channel.setRunningForTesting(true)
                channel.setAdmissionFormatForTesting(width: 1920, height: 1080,
                                                     fps: ShowStandard.activeOrCurrent.frameRate)
            }
        }

        func start() {
            check.start(show: show, preview: .b) { [weak show] result, binding in
                show?.recordAdmission(result, from: binding) ?? false
            }
        }

        func sample(_ index: Int) {
            check.ingestBoundWindowForTesting(window(admitted: frames), show: show,
                                              previewCount: UInt64(frames * index), thermal: .nominal,
                                              now: Double(index * 5))
        }

        func cleanup() { defaults.removePersistentDomain(forName: suite) }
    }

    enum Change: CaseIterable {
        case mode, profile, dimensions, rate, route, stopped, missing, rolesRoundTrip, modeRoundTrip
    }

    @Test(arguments: Change.allCases)
    func changedPairCancelsWithoutRecording(_ change: Change) throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.start()
        rig.sample(1)
        let b = try #require(rig.show.channel(.b))
        switch change {
        case .mode: b.setOperationMode(.autoPan)
        case .profile: b.shotComposer.config.cinematicFormat = .webcam
        case .dimensions: b.setAdmissionFormatForTesting(width: 1280, height: 720, fps: ShowStandard.activeOrCurrent.frameRate)
        case .rate: b.setAdmissionFormatForTesting(width: 1920, height: 1080, fps: 30)
        case .route: rig.show.programOutput.preferredRoute = .virtualCamera
        case .stopped:
            b.stopCapture()
            b.setRunningForTesting(true) // Same instance resumes; source generation still changed.
        case .missing: b.setSourceMissingForTesting(true)
        case .rolesRoundTrip:
            #expect(rig.show.router.setProgram(.b, expectedRouteGeneration: rig.show.router.routeGeneration))
            #expect(rig.show.router.setProgram(.a, expectedRouteGeneration: rig.show.router.routeGeneration))
        case .modeRoundTrip:
            b.setOperationMode(.autoPan)
            b.setOperationMode(.wide)
        }
        rig.sample(2)
        guard case .cancelled = rig.check.phase else { Issue.record("Changed pair continued sampling"); return }
        #expect(rig.show.admissionRecords.allRecords().isEmpty)
    }

    @Test func replacingPreviewWithTheSameFingerprintCannotContinueTheOldCheck() throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.start()
        rig.sample(1)
        let old = try #require(rig.show.channel(.b))
        let oldGeneration = old.revisions.sourceGeneration
        let original = rig.show.admissionFingerprint()
        rig.show.removeChannel(.b)
        let replacement = rig.show.addChannel(.b)
        replacement.setRunningForTesting(true)
        replacement.setAdmissionFormatForTesting(width: 1920, height: 1080, fps: ShowStandard.activeOrCurrent.frameRate)
        #expect(replacement !== old)
        #expect(replacement.revisions.sourceGeneration == oldGeneration)
        #expect(rig.show.admissionFingerprint() == original)
        rig.check.ingestBoundWindowForTesting(window(admitted: rig.frames), show: rig.show,
                                              previewCount: 0, thermal: .nominal, now: 10)
        #expect(rig.check.phase == .cancelled("Setup changed during the check."))
        #expect(rig.show.admissionRecords.allRecords().isEmpty)
    }

    @Test func setupChangeDuringFinishedPublicationRejectsTheFinalSave() throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.start()
        let original = rig.show.admissionFingerprint()
        let b = try #require(rig.show.channel(.b))
        let observation = rig.check.$phase.sink { phase in
            if case .finished = phase { b.setOperationMode(.autoPan) }
        }
        defer { observation.cancel() }
        rig.sample(1)
        rig.sample(2)
        rig.sample(3)
        #expect(rig.check.phase == .cancelled("Setup changed before the check could be saved."))
        #expect(rig.show.admissionFingerprint() != original)
        #expect(rig.show.admissionRecords.allRecords().isEmpty)
        #expect(rig.show.admissionRecords.status(for: original) == .unknown)
    }

    @Test func refusedBindingCannotBeSavedAfterSetupChangesBack() throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.start()
        let binding = try #require(rig.check.binding)
        let b = try #require(rig.show.channel(.b))
        b.shotComposer.config.cinematicFormat = .webcam
        #expect(!rig.show.recordAdmission(evaluate(), from: binding))
        b.shotComposer.config.cinematicFormat = .stage
        #expect(rig.show.admissionFingerprint() == binding.fingerprint)
        #expect(!rig.show.recordAdmission(evaluate(), from: binding))
        #expect(rig.show.admissionRecords.allRecords().isEmpty)
    }

    @Test func unchangedPairSavesOnlyOnceUnderItsStartingFingerprint() throws {
        let rig = Rig()
        defer { rig.cleanup() }
        var saves = 0
        rig.check.start(show: rig.show, preview: .b) { result, binding in
            saves += 1
            return rig.show.recordAdmission(result, from: binding)
        }
        let binding = try #require(rig.check.binding)
        rig.sample(1)
        rig.sample(2)
        rig.sample(3)
        guard case .finished(let result) = rig.check.phase else { Issue.record("Expected finished check"); return }
        #expect(result.status == .provisional)
        #expect(rig.show.admissionRecords.status(for: binding.fingerprint) == .provisional)
        #expect(rig.show.admissionRecords.allRecords().count == 1)
        #expect(!rig.show.recordAdmission(result, from: binding))
        rig.sample(4)
        #expect(saves == 1)
    }

    @Test func changedContextCannotReuseEarlierWindows() {
        let check = MultiInputCheck(warmUpSeconds: 0, sampleWindows: 3)
        check.begin(now: 0, previewCount: 0)
        check.ingest(window(), previewCount: 250, thermal: .nominal, now: 5, context: context)
        var changed = context
        changed.program.route = "Changed synthetic route"
        check.ingest(window(), previewCount: 500, thermal: .nominal, now: 10, context: changed)
        #expect(check.phase == .cancelled("Setup changed during the check."))
    }

    @Test(arguments: [UInt64(0), UInt64.max])
    func resetOrUnrepresentablePreviewCounterCancelsSafely(_ next: UInt64) {
        let check = MultiInputCheck(warmUpSeconds: 0, sampleWindows: 3)
        check.begin(now: 0, previewCount: 250)
        check.ingest(window(), previewCount: next, thermal: .nominal, now: 5, context: context)
        #expect(check.phase == .cancelled("Preview render counter changed during the check."))
    }

    @Test func nonfiniteResultPublishesOnceAndReturns() {
        let check = MultiInputCheck(warmUpSeconds: 0, sampleWindows: 3)
        var finishedPublications = 0
        let observation = check.$phase.sink { phase in
            if case .finished = phase { finishedPublications += 1 }
        }
        defer { observation.cancel() }
        check.begin(now: 0, previewCount: 0)
        let nonfinite = window(frameMS: .nan)
        for index in 1...3 {
            check.ingest(nonfinite, previewCount: UInt64(250 * index), thermal: .nominal,
                         now: Double(5 * index), context: context)
        }
        guard case .finished(let result) = check.phase else { Issue.record("Expected finished publication"); return }
        #expect(result.programReport.measured.frameWallMeanMS.isNaN)
        #expect(finishedPublications == 1)
        #expect(!check.phase.isRunning)
    }

    enum Reentry: CaseIterable { case startDuringWarmup, startDuringFinish, cancelDuringFinish }

    @Test(arguments: Reentry.allCases)
    func observerTransitionPreservesTheLatestMeasurement(_ reentry: Reentry) throws {
        let rig = Rig()
        defer { rig.cleanup() }
        var entered = false
        var old: PairMeasurementBinding?
        let observation = rig.check.$phase.sink { phase in
            let trigger: Bool
            switch (reentry, phase) {
            case (.startDuringWarmup, .warmingUp), (.startDuringFinish, .finished), (.cancelDuringFinish, .finished):
                trigger = true
            default: trigger = false
            }
            guard trigger, !entered else { return }
            entered = true
            old = rig.check.binding
            if reentry == .cancelDuringFinish { rig.check.cancel() }
            else { rig.start() }
        }
        defer { observation.cancel() }
        rig.start()
        if reentry != .startDuringWarmup {
            rig.sample(1)
            rig.sample(2)
            rig.sample(3)
        }
        #expect(entered)
        #expect(rig.show.admissionRecords.allRecords().isEmpty)
        if reentry == .cancelDuringFinish {
            #expect(rig.check.phase == .cancelled("Cancelled by the operator."))
            #expect(rig.check.binding == nil)
        } else {
            #expect(rig.check.phase == .warmingUp)
            #expect(rig.check.binding !== old)
            // The new callback and sampling state survive the old publisher.
            rig.sample(1)
            rig.sample(2)
            rig.sample(3)
            guard case .finished = rig.check.phase else { Issue.record("Replacement did not finish"); return }
            #expect(rig.show.admissionStatus == .provisional)
        }
    }

    @Test func cancelledMeasurementCannotSaveAfterANewCheckStarts() throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.start()
        let first = try #require(rig.check.binding)
        rig.check.cancel()
        rig.start()
        #expect(rig.check.binding !== first)
        #expect(!rig.show.recordAdmission(evaluate(), from: first))
        #expect(rig.show.admissionRecords.allRecords().isEmpty)
        rig.sample(1)
        rig.sample(2)
        rig.sample(3)
        guard case .finished = rig.check.phase else { Issue.record("New check did not finish"); return }
        #expect(rig.show.admissionStatus == .provisional)
    }

}
#endif
