// Offline readiness harness. Set ALFIE_READINESS_CLIPS to a folder of consented
// .mov/.mp4/.m4v clips and ALFIE_READINESS_OUT to a CSV path, then run only
// ReadinessEvaluationTests. Optional <clip-basename>.json contains
// {"points":[{"timeS":0.0,"x":0.5,"y":0.5}, ...]} where x/y are normalized
// Vision bottom-left coordinates for the intended subject. No raw frames,
// face prints, or names are written to the CSV. Track-ID changes are a proxy,
// not a ground-truth wrong-person recovery count.

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import Testing
@testable import Alfie

@MainActor
struct ReadinessEvaluationTests {
    private struct TargetPoint: Decodable {
        let timeS: Double
        let x: Double
        let y: Double
    }
    private struct Annotation: Decodable { let points: [TargetPoint] }

    private struct ClipRow {
        let clip: String
        let annotated: Bool
        let decodedFrames: Int
        let selectedFrames: Int
        let subjectHeightMedianPx: Double?
        let faceFrames: Int
        let featurePrintFrames: Int
        let poseFrames: Int
        let freshFrames: Int
        let identitySwitchesProxy: Int

        static let header = "clip,annotated,decoded_frames,selected_frames,subject_height_median_px,face_frames,feature_print_frames,pose_frames,fresh_frames,identity_switches_proxy\n"
        var csv: String {
            let fields = [Self.escape(clip), annotated ? "yes" : "no", String(decodedFrames),
                          String(selectedFrames), subjectHeightMedianPx.map { String(format: "%.1f", $0) } ?? "",
                          String(faceFrames), String(featurePrintFrames), String(poseFrames),
                          String(freshFrames), String(identitySwitchesProxy)]
            return fields.joined(separator: ",") + "\n"
        }
        private nonisolated static func escape(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
    }

    private func target(in persons: [PersonDetector.DetectedPerson],
                        at seconds: Double, annotation: Annotation?) -> PersonDetector.DetectedPerson? {
        guard !persons.isEmpty else { return nil }
        guard let point = annotation?.points.min(by: { abs($0.timeS - seconds) < abs($1.timeS - seconds) }) else {
            return persons.max(by: { $0.boundingBox.height < $1.boundingBox.height })
        }
        let p = CGPoint(x: point.x, y: point.y)
        return persons.filter { $0.boundingBox.contains(p) }
            .min(by: { abs($0.boundingBox.midX - p.x) < abs($1.boundingBox.midX - p.x) })
    }

    private func evaluate(_ url: URL) async throws -> ClipRow {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "ReadinessEvaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track: \(url.lastPathComponent)"])
        }
        let annotationURL = url.deletingPathExtension().appendingPathExtension("json")
        let annotation: Annotation?
        if FileManager.default.fileExists(atPath: annotationURL.path) {
            annotation = try JSONDecoder().decode(Annotation.self, from: Data(contentsOf: annotationURL))
        } else {
            annotation = nil
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? NSError(domain: "ReadinessEvaluation", code: 2) }

        let detector = PersonDetector()
        let extractor = FaceSignatureExtractor()
        let plan = PersonDetector.DetectionRequestPlan(mode: .reacquiring, roi: nil)
        var decoded = 0, selected = 0, faces = 0, prints = 0, poses = 0, fresh = 0, switches = 0
        var heights: [Double] = []
        var previousID: UUID?
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            decoded += 1
            let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            let start = CACurrentMediaTime()
            let persons = await detector.processFrame(buffer, plan: plan)
            let observationAge = CACurrentMediaTime() - start
            guard let subject = target(in: persons, at: seconds, annotation: annotation) else {
                previousID = nil
                continue
            }
            selected += 1
            heights.append(Double(subject.boundingBox.height) * Double(CVPixelBufferGetHeight(buffer)))
            if observationAge <= DetectionFrameStore.maximumAge { fresh += 1 }
            if subject.poseKeypoints != nil { poses += 1 }
            if let box = subject.faceBoundingBox {
                faces += 1
                if await extractor.extractSignature(from: buffer, faceBoundingBox: box) != nil { prints += 1 }
            }
            if let previousID, previousID != subject.id { switches += 1 }
            previousID = subject.id
        }
        guard reader.status == .completed else {
            throw reader.error ?? NSError(domain: "ReadinessEvaluation", code: 3)
        }
        let ordered = heights.sorted()
        let median = ordered.isEmpty ? nil : ordered[ordered.count / 2]
        return ClipRow(clip: url.lastPathComponent, annotated: annotation != nil,
                       decodedFrames: decoded, selectedFrames: selected,
                       subjectHeightMedianPx: median, faceFrames: faces,
                       featurePrintFrames: prints, poseFrames: poses, freshFrames: fresh,
                       identitySwitchesProxy: switches)
    }

    @Test func replayConsentedFolderWhenConfigured() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let folder = env["ALFIE_READINESS_CLIPS"],
              let output = env["ALFIE_READINESS_OUT"] else { return }
        let clips = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder),
                                                                 includingPropertiesForKeys: nil)
            .filter { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!clips.isEmpty)
        var csv = ClipRow.header
        for clip in clips { csv += try await evaluate(clip).csv }
        try csv.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
        #expect(csv.split(separator: "\n").count == clips.count + 1)
    }

    @Test func syntheticClipExercisesDecoderAndCSVWithoutPeople() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alfie-readiness-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeSyntheticClip(at: url)
        let row = try await evaluate(url)
        #expect(row.decodedFrames == 6)
        #expect(row.selectedFrames == 0)
        #expect(row.faceFrames == 0)
        #expect(row.csv.contains(",6,0,"))
    }

    private func makeSyntheticClip(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160, AVVideoHeightKey: 90
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 160,
                kCVPixelBufferHeightKey as String: 90
            ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "ReadinessEvaluation", code: 4) }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<6 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, kCVPixelFormatType_32BGRA,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
            guard let buffer else { throw NSError(domain: "ReadinessEvaluation", code: 5) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, index.isMultiple(of: 2) ? 0 : 64, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 10)) else {
                throw writer.error ?? NSError(domain: "ReadinessEvaluation", code: 6)
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "ReadinessEvaluation", code: 7) }
    }
}
