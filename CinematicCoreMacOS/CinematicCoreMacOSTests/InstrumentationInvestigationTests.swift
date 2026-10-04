// Synthetic investigation harness. No camera, real sink, or production changes.
import CoreVideo
import Foundation
import QuartzCore
import Testing
@testable import Alfie

@MainActor private final class InvestigationSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .display
    var isAvailable: Bool { true }
    var summary: String { "synthetic" }
    var detail: String { "synthetic" }
    var lastErrorDescription: String? { nil }
    var onStateChange: (() -> Void)?
    func connect() {}
    func disconnect() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { true }
}

@MainActor struct InstrumentationInvestigationTests {
    private struct Sample: Codable {
        let mode: String
        let frames: Int
        let repetition: Int
        let elapsedSeconds: Double
        let cpuSeconds: Double
        let microsecondsPerFrame: Double
        let thermal: String
        let lowPower: Bool
        let retainedLatencySamples: Int
    }
    // Read scalar storage statistics after timing; no reflection or collection
    // copying enters the measured frame loop.
    private func retainedSamples(_ output: ProgramOutputManager) -> Int {
        output.latencyStorageStatistics.values.reduce(0) { $0 + $1.count }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ALFIE_INSTRUMENTATION_STUDY"] == "1",
                   "Opt-in synthetic benchmark investigation; avoid adding load to the ordinary unit suite"))
    func compareAcceleratedWallClockAndSourceClockWindows() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixel = try #require(buffer)
        var samples: [Sample] = []
        for repetition in 0..<3 {
            // Alternate ordering to reduce systematic warm-up/order bias.
            let modes = repetition.isMultiple(of: 2) ? ["wall", "source"] : ["source", "wall"]
            for frames in [500, 1000, 2000, 5000] {
                for mode in modes {
                    let output = ProgramOutputManager(sinks: [InvestigationSink()])
                    output.start()
                    output.updateCaptureStatus(isRunning: true)
                    let cpuStart = DiagnosticsLog.processCPUSeconds()
                    let clock = ContinuousClock()
                    let elapsed = clock.measure {
                        for index in 0..<frames {
                            let t = Double(index) / 50
                            let sampleTime = mode == "wall" ? CACurrentMediaTime() : t
                            output.recordMainActorHop(0.001)
                            output.recordInputFrame(timestamp: t)
                            output.recordLatency(stage: .compose, duration: 0.001, timestamp: sampleTime)
                            output.recordLatency(stage: .cropRender, duration: 0.004, timestamp: sampleTime)
                            output.sendFrame(pixel, timestamp: t)
                            output.recordLatency(stage: .mainActor, duration: 0.003, timestamp: sampleTime)
                            output.recordLatency(stage: .total, duration: 0.008, timestamp: sampleTime)
                            output.recordGateDropTotal(UInt64(index / 10))
                        }
                    }
                    let cpu = DiagnosticsLog.processCPUSeconds() - cpuStart
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    let retained = retainedSamples(output)
                    output.stop()
                    #expect(output.framesSent == frames)
                    #expect(seconds.isFinite && seconds > 0)
                    #expect(retained >= 0)
                    samples.append(.init(mode: mode, frames: frames, repetition: repetition,
                        elapsedSeconds: seconds, cpuSeconds: cpu,
                        microsecondsPerFrame: seconds / Double(frames) * 1e6,
                        thermal: DiagnosticsLog.thermalStateName(ProcessInfo.processInfo.thermalState),
                        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                        retainedLatencySamples: retained))
                }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(samples)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alfie-instrumentation-investigation.json")
        try data.write(to: url, options: .atomic)
        print("INSTRUMENTATION_INVESTIGATION " + url.path)
        print(String(decoding: data, as: UTF8.self))
    }
}
