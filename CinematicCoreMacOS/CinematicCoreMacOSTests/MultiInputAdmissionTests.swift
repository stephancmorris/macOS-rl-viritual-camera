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
        show.recordAdmission(evaluate())
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
