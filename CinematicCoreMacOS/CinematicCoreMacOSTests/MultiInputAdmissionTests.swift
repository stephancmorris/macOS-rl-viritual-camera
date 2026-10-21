//
//  MultiInputAdmissionTests.swift
//  CinematicCoreMacOSTests
//
//  ADMISSION card: fixtures for capture, render, perception, CPU, memory and
//  heat bottlenecks and for no evidence; unknown ≠ supported; certified only
//  via MULTI-QA; fingerprint changes invalidate; the output rate never moves.
//

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

    @Test(arguments: [nil, 0, -1, Double.nan, Double.infinity, -Double.infinity] as [Double?])
    func unusablePreviewRateCannotPass(rate: Double?) {
        var invalid = context
        invalid.previewCaptureFPS = rate
        let result = PairAdmission.evaluate(
            program: Array(repeating: CapabilitySample(window: window(), thermal: .nominal), count: 4),
            preview: Array(repeating: PreviewAdmissionSample(windowSeconds: 5, renderedFrames: 250), count: 4),
            context: invalid)
        #expect(result.status == .unknown)
        #expect(result.reasons.contains { $0.code == "preview.rateUnknown" })
    }

    @Test func malformedPreviewEvidenceCannotPassOrTrap() {
        let healthy = PreviewAdmissionSample(windowSeconds: 5, renderedFrames: 250)
        let invalid: [[PreviewAdmissionSample]] = [
            [], Array(repeating: healthy, count: 3),
            [.init(windowSeconds: .nan, renderedFrames: 250)] + Array(repeating: healthy, count: 3),
            [.init(windowSeconds: .infinity, renderedFrames: 250)] + Array(repeating: healthy, count: 3),
            [.init(windowSeconds: 0, renderedFrames: 250)] + Array(repeating: healthy, count: 3),
            [.init(windowSeconds: -5, renderedFrames: 250)] + Array(repeating: healthy, count: 3),
            [.init(windowSeconds: 5, renderedFrames: -1)] + Array(repeating: healthy, count: 3),
            Array(repeating: .init(windowSeconds: 5, renderedFrames: Int.max), count: 4),
            Array(repeating: .init(windowSeconds: 10, renderedFrames: 500), count: 4)
        ]
        for preview in invalid {
            let result = PairAdmission.evaluate(
                program: Array(repeating: CapabilitySample(window: window(), thermal: .nominal), count: 4),
                preview: preview, context: context)
            #expect(result.status == .unknown)
            #expect(result.reasons.contains { $0.bottleneck == .evidence })
            #expect(result.previewFPS.isFinite)
        }
    }

    @Test func malformedProgramEvidenceCannotPassOrTrap() {
        var invalid: [DiagnosticsWindow] = []
        var value = window(); value.windowSeconds = .nan; invalid.append(value)
        value = window(); value.windowSeconds = 0; invalid.append(value)
        value = window(); value.frameMeanMS = .nan; invalid.append(value)
        value = window(); value.mainMeanMS = .infinity; invalid.append(value)
        value = window(); value.observationMeanMS = -1; invalid.append(value)
        value = window(); value.footprintMB = .nan; invalid.append(value)
        value = window(); value.window.admitted = -1; invalid.append(value)
        value = window(); value.window.admitted = Int.max; invalid.append(value)
        value = window(); value.window.gateSkipped = UInt64.max; invalid.append(value)
        value = window(); value.detections = -1; invalid.append(value)
        value = window(); value.kind = .marker; invalid.append(value)
        value = window(); value.mainMeanMS = .greatestFiniteMagnitude; invalid.append(value)
        for sample in invalid {
            let result = evaluate(sample)
            #expect(result.status == .unknown)
            #expect(result.reasons.contains { $0.bottleneck == .evidence })
        }
    }

    @Test(arguments: [nil, 0, -1, Double.nan, Double.infinity, -Double.infinity] as [Double?])
    func unusableProgramRateCannotPass(rate: Double?) {
        var invalid = context
        invalid.program.captureFPS = rate
        let result = PairAdmission.evaluate(
            program: Array(repeating: CapabilitySample(window: window(), thermal: .nominal), count: 4),
            preview: Array(repeating: PreviewAdmissionSample(windowSeconds: 5, renderedFrames: 250), count: 4),
            context: invalid)
        #expect(result.status == .unknown)
        #expect(result.programReport.verdict == .unverified)
        #expect(result.reasons.contains { $0.code == "program.source.rateUnknown" })
    }

    @Test func invalidThresholdsAndShowRateRemainUnverified() {
        var thresholds = CapabilityThresholds.provisional
        thresholds.deliveredRatioFloor = .nan
        let samples = Array(repeating: CapabilitySample(window: window(), thermal: .nominal), count: 4)
        #expect(CapabilityReport.evaluate(samples: samples, context: context.program,
                                         thresholds: thresholds).verdict == .unverified)
        var invalid = context.program
        invalid.showFPS = .infinity
        #expect(CapabilityReport.evaluate(samples: samples, context: invalid).verdict == .unverified)
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

    @Test func showAdmissionFollowsTheChannelCount() throws {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []), admissionRecords: store())
        #expect(show.admissionDecision == .allowed(certified: false))    // one input: nothing to admit
        show.addChannel(.b)
        #expect(show.admissionDecision == .trialOnly)
        show.channelA.setRunningForTesting(true)
        show.channel(.b)!.setRunningForTesting(true)
        let binding = try #require(show.admissionCheckBinding(preview: .b))
        #expect(show.recordAdmission(evaluate(), for: binding))
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

    private func runningPair() -> ShowCoordinator {
        let defaults = UserDefaults(suiteName: "alfie-admission-mode-\(UUID().uuidString)")!
        defaults.set(OperatorMode.multiCam.rawValue, forKey: OperatorModeStore.key)
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []), admissionRecords: store(),
                                   operatorModes: OperatorModeStore(defaults: defaults, multiviewEnabled: true))
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b).setRunningForTesting(true)
        return show
    }

    @Test func liveModeChangesCancelImmediatelyEvenWhenChangedBack() {
        let show = runningPair()
        show.channel(.b)!.setOperationMode(.manualCrop)
        let check = MultiInputCheck()
        var completed = 0
        check.start(show: show, preview: .b) { _, _ in completed += 1 }
        #expect(check.phase == .warmingUp)
        show.channel(.b)!.setOperationMode(.autoPan)
        guard case .cancelled = check.phase else { Issue.record("expected immediate mode cancellation"); return }
        show.channel(.b)!.setOperationMode(.manualCrop)
        guard case .cancelled = check.phase else { Issue.record("mode restoration must not resume a retired sample"); return }
        #expect(completed == 0)
        #expect(show.admissionStatus == .unknown)
    }

    @Test func operatorModeChangeCancelsDespiteTheSameStageFingerprint() throws {
        let show = runningPair()
        let original = try #require(show.admissionCheckBinding(preview: .b))
        let check = MultiInputCheck()
        check.start(show: show, preview: .b) { _, _ in Issue.record("changed mode must not complete") }
        // Exercise the store's documented internal apply path. The public
        // request correctly refuses leaving Multi Cam while B exists.
        show.operatorModes.select(.singleCam)
        #expect(show.admissionFingerprint() == original.fingerprint)
        guard case .cancelled = check.phase else { Issue.record("expected operator-mode cancellation"); return }
        #expect(!show.recordAdmission(evaluate(), for: original))
    }

    @Test func changedConfigurationCancelsSampleAndCannotRecordItsResult() throws {
        let show = runningPair()
        let binding = try #require(show.admissionCheckBinding(preview: .b))
        let check = MultiInputCheck(warmUpSeconds: 0, sampleWindows: 3)
        check.begin(now: 0, previewCount: 0, binding: binding)
        check.ingest(window(), previewCount: 250, thermal: .nominal, now: 5, context: context, binding: binding)
        show.channel(.b)!.setOperationMode(.autoPan)
        let changed = try #require(show.admissionCheckBinding(preview: .b))
        #expect(changed.fingerprint != binding.fingerprint)
        check.ingest(window(), previewCount: 500, thermal: .nominal, now: 10, context: context, binding: changed)
        guard case .cancelled = check.phase else { Issue.record("expected cancellation on mode change"); return }
        #expect(!show.recordAdmission(evaluate(), for: binding))
        #expect(show.admissionRecords.status(for: binding.fingerprint) == .unknown)
        #expect(show.admissionStatus == .unknown)
    }

    @Test func sameFingerprintAfterSourceRestartStillRejectsOldMeasurement() throws {
        let show = runningPair()
        let binding = try #require(show.admissionCheckBinding(preview: .b))
        let b = show.channel(.b)!
        b.stopCapture()
        b.setRunningForTesting(true)
        let restarted = try #require(show.admissionCheckBinding(preview: .b))
        #expect(restarted.fingerprint == binding.fingerprint)
        #expect(restarted != binding)
        #expect(!show.recordAdmission(evaluate(), for: binding))
        #expect(show.admissionStatus == .unknown)
    }

    @Test func roleRoundTripAndReplacedChannelCannotReviveOldMeasurement() throws {
        let show = runningPair()
        let binding = try #require(show.admissionCheckBinding(preview: .b))
        #expect(show.router.setProgram(.b, expectedRouteGeneration: show.router.routeGeneration))
        #expect(!show.recordAdmission(evaluate(), for: binding))
        #expect(show.router.setProgram(.a, expectedRouteGeneration: show.router.routeGeneration))
        #expect(show.admissionFingerprint() == binding.fingerprint)
        #expect(!show.recordAdmission(evaluate(), for: binding))
        show.removeChannel(.b)
        show.addChannel(.b).setRunningForTesting(true)
        #expect(show.admissionFingerprint() == binding.fingerprint)
        #expect(!show.recordAdmission(evaluate(), for: binding))
        #expect(show.admissionStatus == .unknown)
    }

    @Test func missingSourceAndLateCompletionCannotRecordOrReplaceCurrentRun() throws {
        let show = runningPair()
        let binding = try #require(show.admissionCheckBinding(preview: .b))
        let check = MultiInputCheck(warmUpSeconds: 0, sampleWindows: 3)
        check.begin(now: 0, previewCount: 0, binding: binding)
        show.channel(.b)!.setSourceMissingForTesting(true)
        check.ingest(window(), previewCount: 250, thermal: .nominal, now: 5, context: context,
                     binding: show.admissionCheckBinding(preview: .b))
        guard case .cancelled = check.phase else { Issue.record("expected cancellation on source loss"); return }
        #expect(!show.recordAdmission(evaluate(), for: binding))
        show.channel(.b)!.setSourceMissingForTesting(false)
        show.channel(.b)!.setOperationMode(.autoPan)
        let current = try #require(show.admissionCheckBinding(preview: .b))
        check.begin(now: 5, previewCount: 250, binding: current)
        // A retired callback cannot attach its old measurement to this setup.
        #expect(!show.recordAdmission(evaluate(), for: binding))
        #expect(check.phase == .warmingUp)
        for tick in 1...3 {
            check.ingest(window(), previewCount: UInt64(250 + tick * 250), thermal: .nominal,
                         now: Double(5 + tick * 5), context: context, binding: current)
        }
        guard case .finished(let result) = check.phase else { Issue.record("expected current run to finish"); return }
        #expect(show.recordAdmission(result, for: current))
        #expect(show.admissionRecords.status(for: binding.fingerprint) == .unknown)
        #expect(show.admissionStatus == .provisional)
    }

    @Test func previewCounterResetCancelsInsteadOfWrapping() {
        let check = MultiInputCheck(warmUpSeconds: 0, sampleWindows: 3)
        check.begin(now: 0, previewCount: 1000)
        check.ingest(window(), previewCount: 0, thermal: .nominal, now: 5, context: context)
        guard case .cancelled = check.phase else { Issue.record("expected cancellation on counter reset"); return }
    }

    @Test func admissionNeverChangesTheShowStandard() {
        let before = ShowStandard.activeOrCurrent
        _ = evaluate(window(admitted: 100, frameMS: 30), thermal: .critical)
        #expect(ShowStandard.activeOrCurrent == before)
    }
}
