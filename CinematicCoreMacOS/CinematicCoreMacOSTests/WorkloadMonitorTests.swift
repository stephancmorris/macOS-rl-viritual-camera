//
//  WorkloadMonitorTests.swift
//  CinematicCoreMacOSTests
//
//  DEGRADE-MODEL: the window adapter, the flag-off no-op, hysteresis
//  through the show, and that no level touches routing, roles or channels.
//

import Foundation
import Testing
@testable import Alfie

struct WorkloadMonitorMappingTests {
    private func row(seconds: Double = 5, repeated: Int = 0, refused: Int = 0,
                     noRoute: Int = 0, failed: Int = 0) -> DiagnosticsWindow {
        var row = DiagnosticsWindow()
        row.windowSeconds = seconds
        row.window.repeated = repeated
        row.window.handoffRefused = refused
        row.window.noRoute = noRoute
        row.window.renderFailed = failed
        return row
    }

    @Test func missFractionCountsEveryKindOfMissedProgramSlot() {
        // 5 s at 50 fps expects 250 frames; 5 + 5 + 10 + 5 = 25 missed.
        #expect(abs(WorkloadMonitor.programDeadlineMissFraction(
            row(repeated: 5, refused: 5, noRoute: 10, failed: 5), showFPS: 50) - 0.1) < 1e-12)
        #expect(WorkloadMonitor.programDeadlineMissFraction(row(repeated: 9999), showFPS: 50) == 1)
        #expect(WorkloadMonitor.programDeadlineMissFraction(row(seconds: 0, repeated: 5), showFPS: 50) == 0)
        #expect(WorkloadMonitor.programDeadlineMissFraction(row(repeated: 5), showFPS: .nan) == 0)
    }

    @Test func contextMapsAndNeverLatchesUnsupportedFromAGuess() {
        let context = WorkloadMonitor.Context(twoInputsActive: true, cpuFraction: 0.5, thermalSerious: true,
                                              showFPS: 50, previewRenderAgeSeconds: 0.05)
        let window = WorkloadMonitor.window(from: row(), context: context)
        #expect(window.twoInputsActive && window.thermalSerious && window.cpuFraction == 0.5)
        #expect(window.previewRenderAgeSeconds == 0.05 && window.candidateAgeSeconds == 0.05)
        #expect(window.sourceIngestSustainable && window.programBudgetSustainable)
        let noPreview = WorkloadMonitor.window(from: row(), context: .init(
            twoInputsActive: false, cpuFraction: 0, thermalSerious: false, showFPS: 50, previewRenderAgeSeconds: nil))
        #expect(noPreview.candidateAgeSeconds == nil)   // unknown, never "fresh"
    }

    @Test func cpuClockStaysInRange() {
        var clock = ProcessCPUClock()
        var x = 0.0
        for i in 0..<200_000 { x += Double(i).squareRoot() }
        #expect(x > 0)
        let fraction = clock.sample()
        #expect(fraction >= 0 && fraction <= 1)
    }

    /// PR-REVIEW-1104 C2: a span that starts before the window would
    /// average in idle time. `restart()` begins a new span.
    @Test func cpuClockRestartDropsTheIdleSpanBeforeIt() {
        let source = FakeCPUSource(cores: 4)
        var clock = ProcessCPUClock(read: source.read)
        source.advance(wall: 100, busyCores: 0)        // idle before the show
        clock.restart()
        source.advance(wall: 2, busyCores: 3.6)        // 90% of 4 cores
        #expect(abs(clock.sample() - 0.9) < 1e-9)
        source.advance(wall: 2, busyCores: 1)
        #expect(abs(clock.sample() - 0.25) < 1e-9)     // consecutive spans line up
    }
}

/// Deterministic process CPU and wall clock for `ProcessCPUClock`.
nonisolated final class FakeCPUSource: @unchecked Sendable {
    private var reading: ProcessCPUClock.Reading
    init(cores: Int) { reading = .init(cpuSeconds: 0, wallSeconds: 0, cores: cores) }
    var read: @Sendable () -> ProcessCPUClock.Reading { { self.reading } }
    func advance(wall: Double, busyCores: Double) {
        reading.wallSeconds += wall
        reading.cpuSeconds += wall * busyCores
    }
}

