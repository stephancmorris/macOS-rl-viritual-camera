//
//  DiagnosticsLogTests.swift
//  CinematicCoreMacOSTests
//
//  METRICS card: every recorded number names its stage, unit, window and
//  provenance; synthetic counts, repeats and the final partial flush land in
//  the right columns; nothing invents a downstream (presented) rate; and the
//  per-frame instrumentation cost is measured.
//

import CoreVideo
import Foundation
import QuartzCore
import Testing
@testable import Alfie

struct DiagnosticsLogTests {

    // MARK: - Column contract

    @Test func everyColumnIsFullyDefinedAndUnique() {
        let columns = DiagnosticsLog.columns
        #expect(Set(columns.map(\.name)).count == columns.count)
        for column in columns {
            #expect(!column.unit.isEmpty, "\(column.name) has no unit")
            #expect(!column.window.isEmpty, "\(column.name) has no window")
            #expect(!column.provenance.isEmpty, "\(column.name) has no provenance")
        }
        #expect(columns.last?.name == "note")
        #expect(DiagnosticsLog.header == columns.map(\.name).joined(separator: ",") + "\n")
    }

    @Test func frameStagesAreAllRepresented() {
        let stages = Set(DiagnosticsLog.columns.map(\.stage))
        for stage in [MetricStage.captureUpstream, .delivered, .admitted, .render, .routed, .handoff, .repeated, .presented] {
            #expect(stages.contains(stage), "no column for \(stage)")
        }
    }

    @Test func presentedIsDeclaredUnknownNotEstimated() throws {
        let presented = try #require(DiagnosticsLog.columns.first { $0.stage == .presented })
        #expect(presented.provenance.contains("unknown"))
        let fields = named(DiagnosticsLog.rowFields(
            elapsed: 1, clock: "00:00:01", system: system, window: DiagnosticsWindow(), note: ""))
        #expect(fields["presented_fps"] == "unknown")
        // Handoff rate is labelled as host handoff, not presentation.
        let handoff = try #require(DiagnosticsLog.columns.first { $0.name == "handoff_fps" })
        #expect(handoff.provenance.contains("not presentation"))
    }

    // MARK: - Row generation

    private let system = DiagnosticsSystemSample(thermal: "nominal", lowPower: false, cpuCores: 1.5, threads: 42)

