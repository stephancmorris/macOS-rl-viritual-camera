//
//  WorkloadMonitor.swift
//  CinematicCoreMacOS
//
//  DEGRADE-MODEL: turns each closed diagnostics window into a
//  `DegradePolicy.Window`. Pure apart from `ProcessCPUClock`. The show runs
//  the policy only behind `DeveloperFlags.runtimeWorkloadPolicy` (off) and
//  applies only its optional-UI hint. Thresholds stay the policy's
//  provisional values until MULTI-QA measures budgets: unapproved, needs
//  rig calibration.
//

import Darwin
import Foundation

nonisolated enum WorkloadMonitor {
    /// Show-level facts the diagnostics window doesn't carry.
    struct Context: Equatable, Sendable {
        var twoInputsActive: Bool
        /// Process CPU time over wall time, divided by active cores (0…1).
        var cpuFraction: Double
        var thermalSerious: Bool
        var showFPS: Double
        /// Age of the Preview channel's newest rendered frame; nil with no Preview.
        var previewRenderAgeSeconds: Double?
    }

    /// Program frames that missed their slot: held repeats, refusals, no
    /// route and render failures, as a fraction of the frames the show
    /// standard expected in the window.
    static func programDeadlineMissFraction(_ row: DiagnosticsWindow, showFPS: Double) -> Double {
        let expected = row.windowSeconds * showFPS
        guard expected.isFinite, expected > 0 else { return 0 }
        let w = row.window
        let missed = Double(w.repeated + w.handoffRefused + w.noRoute + w.renderFailed)
        return min(1, max(0, missed / expected))
    }

    static func window(from row: DiagnosticsWindow, context c: Context) -> DegradePolicy.Window {
        var window = DegradePolicy.Window()
        window.twoInputsActive = c.twoInputsActive
        window.cpuFraction = c.cpuFraction
        window.thermalSerious = c.thermalSerious
        window.programDeadlineMissFraction = programDeadlineMissFraction(row, showFPS: c.showFPS)
        window.previewRenderAgeSeconds = c.previewRenderAgeSeconds ?? 0
        // No calibrated definition of a failed ingest or Program budget yet
        // (MULTI-QA); never latch Unsupported from an unmeasured guess.
        window.sourceIngestSustainable = true
        window.programBudgetSustainable = true
        window.candidateAgeSeconds = c.previewRenderAgeSeconds
        return window
    }
}

/// Process CPU time against wall time between two samples.
nonisolated struct ProcessCPUClock {
    private var lastCPU: Double
    private var lastWall: Double

    init() {
        lastCPU = Self.processCPUSeconds()
        lastWall = ProcessInfo.processInfo.systemUptime
    }

    static func processCPUSeconds() -> Double {
        var spec = timespec()
        guard clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &spec) == 0 else { return 0 }
        return Double(spec.tv_sec) + Double(spec.tv_nsec) / 1e9
    }

    /// Fraction of the machine's cores this process used since the last call.
    mutating func sample() -> Double {
        let cpu = Self.processCPUSeconds(), wall = ProcessInfo.processInfo.systemUptime
        defer { lastCPU = cpu; lastWall = wall }
        let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
        let elapsed = wall - lastWall
        guard elapsed > 0 else { return 0 }
        return min(1, max(0, (cpu - lastCPU) / elapsed / cores))
    }
}