@MainActor
struct WorkloadPolicyShowTests {
    private func show(enabled: Bool) -> ShowCoordinator {
        let defaults = UserDefaults(suiteName: "alfie-workload-\(UUID().uuidString)")!
        return ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
                               admissionRecords: AdmissionRecordStore(defaults: defaults),
                               operatorModes: OperatorModeStore(defaults: defaults, multiviewEnabled: true),
                               workloadPolicyEnabled: enabled)
    }

    /// PR-REVIEW-1104 C2: the first window after go-live measures only
    /// the show, not the idle time since the coordinator was created.
    @Test func goingLiveRestartsTheCPUSpan() {
        let defaults = UserDefaults(suiteName: "alfie-workload-cpu-\(UUID().uuidString)")!
        let source = FakeCPUSource(cores: 4)
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
                                   admissionRecords: AdmissionRecordStore(defaults: defaults),
                                   operatorModes: OperatorModeStore(defaults: defaults, multiviewEnabled: true),
                                   workloadPolicyEnabled: true, workloadCPUReading: source.read)
        source.advance(wall: 600, busyCores: 0.04)     // ten idle minutes
        show.channelA.setRunningForTesting(true)
        defer { show.channelA.setRunningForTesting(false) }
        source.advance(wall: 2, busyCores: 3.6)
        #expect(abs(show.sampleWorkloadCPUForTesting() - 0.9) < 1e-9)
    }

    private var overloaded: DegradePolicy.Window {
        var w = DegradePolicy.Window(); w.cpuFraction = 0.95; w.candidateAgeSeconds = 0.05; return w
    }
    private var healthy: DegradePolicy.Window {
        var w = DegradePolicy.Window(); w.cpuFraction = 0.3; w.candidateAgeSeconds = 0.05; return w
    }

    @Test func flagOffIsANoOp() {
        let show = show(enabled: false)
        #expect(show.workloadPolicy == nil)
        for _ in 0..<10 { show.applyWorkloadWindow(overloaded) }
        #expect(show.workloadLevel == .normal && !show.reducesOptionalUI)
    }

    @Test func sustainedPressureStepsDownThenRecoversWithHysteresis() {
        let show = show(enabled: true)
        show.addChannel(.b)
        let program = show.programChannel, generation = show.router.routeGeneration
        let channels = ChannelID.allCases.filter { show.channel($0) != nil }

        show.applyWorkloadWindow(overloaded); show.applyWorkloadWindow(overloaded)
        #expect(show.workloadLevel == .normal)            // two windows are not sustained
        show.applyWorkloadWindow(overloaded)
        #expect(show.workloadLevel == .optionalUI && show.reducesOptionalUI)

        // One healthy window doesn't flip back; six do.
        show.applyWorkloadWindow(healthy)
        #expect(show.workloadLevel == .optionalUI)
        for _ in 0..<5 { show.applyWorkloadWindow(healthy) }
        #expect(show.workloadLevel == .normal && !show.reducesOptionalUI)

        // No level ever touched roles, routing or channels.
        #expect(show.programChannel == program && show.router.routeGeneration == generation)
        #expect(ChannelID.allCases.filter { show.channel($0) != nil } == channels)
        #expect(!show.editLive)
    }

    @Test func alternatingWindowsDoNotOscillate() {
        let show = show(enabled: true)
        for _ in 0..<20 {
            show.applyWorkloadWindow(overloaded)
            show.applyWorkloadWindow(healthy)
        }
        #expect(show.workloadLevel == .normal)
        #expect(show.workloadPolicy?.transitions.isEmpty == true)
    }

    @Test func aSingleInputAlwaysRunsNormal() {
        let show = show(enabled: true)
        for _ in 0..<3 { show.applyWorkloadWindow(overloaded) }
        #expect(show.workloadLevel == .optionalUI)
        var single = overloaded; single.twoInputsActive = false
        show.applyWorkloadWindow(single)
        #expect(show.workloadLevel == .normal)
    }
}