    private func named(_ fields: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: zip(DiagnosticsLog.columns.map(\.name), fields))
    }

    @Test func rowFieldsMatchTheColumnTable() {
        var window = DiagnosticsWindow()
        window.kind = .partial
        window.windowSeconds = 2
        window.detections = 10
        window.window = PipelineCounters(
            admitted: 90, gateSkipped: 10, captureDropped: 1, renderFailed: 2,
            routed: 90, noRoute: 3, handoffAccepted: 86, handoffRefused: 1, repeated: 2)
        window.totals = PipelineCounters(
            admitted: 900, gateSkipped: 100, captureDropped: 4, renderFailed: 5,
            routed: 900, noRoute: 6, handoffAccepted: 880, handoffRefused: 7, repeated: 8)

        let raw = DiagnosticsLog.rowFields(elapsed: 12.3, clock: "10:00:00", system: system, window: window, note: "a, b")
        #expect(raw.count == DiagnosticsLog.columns.count)
        let row = named(raw)
        #expect(row["window_kind"] == "partial")
        #expect(row["delivered_window"] == "100")
        #expect(row["admitted_window"] == "90")
        #expect(row["gate_drops_window"] == "10")
        #expect(row["gate_drops_total"] == "100")
        #expect(row["capture_dropped_window"] == "1")
        #expect(row["capture_dropped_total"] == "4")
        #expect(row["render_failed_window"] == "2")
        #expect(row["routed_window"] == "90")
        #expect(row["no_route_window"] == "3")
        #expect(row["frames_window"] == "86")
        #expect(row["frames_total"] == "880")
        #expect(row["handoff_refused_window"] == "1")
        #expect(row["handoff_refused_total"] == "7")
        #expect(row["repeated_window"] == "2")
        #expect(row["repeated_total"] == "8")
        #expect(row["handoff_fps"] == "43.00")
        #expect(row["detector_fps"] == "5.00")
        #expect(row["cpu_pct"] == "150")
        #expect(row["note"] == "\"a, b\"")
    }

    @Test func markerRowsCarryNoMeasurements() {
        let raw = DiagnosticsLog.markerFields(elapsed: 3, clock: "10:00:03", thermal: "fair", lowPower: true, note: "capture stop")
        #expect(raw.count == DiagnosticsLog.columns.count)
        let filled = Set(named(raw).filter { !$0.value.isEmpty }.keys)
        #expect(filled == ["elapsed_s", "clock", "window_kind", "thermal", "low_power", "note"])
        #expect(named(raw)["window_kind"] == "marker")
    }

    // MARK: - Counters

    @Test func windowIsTheDifferenceOfTwoSnapshots() {
        let earlier = PipelineCounters(admitted: 10, gateSkipped: 2, handoffAccepted: 9, repeated: 1)
        let later = PipelineCounters(admitted: 25, gateSkipped: 5, handoffAccepted: 22, repeated: 4)
        let window = later.since(earlier)
        #expect(window.admitted == 15)
        #expect(window.gateSkipped == 3)
        #expect(window.delivered == 18)
        #expect(window.handoffAccepted == 13)
        #expect(window.repeated == 3)
        // A reset between snapshots never yields negative counts.
        #expect(PipelineCounters().since(later) == PipelineCounters())
    }

    // MARK: - Manifest

    @Test func manifestRoundTripsWithIdentityColumnsAndUnknowns() throws {
        let identity = DiagnosticsSessionIdentity(
            build: .init(appVersion: "1.0", buildNumber: "4", sourceFingerprint: "abc", osVersion: "26.0", machineModel: "Mac16,1"),
            source: .init(inputKind: "Live camera", deviceName: "C920", deviceModelID: "UVC", captureProfile: "webcam",
                          requestedWidth: 1920, requestedHeight: 1080, configuredCaptureFPS: 30,
                          captureSelectionReason: "webcam has no format at the show rate; using its fastest HD format",
                          belowShowRate: true, deliveredWidth: 1920, deliveredHeight: 1080),
            output: .init(route: "Virtual Camera", showStandard: "1080p50", showFPS: 50, playoutFPS: 50,
                          presentation: "Virtual Camera: handoff = the route accepted the frame; …"))
        let manifest = DiagnosticsManifest(
            csvFile: "alfie_soak_x.csv", memoryFile: "alfie_memory_x.csv", startedAt: "2026-09-28T00:00:00Z",
            identity: identity, columns: DiagnosticsLog.columns,
            unobservable: DiagnosticsLog.alwaysUnobservable + [identity.output.presentation])
        let decoded = try JSONDecoder().decode(DiagnosticsManifest.self, from: JSONEncoder().encode(manifest))
        #expect(decoded == manifest)
        #expect(decoded.schemaVersion == DiagnosticsManifest.currentSchemaVersion)
        #expect(decoded.identity.source.belowShowRate)
        #expect(decoded.identity.source.configuredCaptureFPS == 30)
        #expect(decoded.unobservable.contains { $0.contains("ATEM") })
    }

    @Test func buildIdentityNeverShowsAnUnexpandedFingerprint() {
        let build = DiagnosticsLog.currentBuildIdentity()
        #expect(!build.sourceFingerprint.hasPrefix("$("))
        #expect(!build.machineModel.isEmpty)
    }
}

// MARK: - Synthetic pipeline through ProgramOutputManager

@MainActor
private final class FakeSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route
    var accepts = true
    var isAvailable: Bool { true }
    var summary: String { "fake" }
    var detail: String { "fake" }
    var lastErrorDescription: String? { nil }
    var onStateChange: (() -> Void)?

    init(route: ProgramOutputManager.Route) { self.route = route }

    func connect() {}
    func disconnect() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { accepts }
}

