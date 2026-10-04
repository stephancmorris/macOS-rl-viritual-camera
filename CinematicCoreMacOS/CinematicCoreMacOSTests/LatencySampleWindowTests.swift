import Foundation
import Testing
@testable import Alfie

@MainActor
struct LatencySampleWindowTests {
    private struct ReferenceSample {
        let timestamp: TimeInterval
        let duration: TimeInterval
    }

    @Test func cutoffIsInclusiveAndExpiryUsesTheLatestStageAppend() {
        let window = LatencySampleWindow()
        window.append(timestamp: 0, duration: 1)
        window.append(timestamp: 4.999, duration: 2)
        window.append(timestamp: 5, duration: 3)
        #expect(window.count == 3) // Exactly five seconds old is retained.
        #expect(window.averageDuration == 2)
        window.append(timestamp: 5.001, duration: 4)
        #expect(window.count == 3)
        #expect(window.averageDuration == 3)
    }

    @Test func wrapGrowthAndEvictionMatchOrderedArrayReference() {
        let window = LatencySampleWindow()
        var reference: [ReferenceSample] = []
        var timestamp = 0.0
        let gaps = [0.0, 0.003, 0.02, 0.001, 0.011, 0.04]
        for index in 0..<1_200 {
            timestamp += gaps[index % gaps.count]
            let duration = Double((index * 17) % 101) / 10_000
            window.append(timestamp: timestamp, duration: duration)
            reference.append(.init(timestamp: timestamp, duration: duration))
            reference.removeAll { $0.timestamp < timestamp - 5 }
            #expect(window.count == reference.count)
            #expect(window.averageDuration == reference.reduce(0) { $0 + $1.duration } / Double(reference.count))
            #expect(window.storageCapacity <= max(64, reference.count * 4))
        }
    }

    @Test func uniformShowCadenceHasAClockWindowBound() {
        for rate in [50.0, 60000.0 / 1001.0, 60.0] {
            let window = LatencySampleWindow()
            for index in 0..<2_000 {
                window.append(timestamp: Double(index) / rate, duration: 0.001)
                #expect(window.count <= Int(5 * rate) + 1)
                #expect(window.storageCapacity <= 512)
            }
            #expect(window.count >= Int(5 * rate))
        }
    }

    @Test func equalTimestampBurstIsLosslessAndExpiredCapacityIsReleased() {
        let window = LatencySampleWindow()
        var total = 0.0
        for index in 0..<10_000 {
            let duration = Double(index % 31) / 1_000
            total += duration
            window.append(timestamp: 10, duration: duration)
        }
        #expect(window.count == 10_000)
        #expect(window.averageDuration == total / 10_000)
        #expect(window.storageCapacity >= 10_000)
        window.append(timestamp: 15, duration: 1)
        #expect(window.count == 10_001) // Burst exactly on cutoff stays intact.
        window.append(timestamp: 15.001, duration: 2)
        #expect(window.count == 2)
        #expect(window.averageDuration == 1.5)
        #expect(window.storageCapacity == 64)
    }

    @Test func backwardsTimestampStartsANewEpochAndReleasesBurstStorage() {
        let window = LatencySampleWindow()
        for _ in 0..<1_000 { window.append(timestamp: 10, duration: 1) }
        window.append(timestamp: 9, duration: 7)
        #expect(window.count == 1)
        #expect(window.averageDuration == 7)
        #expect(window.storageCapacity == 64)
        window.append(timestamp: 14, duration: 3)
        #expect(window.count == 2)
        #expect(window.averageDuration == 5)
    }

    @Test func nonfiniteTimestampDoesNotMutateWindowOrClockEpoch() {
        let window = LatencySampleWindow()
        window.append(timestamp: 10, duration: 2)
        for timestamp in [Double.nan, .infinity, -.infinity] {
            #expect(!window.append(timestamp: timestamp, duration: 100))
            #expect(window.count == 1)
            #expect(window.averageDuration == 2)
        }
        window.append(timestamp: 11, duration: 4)
        #expect(window.count == 2)
        #expect(window.averageDuration == 3)
    }
}

@MainActor
struct ProgramOutputLatencyWindowTests {
    @Test func snapshotsKeepStageIsolationRawDurationsAndPublishCadence() throws {
        let output = ProgramOutputManager()
        output.start()
        output.recordLatency(stage: .compose, duration: 0.003, timestamp: 10)
        output.recordLatency(stage: .compose, duration: 0.005, timestamp: 11)
        output.recordLatency(stage: .detection, duration: 0.01, timestamp: 10)
        output.recordLatency(stage: .detection, duration: 0.02, timestamp: 9)
        output.recordLatency(stage: .mainActor, duration: 0.002, timestamp: 10)
        output.recordLatency(stage: .mainActor, duration: 0.006, timestamp: .nan)
        output.recordLatency(stage: .total, duration: 0.004, timestamp: 10)
        output.recordLatency(stage: .total, duration: 0.008, timestamp: .infinity)
        #expect(output.stageLatencies.isEmpty) // No per-sample publication.
        #expect(output.latencyStorageStatistics[.compose]?.count == 2)
        #expect(output.latencyStorageStatistics[.detection]?.count == 1)
        #expect(output.latencyStorageStatistics[.mainActor]?.count == 1)
        #expect(output.latencyStorageStatistics[.total]?.count == 1)
        output.stop()
        let means = Dictionary(uniqueKeysWithValues: output.stageLatencies.map { ($0.stage, $0.averageDuration) })
        #expect(means[.compose] == 0.004)
        #expect(means[.detection] == 0.02)
        #expect(means[.mainActor] == 0.002)
        #expect(means[.total] == 0.004)
        let row = try #require(output.lastPipelineWindow)
        // Raw duration counters keep every call, including a rejected stamp.
        #expect(row.mainMeanMS == 4)
        #expect(row.frameMeanMS == 6)
        #expect(row.mainMaxMS == 6)
        #expect(row.frameMaxMS == 8)
    }

    @Test func everyStageMatchesReferenceAndStartResetsWindows() {
        let output = ProgramOutputManager()
        output.start()
        var reference: [(Double, Double)] = []
        for index in 0..<400 {
            let timestamp = Double(index) / 50
            let duration = Double(index % 19) / 1_000
            reference.append((timestamp, duration))
            reference.removeAll { $0.0 < timestamp - 5 }
            for stage in ProgramOutputManager.LatencyStage.allCases {
                output.recordLatency(stage: stage, duration: duration, timestamp: timestamp)
            }
        }
        output.stop()
        #expect(output.stageLatencies.count == ProgramOutputManager.LatencyStage.allCases.count)
        let average = reference.reduce(0) { $0 + $1.1 } / Double(reference.count)
        for latency in output.stageLatencies { #expect(latency.averageDuration == average) }
        for stats in output.latencyStorageStatistics.values { #expect(stats.count == reference.count) }
        output.start()
        #expect(output.latencyStorageStatistics.isEmpty)
        #expect(output.stageLatencies.isEmpty)
        output.stop()
    }
}
