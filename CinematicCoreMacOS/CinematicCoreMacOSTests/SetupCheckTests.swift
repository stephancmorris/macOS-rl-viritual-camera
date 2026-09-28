//
//  SetupCheckTests.swift
//  CinematicCoreMacOSTests
//
//  PREFLIGHT card: metric fixtures for a healthy run, overload, missing
//  samples and thermal pressure; cancellation; warm-up; and that a short
//  sample never claims more than a provisional verdict.
//

import Foundation
import Testing
@testable import Alfie

private func window(
    seconds: Double = 5,
    admitted: Int = 250,
    gateSkipped: UInt64 = 0,
    handoff: Int? = nil,
    frameMS: Double = 8,
    detections: Int = 125,
    footprint: Double = 500,
    captureDropped: Int = 0,
    renderFailed: Int = 0,
    refused: Int = 0,
    kind: DiagnosticsWindowKind = .full
) -> DiagnosticsWindow {
    var w = DiagnosticsWindow()
    w.kind = kind
    w.windowSeconds = seconds
    w.footprintMB = footprint
    w.frameMeanMS = frameMS
    w.frameMaxMS = frameMS * 2
    w.detections = detections
    w.visionMeanMS = 16
    w.observationMeanMS = 30
    w.window = PipelineCounters(
        admitted: admitted, gateSkipped: gateSkipped, captureDropped: captureDropped,
        renderFailed: renderFailed, routed: admitted, noRoute: 0,
        handoffAccepted: handoff ?? admitted - refused, handoffRefused: refused, repeated: renderFailed)
    return w
}

private let stage50 = CapabilityContext(
    captureFPS: 50, showStandard: "1080p50", showFPS: 50, belowShowRate: false,
    source: "Elgato 4K X · stage", route: "Program Display")

private func samples(_ windows: [DiagnosticsWindow], thermal: ThermalLevel = .nominal) -> [CapabilitySample] {
    windows.map { CapabilitySample(window: $0, thermal: thermal) }
}

struct CapabilityReportTests {

    @Test func healthyRunIsSupportedButOnlyProvisionally() {
        let report = CapabilityReport.evaluate(samples: samples(Array(repeating: window(), count: 4)), context: stage50)
        #expect(report.verdict == .supported)
        #expect(report.reasons.isEmpty)
        #expect(report.verdict.title.contains("provisional"))
        #expect(CapabilityReport.disclaimer.contains("60-minute"))
        #expect(abs(report.measured.deliveredFPS - 50) < 0.01)
    }

    @Test func overloadIsLimitedWithMeasuredReasons() {
        // 40 fps admitted + 8 fps skipped = 48 delivered; 19 ms frames.
        let overloaded = window(admitted: 200, gateSkipped: 40, frameMS: 19, captureDropped: 3, renderFailed: 1)
        let report = CapabilityReport.evaluate(samples: samples(Array(repeating: overloaded, count: 4)), context: stage50)
        #expect(report.verdict == .limited)
        let codes = Set(report.reasons.map(\.code))
        #expect(codes.isSuperset(of: ["capture.cadence", "pipeline.gateSkips", "pipeline.frameTime", "capture.dropped", "render.failed"]))
        let cadence = report.reasons.first { $0.code == "capture.cadence" }
        #expect(cadence?.message == "Source delivered 48.0 fps; Alfie configured 50 fps.")
    }

    @Test func tooFewWindowsIsUnverified() {
        let report = CapabilityReport.evaluate(samples: samples([window(), window()]), context: stage50)
        #expect(report.verdict == .unverified)
        #expect(report.reasons.contains { $0.code == "sample.short" && $0.kind == .unknown })
    }

    @Test func missingFramesIsUnverifiedNotSupported() {
        let empty = window(admitted: 0, handoff: 0, detections: 0)
        let report = CapabilityReport.evaluate(samples: samples(Array(repeating: empty, count: 4)), context: stage50)
        #expect(report.verdict == .unverified)
        #expect(report.reasons.contains { $0.code == "sample.noFrames" })
    }

    @Test func detectionNotExercisedIsUnverified() {
        let report = CapabilityReport.evaluate(
            samples: samples(Array(repeating: window(detections: 0), count: 4)), context: stage50)
        #expect(report.verdict == .unverified)
        #expect(report.reasons.contains { $0.code == "sample.noDetection" })
    }

    @Test func unknownCaptureRateIsUnverified() {
        var context = stage50
        context.captureFPS = nil
        let report = CapabilityReport.evaluate(samples: samples(Array(repeating: window(), count: 4)), context: context)
        #expect(report.verdict == .unverified)
        #expect(report.reasons.contains { $0.code == "source.rateUnknown" })
    }

    @Test func seriousThermalPressureIsLimited() {
        let report = CapabilityReport.evaluate(
            samples: samples(Array(repeating: window(), count: 4), thermal: .serious), context: stage50)
        #expect(report.verdict == .limited)
        #expect(report.reasons.contains { $0.code == "system.thermal" })
    }

