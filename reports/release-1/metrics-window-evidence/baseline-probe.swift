// Faithful standalone reproduction of origin/main ProgramOutputManager.recordLatency.
// Isolates sample-array insertion/expiry from UI, capture, sendFrame and coalesced publication.
import Foundation
import QuartzCore
import Darwin

enum Stage: CaseIterable { case detection, compose, cropRender, xpcSend, total, mainActor }
struct TimedDuration { let timestamp: TimeInterval; let duration: TimeInterval }
final class Baseline {
    var latencySamples: [Stage: [TimedDuration]] = [:]
    var rawMainSum = 0.0; var rawMainMax = 0.0; var rawMainCount = 0
    var rawFrameSum = 0.0; var rawFrameMax = 0.0; var rawFrameCount = 0
    func recordLatency(stage: Stage, duration: TimeInterval, timestamp: TimeInterval) {
        if stage == .mainActor {
            rawMainSum += duration
            rawMainMax = max(rawMainMax, duration)
            rawMainCount += 1
        }
        if stage == .total {
            rawFrameSum += duration
            rawFrameMax = max(rawFrameMax, duration)
            rawFrameCount += 1
        }
        var samples = latencySamples[stage, default: []]
        samples.append(TimedDuration(timestamp: timestamp, duration: duration))
        let windowStart = timestamp - 5
        samples.removeAll { $0.timestamp < windowStart }
        latencySamples[stage] = samples
    }
}
func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
}
struct Measurement: Codable {
    let mode: String; let frames: Int; let repetition: Int
    let wallSeconds: Double; let cpuSeconds: Double; let microsecondsPerFrame: Double
    let retainedSamples: Int; let thermal: String; let lowPower: Bool
    let allocationRequests: UInt64?; let allocatedBytes: UInt64?
}
typealias AllocationBegin = @convention(c) () -> Void
typealias AllocationEnd = @convention(c) (Int32) -> UInt64
let allocationBegin = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "probe_allocation_begin")
    .map { unsafeBitCast($0, to: AllocationBegin.self) }
let allocationEnd = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "probe_allocation_end")
    .map { unsafeBitCast($0, to: AllocationEnd.self) }
let allocationDump = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "probe_allocation_dump")
    .map { unsafeBitCast($0, to: AllocationBegin.self) }
let mode = CommandLine.arguments.dropFirst().first ?? "wall"
let frames = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 5000
let repetitions = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 3
var measurements: [Measurement] = []
for repetition in 0..<repetitions {
    let baseline = Baseline()
    allocationBegin?()
    let cpuStart = cpuSeconds(); let wallStart = CACurrentMediaTime()
    for index in 0..<frames {
        let timestamp = mode == "wall" ? CACurrentMediaTime() : Double(index) / 50
        baseline.recordLatency(stage: .compose, duration: 0.001, timestamp: timestamp)
        baseline.recordLatency(stage: .cropRender, duration: 0.004, timestamp: timestamp)
        baseline.recordLatency(stage: .mainActor, duration: 0.003, timestamp: timestamp)
        baseline.recordLatency(stage: .total, duration: 0.008, timestamp: timestamp)
    }
    let wall = CACurrentMediaTime() - wallStart
    let requests = allocationEnd?(0); let bytes = allocationEnd?(1)
    allocationDump?()
    measurements.append(Measurement(mode: mode, frames: frames, repetition: repetition,
        wallSeconds: wall, cpuSeconds: cpuSeconds() - cpuStart,
        microsecondsPerFrame: wall / Double(frames) * 1e6,
        retainedSamples: baseline.latencySamples.values.reduce(0) { $0 + $1.count },
        thermal: String(describing: ProcessInfo.processInfo.thermalState),
        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
        allocationRequests: requests, allocatedBytes: bytes))
}
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(decoding: try encoder.encode(measurements), as: UTF8.self))
