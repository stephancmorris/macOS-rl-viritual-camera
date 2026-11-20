//
//  ValidationClipPlayer.swift
//  CinematicCoreMacOS
//
//  G-01 stage 4. Owns validation-clip playback (Gate 5): the playback task
//  that used to be a private stored property of CameraManager, the loop,
//  and the AVAssetReader that paces a file's frames at their own timing.
//  CameraManager keeps the session state it publishes (running, source,
//  status, error) and reacts to how playback ends.
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore

@MainActor
final class ValidationClipPlayer {
    /// How one playback ended.
    enum Ending {
        case finished
        case cancelled
        case failed(Error)
    }

    private var task: Task<Void, Never>?

    /// Play `url` from a detached task, frame by frame at the file's own
    /// timing, repeating while `shouldLoop` says so. A playback already
    /// running is cancelled first. `ended` runs on the main actor exactly
    /// once unless the playback is stopped and replaced first; the camera
    /// checks its own generation there.
    func start(_ url: URL,
               onFrame: @escaping @Sendable (SendablePixelBufferBox, Double) async -> Void,
               shouldLoop: @escaping @MainActor @Sendable () -> Bool,
               onLoop: @escaping @MainActor @Sendable () -> Void,
               ended: @escaping @MainActor @Sendable (Ending) -> Void) {
        task?.cancel()
        task = Task.detached(priority: .userInitiated) {
            do {
                repeat {
                    try await Self.readFrames(from: url, onFrame: onFrame)
                    let loop = await shouldLoop()
                    if !loop || Task.isCancelled {
                        break
                    }
                    await onLoop()
                } while !Task.isCancelled

                await ended(Task.isCancelled ? .cancelled : .finished)
            } catch is CancellationError {
                await ended(.cancelled)
            } catch {
                await ended(.failed(error))
            }
        }
    }

    /// Cancel playback and forget the task.
    func stop() {
        task?.cancel()
        task = nil
    }

    /// Playback has ended; forget the task without cancelling it.
    func playbackEnded() {
        task = nil
    }

    nonisolated static func playbackDelay(sourceTimestamp: Double, firstTimestamp: Double,
        playbackStart: Double, now: Double) -> Double {
        max(0, playbackStart + max(0, sourceTimestamp - firstTimestamp) - now)
    }

    private nonisolated static func readFrames(
        from url: URL,
        onFrame: @escaping @Sendable (SendablePixelBufferBox, Double) async -> Void
    ) async throws {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw CameraError.invalidValidationClip
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw CameraError.validationClipPlaybackFailed("AVAssetReader could not attach the video output")
        }
        reader.add(output)

        guard reader.startReading() else {
            throw CameraError.validationClipPlaybackFailed(
                reader.error?.localizedDescription ?? "AVAssetReader failed to start"
            )
        }

        var firstTimestamp: Double?
        let playbackStart = CACurrentMediaTime()
        while !Task.isCancelled, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            if firstTimestamp == nil { firstTimestamp = timestampSeconds }
            let delay = Self.playbackDelay(sourceTimestamp: timestampSeconds,
                firstTimestamp: firstTimestamp!, playbackStart: playbackStart, now: CACurrentMediaTime())
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }

            let pixelBufferBox = SendablePixelBufferBox(pixelBuffer)
            await onFrame(pixelBufferBox, timestampSeconds)
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        if reader.status == .failed {
            throw CameraError.validationClipPlaybackFailed(
                reader.error?.localizedDescription ?? "AVAssetReader failed while reading"
            )
        }
    }
}
