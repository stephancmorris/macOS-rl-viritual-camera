//
//  CameraChannel.swift
//  CinematicCoreMacOS
//
//  Per-channel output seam (CHANNEL card). `CameraManager` is the per-channel
//  controller — the multi-camera spec allows "an extracted CameraManager" —
//  and each instance talks to the show through a `ChannelOutputPort` instead
//  of owning an output.
//
//  - The routed channel's port is the show's single ProgramOutputManager, so
//    single-camera behaviour is unchanged call for call.
//  - Every other channel gets an `UnroutedChannelOutput`: it keeps no sink,
//    never starts or stops the show output, and records nothing in the show's
//    diagnostics. Its rendered frames stay on the channel
//    (`CameraManager.latestRenderedFrame`) for Preview and a later Take.
//
//  ROUTER replaces the "routed channel = the output" shortcut with a
//  ProgramRouter that owns route generations and the output clock.
//

import CoreVideo
import Foundation
import QuartzCore

/// Everything a channel's frame path may tell the show. Mirrors the
/// ProgramOutputManager calls CameraManager made before channels existed.
protocol ChannelOutputPort: AnyObject {
    var diagnosticsFileName: String? { get }
    /// Route generation to stamp on a frame when its processing starts, so a
    /// frame rendered before a role change is refused when it arrives.
    var routeGeneration: UInt64 { get }
    func submitFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double, isRepeat: Bool, routeGeneration: UInt64)

    func start()
    func stop()
    func updateCaptureStatus(isRunning: Bool)
    func sendFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double, isRepeat: Bool)

    func beginDiagnosticsSessionIfNeeded(note: String)
    func noteDetectionStartIfNeeded()
    func noteDiagnostics(_ text: String)
    func recordSourceIdentity(_ source: DiagnosticsSessionIdentity.Source)
    func recordDeliveredDimensions(width: Int, height: Int)
    func recordInputFrame(timestamp: Double)
    func recordMainActorHop(_ seconds: TimeInterval)
    func recordDetectionTiming(queueWait: TimeInterval, visionWall: TimeInterval)
    func recordObservationAge(_ age: TimeInterval)
    func recordLatency(stage: ProgramOutputManager.LatencyStage, duration: TimeInterval, timestamp: TimeInterval)
    func recordDroppedFrame(timestamp: Double, reason: String, stage: ProgramOutputManager.DropStage)
    func recordGateDropTotal(_ total: UInt64)
    func recordFramePathCounts(detectedPersons: Int)
    func recordPictureQuality(sourceHeight: Int, cropHeightFraction: Double, outputHeight: Int)
}

extension ChannelOutputPort {
    /// Ports without routing (the direct output, unrouted channels) have a
    /// single, fixed generation.
    var routeGeneration: UInt64 { 0 }

    func submitFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double, isRepeat: Bool, routeGeneration: UInt64) {
        sendFrame(pixelBuffer, timestamp: timestamp, isRepeat: isRepeat)
    }

    func recordLatency(stage: ProgramOutputManager.LatencyStage, duration: TimeInterval) {
        recordLatency(stage: stage, duration: duration, timestamp: CACurrentMediaTime())
    }

    func sendFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double) {
        sendFrame(pixelBuffer, timestamp: timestamp, isRepeat: false)
    }
}

/// The routed channel's port: the show's single output, unchanged.
extension ProgramOutputManager: ChannelOutputPort {}

/// Port for a channel that is not routed downstream. It owns nothing and
/// cannot affect the show output; it only counts what it was offered so tests
/// and diagnostics can see the channel is alive.
final class UnroutedChannelOutput: ChannelOutputPort {
    let channelID: ChannelID
    private(set) var framesOffered = 0

    init(channelID: ChannelID) {
        self.channelID = channelID
    }

    /// Non-nil so the channel never tries to open the show's diagnostics
    /// session (which would otherwise be attempted on every frame).
    var diagnosticsFileName: String? { "not recorded: \(channelID.cameraLabel) is not routed" }

    func start() {}
    func stop() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double, isRepeat: Bool) { framesOffered += 1 }

    func beginDiagnosticsSessionIfNeeded(note: String) {}
    func noteDetectionStartIfNeeded() {}
    func noteDiagnostics(_ text: String) {}
    func recordSourceIdentity(_ source: DiagnosticsSessionIdentity.Source) {}
    func recordDeliveredDimensions(width: Int, height: Int) {}
    func recordInputFrame(timestamp: Double) {}
    func recordMainActorHop(_ seconds: TimeInterval) {}
    func recordDetectionTiming(queueWait: TimeInterval, visionWall: TimeInterval) {}
    func recordObservationAge(_ age: TimeInterval) {}
    func recordLatency(stage: ProgramOutputManager.LatencyStage, duration: TimeInterval, timestamp: TimeInterval) {}
    func recordDroppedFrame(timestamp: Double, reason: String, stage: ProgramOutputManager.DropStage) {}
    func recordGateDropTotal(_ total: UInt64) {}
    func recordFramePathCounts(detectedPersons: Int) {}
    func recordPictureQuality(sourceHeight: Int, cropHeightFraction: Double, outputHeight: Int) {}
}