@MainActor
struct ProgramOutputMetricsTests {
    private func makeBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, attributes, &buffer)
        return try #require(buffer)
    }

    @Test func syntheticCountsRepeatsAndFinalFlushLandInTheirStages() throws {
        let sink = FakeSink(route: .display)
        let output = ProgramOutputManager(sinks: [sink])
        output.start()
        output.updateCaptureStatus(isRunning: true)
        let buffer = try makeBuffer()

        output.recordGateDropTotal(100) // baseline for this session
        for index in 0..<10 {
            let t = Double(index) / 50
            output.recordInputFrame(timestamp: t)
            output.sendFrame(buffer, timestamp: t, isRepeat: index >= 8)
        }
        output.recordGateDropTotal(103)
        output.recordDroppedFrame(timestamp: 0.3, reason: "upstream", stage: .captureUpstream)
        output.recordDroppedFrame(timestamp: 0.3, reason: "render", stage: .renderFailed)
        sink.accepts = false
        output.sendFrame(buffer, timestamp: 0.4)

        // Stop flushes the open window early and marks it partial.
        output.stop()
        let window = try #require(output.lastPipelineWindow)
        #expect(window.kind == .partial)
        #expect(window.window.admitted == 10)
        #expect(window.window.gateSkipped == 3)
        #expect(window.window.delivered == 13)
        #expect(window.window.routed == 11)
        #expect(window.window.handoffAccepted == 10)
        #expect(window.window.repeated == 2)
        #expect(window.window.handoffRefused == 1)
        #expect(window.window.captureDropped == 1)
        #expect(window.window.renderFailed == 1)
        #expect(window.window.noRoute == 0)
        // The HUD aggregate is still the sum of every drop stage.
        #expect(output.droppedFrames == 3)
        #expect(output.framesSent == 10)
    }

    @Test func framesWithNoActiveRouteAreCountedNotSent() throws {
        let output = ProgramOutputManager(sinks: [])
        output.start()
        output.updateCaptureStatus(isRunning: true)
        output.sendFrame(try makeBuffer(), timestamp: 0)
        output.stop()
        let window = try #require(output.lastPipelineWindow)
        #expect(window.window.routed == 1)
        #expect(window.window.noRoute == 1)
        #expect(window.window.handoffAccepted == 0)
    }

    /// Accelerated source-clock stress retains the existing 5,000-frame
    /// workload and 250 µs gross-regression bound. It is not a live cadence or
    /// production performance budget; opt in to keep load out of the unit suite.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ALFIE_METRICS_STRESS"] == "1",
                   "Opt-in accelerated instrumentation stress; run separately from cadence measurements"))
    func acceleratedInstrumentationStressKeepsOriginalBound() throws {
        let sink = FakeSink(route: .display)
        let output = ProgramOutputManager(sinks: [sink])
        output.start()
        output.updateCaptureStatus(isRunning: true)
        let buffer = try makeBuffer()
        let frames = 5_000
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for index in 0..<frames {
                let t = Double(index) / 50
                output.recordMainActorHop(0.001)
                output.recordInputFrame(timestamp: t)
                output.recordLatency(stage: .compose, duration: 0.001, timestamp: t)
                output.recordLatency(stage: .cropRender, duration: 0.004, timestamp: t)
                output.sendFrame(buffer, timestamp: t)
                output.recordLatency(stage: .mainActor, duration: 0.003, timestamp: t)
                output.recordLatency(stage: .total, duration: 0.008, timestamp: t)
                output.recordGateDropTotal(UInt64(index / 10))
            }
        }
        output.stop()
        let microsecondsPerFrame = Self.seconds(elapsed) / Double(frames) * 1_000_000
        let emitMS = output.lastPipelineWindow?.emitMS ?? 0
        let report = String(
            format: "[METRICS] accelerated source-clock instrumentation: %.2f µs/frame over %d frames; row aggregate: %.3f ms (Debug build)\n",
            microsecondsPerFrame, frames, emitMS)
        // Test-host stdout is not captured; leave the numbers where a human can
        // read them (the test host's temporary directory).
        try? report.write(
            to: FileManager.default.temporaryDirectory.appendingPathComponent("alfie-metrics-accelerated-stress.txt"),
            atomically: true, encoding: .utf8)
        #expect(microsecondsPerFrame < 250)
    }

    private struct CadenceSample: Codable {
        let repetition: Int
        let frames: Int
        let warmUpSeconds: Double
        let warmUpFrames: Int
        let missedScheduleIntervals: Int
        let referenceWindowSamplesPerStage: Int
        let elapsedSeconds: Double
        let cpuSeconds: Double
        let instrumentationMicrosecondsPerFrame: Double
        let invocationCadenceFPS: Double
        let retainedLatencySamples: Int
        let allocatedLatencySlots: Int
        let thermal: String
        let lowPower: Bool
        let build: String
    }

    /// Periodic ContinuousClock deadlines emulate nominal 50 Hz arrivals.
    /// Missed deadlines are skipped, never replayed as a catch-up frame batch;
    /// latency stamps remain CACurrentMediaTime. Warm up at least five seconds,
    /// then measure three 250-frame repetitions and record actual invocation
    /// rate. Work timing excludes sleeps/reference checks; process CPU includes
    /// fixture scheduling, reference bookkeeping and normal refresh/watchdog work.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ALFIE_METRICS_CADENCE"] == "1",
                   "Opt-in periodic 50 Hz benchmark with five-second warm-up and three measured windows"))
    func cadenceRealisticInstrumentationBenchmark() async throws {
        let output = ProgramOutputManager(sinks: [FakeSink(route: .display)])
        output.start()
        output.updateCaptureStatus(isRunning: true)
        var stopped = false
        defer { if !stopped { output.stop() } }
        let buffer = try makeBuffer()
        let epoch = CACurrentMediaTime()
        let clock = ContinuousClock()
        let period: Duration = .milliseconds(20)
        let cadenceStart = clock.now
        var nextDeadline = cadenceStart
        var missedIntervals = 0
        var frameIndex = 0
        var referenceTimestamps: [TimeInterval] = []
        func recordFrame() -> TimeInterval {
            let now = CACurrentMediaTime()
            let sourceTime = now - epoch
            output.recordMainActorHop(0.001)
            output.recordInputFrame(timestamp: sourceTime)
            output.recordLatency(stage: .compose, duration: 0.001, timestamp: now)
            output.recordLatency(stage: .cropRender, duration: 0.004, timestamp: now)
            output.sendFrame(buffer, timestamp: sourceTime)
            output.recordLatency(stage: .mainActor, duration: 0.003, timestamp: now)
            output.recordLatency(stage: .total, duration: 0.008, timestamp: now)
            output.recordGateDropTotal(UInt64(frameIndex / 10))
            frameIndex += 1
            return now
        }
        func invokeScheduledFrame() async throws -> Double {
            try await clock.sleep(until: nextDeadline, tolerance: .milliseconds(1))
            let wakeTime = clock.now
            // If wake-up spans multiple periods, invoke only the latest due
            // interval. Earlier intervals are counted as missed, not replayed.
            while nextDeadline + period <= wakeTime {
                nextDeadline += period
                missedIntervals += 1
            }
            let workStart = CACurrentMediaTime()
            let timestamp = recordFrame()
            let workSeconds = CACurrentMediaTime() - workStart
            // A simple exact reference uses observed stamps; timer jitter does
            // not imply the uniform/minimum-spacing 251-sample bound.
            referenceTimestamps.append(timestamp)
            referenceTimestamps.removeAll { $0 < timestamp - 5 }
            nextDeadline += period
            let afterWork = clock.now
            while nextDeadline <= afterWork {
                nextDeadline += period
                missedIntervals += 1
            }
            return workSeconds
        }
        while clock.now - cadenceStart < .seconds(5) {
            _ = try await invokeScheduledFrame()
        }
        let warmUpSeconds = CACurrentMediaTime() - epoch
        let warmUpFrames = frameIndex
        #expect(warmUpSeconds >= 5)
        var measurements: [CadenceSample] = []
        for repetition in 0..<3 {
            let cpuStart = DiagnosticsLog.processCPUSeconds()
            let start = CACurrentMediaTime()
            let missedStart = missedIntervals
            var workSeconds = 0.0
            for _ in 0..<250 { workSeconds += try await invokeScheduledFrame() }
            let elapsed = CACurrentMediaTime() - start
            let stats = output.latencyStorageStatistics
            let retained = stats.values.reduce(0) { $0 + $1.count }
            for stage in [ProgramOutputManager.LatencyStage.compose, .cropRender, .mainActor, .total] {
                #expect(stats[stage]?.count == referenceTimestamps.count)
            }
            #expect(retained == 4 * referenceTimestamps.count)
            for stageStats in stats.values {
                #expect(stageStats.capacity <= max(64, stageStats.count * 4))
            }
            #expect(workSeconds.isFinite && workSeconds > 0)
            measurements.append(CadenceSample(
                repetition: repetition, frames: 250, warmUpSeconds: warmUpSeconds,
                warmUpFrames: warmUpFrames,
                missedScheduleIntervals: missedIntervals - missedStart,
                referenceWindowSamplesPerStage: referenceTimestamps.count,
                elapsedSeconds: elapsed,
                cpuSeconds: DiagnosticsLog.processCPUSeconds() - cpuStart,
                instrumentationMicrosecondsPerFrame: workSeconds / 250 * 1e6,
                invocationCadenceFPS: 250 / elapsed,
                retainedLatencySamples: retained,
                allocatedLatencySlots: stats.values.reduce(0) { $0 + $1.capacity },
                thermal: DiagnosticsLog.thermalStateName(ProcessInfo.processInfo.thermalState),
                lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                build: DiagnosticsLog.currentBuildIdentity().sourceFingerprint))
        }
        output.stop()
        stopped = true
        #expect(output.framesSent == warmUpFrames + 750)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(measurements)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alfie-metrics-cadence-periodic.json")
        try data.write(to: url, options: .atomic)
        print("METRICS_CADENCE_PERIODIC " + url.path)
        print(String(decoding: data, as: UTF8.self))
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
