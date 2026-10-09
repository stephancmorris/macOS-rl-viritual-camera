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
    private enum StudyError: Error { case invalidAnnotation, invalidConfiguration, emptyDataset }
    private struct Annotation: Decodable {
        let points: [TargetPoint]

        init(points: [TargetPoint]) throws {
            guard !points.isEmpty, points.allSatisfy({
                $0.timeS.isFinite && $0.timeS >= 0 &&
                $0.x.isFinite && (0...1).contains($0.x) &&
                $0.y.isFinite && (0...1).contains($0.y)
            }) else { throw StudyError.invalidAnnotation }
            let sorted = points.sorted { $0.timeS < $1.timeS }
            guard zip(sorted, sorted.dropFirst()).allSatisfy({ pair in pair.0.timeS < pair.1.timeS }) else {
                throw StudyError.invalidAnnotation
            }
            self.points = sorted
        }

        init(from decoder: Decoder) throws {
            enum Keys: CodingKey { case points }
            let container = try decoder.container(keyedBy: Keys.self)
            try self.init(points: container.decode([TargetPoint].self, forKey: .points))
        }

        func nearest(at seconds: Double) -> TargetPoint? {
            guard seconds.isFinite, seconds >= 0 else { return nil }
            // Sorted timestamps keep the earlier sample on an equal-distance tie.
            return points.min { abs($0.timeS - seconds) < abs($1.timeS - seconds) }
        }
    }

    private func configuration(_ env: [String: String]) throws -> (folder: String, output: String)? {
        let folder = env["ALFIE_READINESS_CLIPS"], output = env["ALFIE_READINESS_OUT"]
        if folder == nil && output == nil { return nil }
        guard let folder, let output,
              folder.hasPrefix("/"), output.hasPrefix("/"),
              !folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudyError.invalidConfiguration
        }
        return (folder, output)
    }

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
        guard !persons.isEmpty, seconds.isFinite, seconds >= 0 else { return nil }
        guard let annotation else {
            return persons.max(by: { $0.boundingBox.height < $1.boundingBox.height })
        }
        guard let point = annotation.nearest(at: seconds) else { return nil }
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

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ALFIE_READINESS_CLIPS"] != nil ||
                   ProcessInfo.processInfo.environment["ALFIE_READINESS_OUT"] != nil,
                   "No consented dataset configured; synthetic checks do not qualify readiness"))
    func replayConsentedFolderWhenConfigured() async throws {
        let env = ProcessInfo.processInfo.environment
        let config = try #require(try configuration(env))
        let folder = config.folder, output = config.output
        let clips = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder),
                                                                 includingPropertiesForKeys: nil)
            .filter { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !clips.isEmpty else { throw StudyError.emptyDataset }
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
        #expect(row.csv.contains(",no,6,0,"))
        #expect(!row.annotated)
    }


    #if DEBUG
    @Test(arguments: [false, true])
    func validationClipStartupClearsPriorCameraRate(unreadable: Bool) async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alfie-rate-truth-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        if !unreadable { try await makeSyntheticClip(at: url) }

        let suite = "alfie-rate-truth-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
                                   admissionRecords: AdmissionRecordStore(defaults: defaults))
        // Unrouted B exercises real clip startup without starting the show output.
        let preview = show.addChannel(.b)
        defer { preview.stopCapture() }
        preview.setAdmissionFormatForTesting(width: 1920, height: 1080, fps: 50)
        #expect(preview.admissionInput.captureFPS == 50)
        preview.preferredInputSource = .validationClip
        preview.loopValidationClip = false
        preview.setValidationClipURL(url)

        try await preview.startCapture()
        let playbackGeneration = preview.revisions.sourceGeneration

        #expect(preview.activeInputSource == .validationClip)
        #expect(preview.sourceIdentity?.inputKind == "Validation clip")
        #expect(preview.sourceIdentity?.configuredCaptureFPS == nil)
        #expect(preview.configuredCaptureFPS == nil)
        #expect(preview.admissionInput.captureFPS == nil)
        #expect(show.pairAdmissionContext(preview: .b).previewCaptureFPS == nil)
        #expect(!show.channelA.isRunning)
        if unreadable {
            // The public startup returns before the decoder reports a missing file.
            for _ in 0..<100 {
                if !preview.isRunning { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(!preview.isRunning)
            #expect(preview.revisions.sourceGeneration > playbackGeneration)
            #expect(preview.latestRenderedFrame == nil)
            #expect(preview.error != nil)
            #expect(preview.configuredCaptureFPS == nil)
            #expect(preview.admissionInput.captureFPS == nil)
            #expect(show.pairAdmissionContext(preview: .b).previewCaptureFPS == nil)
        }
    }

    private final class ClipLifecycleSink: ProgramOutputSink {
        let route: ProgramOutputManager.Route = .display
        var isAvailable: Bool { true }
        var summary: String { "clip lifecycle fake" }
        var detail: String { "in-memory handoff" }
        var lastErrorDescription: String? { nil }
        var onStateChange: (() -> Void)?
        private(set) var sent: [CVPixelBuffer] = []
        func connect() {}
        func disconnect() {}
        func updateCaptureStatus(isRunning: Bool) {}
        func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
            sent.append(pixelBuffer)
            return true
        }
    }

    private enum ClipCompletion: CaseIterable { case eof, cancelled, failed }

    private func clipLifecycleShow(defaults: UserDefaults) -> (ShowCoordinator, ClipLifecycleSink) {
        let sink = ClipLifecycleSink()
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: [sink]),
                                   admissionRecords: AdmissionRecordStore(defaults: defaults))
        show.addChannel(.b)
        show.channelA.setRunningForTesting(true)
        show.channelA.outputPort.start()
        show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        show.clock = { 1000 }
        show.router.clock = { 1000 }
        return (show, sink)
    }

    @discardableResult
    private func prepareClipLifecycleFrame(_ channel: CameraManager) throws -> RenderedChannelFrame {
        let buffer = try #require(ProgramRouter.makeBlackFrame(width: 1920, height: 1080))
        let frame = RenderedChannelFrame(
            channelID: channel.channelID, revisions: channel.revisions, sourceTimestamp: 1,
            processingStartedAt: 1000, renderedAt: 1000, crop: .fullFrame,
            outputSize: CGSize(width: 1920, height: 1080), isRepeat: false, pixelBuffer: buffer)
        channel.setLatestRenderedFrameForTesting(frame)
        return frame
    }

    @Test func naturalPreviewClipEOFRevokesTakeAndRetiresSource() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alfie-clip-eof-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeSyntheticClip(at: url)
        let suite = "alfie-clip-eof-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (show, sink) = clipLifecycleShow(defaults: defaults)
        defer { show.stopShow() }
        let preview = try #require(show.channel(.b))
        let aBefore = show.channelA.revisions
        preview.preferredInputSource = .validationClip
        preview.loopValidationClip = false
        preview.setValidationClipURL(url)
        try await preview.startCapture()
        let generation = preview.revisions.sourceGeneration
        for _ in 0..<200 {
            if !preview.isRunning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!preview.isRunning)
        #expect(preview.renderedFrameCount > 0) // The actual decoder/render path produced a candidate.
        #expect(preview.error == nil)
        #expect(preview.validationClipStatus.hasPrefix("Finished "))
        #expect(preview.revisions.sourceGeneration > generation)
        #expect(preview.latestRenderedFrame == nil)
        // Freeze freshness at the just-finished frame even on the old implementation;
        // this proves retirement, rather than eventually passing because a frame ages out.
        if let frame = preview.latestRenderedFrame { show.clock = { frame.renderedAt } }
        #expect(show.take() == .rejected(.notEligible(.preparing)))
        #expect(show.programChannel == .a)
        #expect(show.router.routeGeneration == 0)
        #expect(sink.sent.isEmpty)
        #expect(show.channelA.isRunning)
        #expect(show.channelA.revisions == aBefore)
    }

    @Test(arguments: ClipCompletion.allCases)
    private func currentClipCompletionRetiresCandidateExactlyOnce(completion: ClipCompletion) throws {
        let suite = "alfie-clip-current-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (show, sink) = clipLifecycleShow(defaults: defaults)
        defer { show.stopShow() }
        let preview = try #require(show.channel(.b))
        preview.setRunningForTesting(true)
        let generation = preview.revisions.sourceGeneration
        let aBefore = show.channelA.revisions
        try prepareClipLifecycleFrame(preview)
        #expect(TakeAvailability.evaluate(take: show.takeInputs()!, program: .a, preview: .b,
                                          standard: .p50, editLive: false).isEligible)
        let failure: Error? = completion == .failed ? NSError(domain: "ClipLifecycle", code: 1) : nil
        preview.completeValidationClipForTesting(generation: generation, cancelled: completion == .cancelled, failure: failure)
        #expect(!preview.isRunning)
        #expect(preview.revisions.sourceGeneration > generation)
        #expect(preview.latestRenderedFrame == nil)
        #expect((preview.error != nil) == (completion == .failed))
        #expect(show.take() == .rejected(.notEligible(.preparing)))
        #expect(show.programChannel == .a)
        #expect(show.router.routeGeneration == 0)
        #expect(sink.sent.isEmpty)
        #expect(show.channelA.isRunning)
        #expect(show.channelA.revisions == aBefore)
        let after = preview.revisions
        let detectionAfter = preview.detectionGenerationForTesting
        preview.completeValidationClipForTesting(generation: generation, cancelled: true)
        #expect(preview.revisions == after)
        #expect(preview.detectionGenerationForTesting == detectionAfter)
    }

    @Test(arguments: ClipCompletion.allCases)
    private func retiredClipCompletionCannotStopOrInvalidateReplacement(completion: ClipCompletion) throws {
        let suite = "alfie-clip-stale-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (show, _) = clipLifecycleShow(defaults: defaults)
        defer { show.stopShow() }
        let preview = try #require(show.channel(.b))
        preview.setRunningForTesting(true)
        let retired = preview.revisions.sourceGeneration
        preview.stopCapture()
        preview.setRunningForTesting(true)
        let frame = try prepareClipLifecycleFrame(preview)
        let current = preview.revisions
        let detection = preview.detectionGenerationForTesting
        let failure: Error? = completion == .failed ? NSError(domain: "ClipLifecycle", code: 2) : nil
        preview.completeValidationClipForTesting(generation: retired, cancelled: completion == .cancelled, failure: failure)
        #expect(preview.isRunning)
        #expect(preview.revisions == current)
        #expect(preview.detectionGenerationForTesting == detection)
        #expect(preview.error == nil)
        #expect(preview.latestRenderedFrame?.pixelBuffer === frame.pixelBuffer)
        #expect(show.take() == .committed(newProgram: .b)) // Current healthy Preview remains eligible.
    }
    #endif


    @Test func invalidAnnotationsNeverFallBackToUnannotatedSelection() throws {
        #expect(throws: StudyError.self) { try Annotation(points: []) }
        for value in [Double.nan, .infinity, -.infinity, -1] {
            #expect(throws: StudyError.self) {
                try Annotation(points: [.init(timeS: value, x: 0.5, y: 0.5)])
            }
        }
        for value in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            #expect(throws: StudyError.self) {
                try Annotation(points: [.init(timeS: 0, x: value, y: 0.5)])
            }
            #expect(throws: StudyError.self) {
                try Annotation(points: [.init(timeS: 0, x: 0.5, y: value)])
            }
        }
        #expect(throws: StudyError.self) {
            try Annotation(points: [.init(timeS: 0, x: 0, y: 0), .init(timeS: 0, x: 1, y: 1)])
        }
        #expect(throws: StudyError.self) {
            try JSONDecoder().decode(Annotation.self, from: Data(#"{"points":[]}"#.utf8))
        }
    }

    @Test func annotatedTargetDoesNotPromoteTallestPerson() throws {
        let intended = PersonDetector.DetectedPerson(id: UUID(),
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3),
            confidence: 1, timestamp: 0, poseKeypoints: nil, faceBoundingBox: nil, faceLandmarkRatios: nil)
        let tallest = PersonDetector.DetectedPerson(id: UUID(),
            boundingBox: CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.8),
            confidence: 1, timestamp: 0, poseKeypoints: nil, faceBoundingBox: nil, faceLandmarkRatios: nil)
        let annotation = try Annotation(points: [.init(timeS: 0, x: 0.2, y: 0.2)])
        #expect(target(in: [tallest, intended], at: 0, annotation: annotation)?.id == intended.id)
        #expect(target(in: [intended, tallest], at: 0, annotation: nil)?.id == tallest.id)
        let absent = try Annotation(points: [.init(timeS: 0, x: 0.5, y: 0.5)])
        #expect(target(in: [tallest, intended], at: 0, annotation: absent) == nil)
        #expect(target(in: [tallest, intended], at: .nan, annotation: annotation) == nil)
    }

    @Test func nearestAnnotationIsDeterministicAndRejectsInvalidFrameTime() throws {
        let annotation = try Annotation(points: [
            .init(timeS: 2, x: 1, y: 1), .init(timeS: 0, x: 0, y: 0)])
        #expect(annotation.nearest(at: 1)?.timeS == 0)
        #expect(annotation.nearest(at: 2)?.x == 1)
        for time in [Double.nan, .infinity, -.infinity, -1] {
            #expect(annotation.nearest(at: time) == nil)
        }
    }

    @Test func missingAndPartialDatasetConfigurationAreDistinct() throws {
        #expect(try configuration([:]) == nil)
        for env in [["ALFIE_READINESS_CLIPS": "/tmp/clips"],
                    ["ALFIE_READINESS_OUT": "/tmp/out.csv"],
                    ["ALFIE_READINESS_CLIPS": "", "ALFIE_READINESS_OUT": "/tmp/out.csv"],
                    ["ALFIE_READINESS_CLIPS": "/tmp/clips", "ALFIE_READINESS_OUT": "relative.csv"]] {
            #expect(throws: StudyError.self) { try configuration(env) }
        }
        let configured = try #require(try configuration([
            "ALFIE_READINESS_CLIPS": "/tmp/clips", "ALFIE_READINESS_OUT": "/tmp/out.csv"]))
        #expect(configured.folder == "/tmp/clips")
        #expect(configured.output == "/tmp/out.csv")
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