    @Test func fairThermalIsANoteOnly() {
        let report = CapabilityReport.evaluate(
            samples: samples(Array(repeating: window(), count: 4), thermal: .fair), context: stage50)
        #expect(report.verdict == .supported)
        #expect(report.reasons.map(\.kind) == [.note])
    }

    @Test func memoryGrowthIsLimited() {
        let windows = (0..<4).map { window(footprint: 500 + Double($0) * 10) } // 10 MB / 5 s = 120 MB/min
        let report = CapabilityReport.evaluate(samples: samples(windows), context: stage50)
        #expect(report.verdict == .limited)
        #expect(abs(report.measured.memoryGrowthMBPerMinute - 120) < 0.01)
    }

    @Test func refusedHandoffsAreLimited() {
        let report = CapabilityReport.evaluate(
            samples: samples(Array(repeating: window(refused: 2), count: 4)), context: stage50)
        #expect(report.reasons.contains { $0.code == "output.refused" })
        #expect(report.verdict == .limited)
    }

    @Test func webcamBelowShowRateIsJudgedAgainstItsOwnRate() {
        let webcam = CapabilityContext(
            captureFPS: 30, showStandard: "1080p50", showFPS: 50, belowShowRate: true,
            source: "C920 · webcam", route: "Virtual Camera")
        let report = CapabilityReport.evaluate(
            samples: samples(Array(repeating: window(admitted: 150, frameMS: 12, detections: 75), count: 4)),
            context: webcam)
        #expect(report.verdict == .supported)
        #expect(report.reasons.first?.code == "source.belowShowRate")
        #expect(report.reasons.first?.kind == .note)
    }
}

@MainActor
struct SetupCheckTests {
    @Test func warmUpWindowsAreDiscardedThenSampleFinishes() throws {
        let check = SetupCheck(warmUpSeconds: 5, sampleWindows: 3)
        check.begin(now: 100)
        #expect(check.phase == .warmingUp)
        // Window closing at 104 began at 99: before the check, discarded.
        check.ingest(window(), thermal: .nominal, now: 104, context: stage50)
        #expect(check.phase == .warmingUp)
        // Began at 104: still inside the 5 s warm-up, discarded.
        check.ingest(window(), thermal: .nominal, now: 109, context: stage50)
        #expect(check.phase == .warmingUp)
        check.ingest(window(), thermal: .nominal, now: 114, context: stage50)
        #expect(check.phase == .sampling(collected: 1, needed: 3))
        check.ingest(window(), thermal: .nominal, now: 119, context: stage50)
        check.ingest(window(), thermal: .nominal, now: 124, context: stage50)
        guard case .finished(let report) = check.phase else {
            Issue.record("expected finished, got \(check.phase)")
            return
        }
        #expect(report.verdict == .supported)
        #expect(report.measured.windows == 3)
    }

    @Test func captureStopCancelsTheCheck() {
        let check = SetupCheck(warmUpSeconds: 0, sampleWindows: 3)
        check.begin(now: 0)
        check.ingest(window(), thermal: .nominal, now: 5, context: stage50)
        check.ingest(window(kind: .partial), thermal: .nominal, now: 7, context: stage50)
        #expect(check.phase == .cancelled(reason: "Capture stopped during the check."))
        // Later windows are ignored once cancelled.
        check.ingest(window(), thermal: .nominal, now: 12, context: stage50)
        #expect(check.phase == .cancelled(reason: "Capture stopped during the check."))
    }

    @Test func newCaptureResettingTheWindowCancels() {
        let check = SetupCheck(warmUpSeconds: 0, sampleWindows: 3)
        check.begin(now: 0)
        check.ingest(nil, thermal: .nominal, now: 1, context: stage50)
        #expect(check.phase == .cancelled(reason: "Capture stopped during the check."))
    }

    @Test func operatorCancel() {
        let check = SetupCheck()
        check.begin(now: 0)
        check.cancel()
        #expect(check.phase == .cancelled(reason: "Cancelled by the operator."))
    }

    @Test func refusesToStartWithoutCapture() {
        let check = SetupCheck()
        check.start(output: ProgramOutputManager(sinks: []), isCaptureRunning: false)
        guard case .cancelled(let reason) = check.phase else {
            Issue.record("expected cancelled")
            return
        }
        #expect(reason.contains("Start capture"))
    }

    @Test func checkNeverChangesTheShowStandard() {
        let before = ShowStandard.activeOrCurrent
        let check = SetupCheck(warmUpSeconds: 0, sampleWindows: 1)
        check.begin(now: 0)
        check.ingest(window(), thermal: .nominal, now: 5, context: stage50)
        #expect(ShowStandard.activeOrCurrent == before)
    }
}
