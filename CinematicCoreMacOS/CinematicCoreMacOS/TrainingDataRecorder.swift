//
//  TrainingDataRecorder.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/10/2026.
//  Ticket: RL-01 - Real-World Data Recording
//

import Foundation
import Combine
import CoreGraphics
import AppKit
import OSLog

private actor TrainingDataSessionWriter {
    private let fileHandle: FileHandle
    private var isClosed = false

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func write(_ data: Data) throws -> Int64 {
        guard !isClosed else { throw CocoaError(.fileWriteUnknown) }
        try fileHandle.write(contentsOf: data)
        return Int64(data.count)
    }

    func close() throws {
        guard !isClosed else { return }
        try fileHandle.close()
        isClosed = true
    }
}

/// Records per-frame training data to JSON Lines files for RL agent training.
/// Data format is designed for direct consumption by Gymnasium environment (Task 3.2).
@MainActor
final class TrainingDataRecorder: ObservableObject {
    private nonisolated static let logger = Logger(subsystem: "com.alfie", category: "TrainingData")
    private static let consentDefaultsKey = "alfie.trainingDataRecorder.hasConsent"

    // MARK: - Configuration

    struct Config: Sendable {
        /// Number of frames to buffer before flushing to disk
        var bufferSize: Int = 100

        /// Record every Nth frame (1 = all frames, 2 = every other, etc.)
        var subsampleRate: Int = 1

        /// Delete completed training sessions older than this many days.
        var retentionDays: Int = 30
    }

    @Published var config = Config()

    // MARK: - Published State

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var stats: RecordingStats = .init()
    @Published private(set) var lastErrorDescription: String?

    @Published var hasUserConsentedToTrainingData: Bool {
        didSet {
            UserDefaults.standard.set(
                hasUserConsentedToTrainingData,
                forKey: Self.consentDefaultsKey
            )
        }
    }

    /// When set, this crop is used as the "ideal" label instead of ShotComposer's auto crop
    @Published var manualCropOverride: CropEngine.CropRect?

    struct RecordingStats: Sendable {
        var framesRecorded: Int = 0
        var sessionDuration: TimeInterval = 0
        var fileSizeBytes: Int64 = 0
        var droppedFrames: Int = 0
    }

    // MARK: - Codable Models (per-frame observation)

    struct FrameObservation: Codable, Sendable {
        let t: Double
        let frameIdx: Int
        let speaker: SpeakerData?
        let keypoints: KeypointData?
        let currentCrop: CropData
        let idealCrop: IdealCropData
        let interpolating: Bool
    }

    struct SpeakerData: Codable, Sendable {
        let x: Double
        let y: Double
        let z: Double
        let bbox: [Double]
        let confidence: Double
    }

    struct KeypointData: Codable, Sendable {
        let headX: Double
        let headY: Double
        let waistX: Double
        let waistY: Double
        let poseConfidence: Double
    }

    struct CropData: Codable, Sendable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        let zoom: Double
    }

    struct IdealCropData: Codable, Sendable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        let zoom: Double
        let source: String
    }

    struct SessionMetadata: Codable, Sendable {
        let sessionId: String
        let startTime: String
        var endTime: String?
        var durationSeconds: Double?
        var totalFrames: Int?
        let fps: Int
        let resolution: ResolutionData
        let cameraName: String
        let labelSource: String
        let composerConfig: ComposerConfigData
        let detectorConfig: DetectorConfigData
    }

    struct ResolutionData: Codable, Sendable {
        let width: Int
        let height: Int
    }

    struct ComposerConfigData: Codable, Sendable {
        let deadzoneThreshold: Double
        let smoothingFactor: Double
        let targetHoldDuration: Double
        let stageHorizontalMargin: Double
        let stageVerticalMargin: Double
    }

    struct DetectorConfigData: Codable, Sendable {
        let confidenceThreshold: Double
        let maxPersons: Int
        let highAccuracy: Bool
    }

    // MARK: - Private State

    private var sessionDirectory: URL?
    private var sessionWriter: TrainingDataSessionWriter?
    private var pendingWriteTasks: [Task<Int64, Error>] = []
    private var frameIndex: Int = 0
    private var sessionStartTime: Date?
    private var sessionId: String?
    private var buffer: [Data] = []
    private var pendingMetadata: SessionMetadata?

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    init(defaults: UserDefaults = .standard) {
        self.hasUserConsentedToTrainingData = defaults.bool(forKey: Self.consentDefaultsKey)
    }

    /// Base output directory for all training data sessions
    var outputDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("CinematicCore/TrainingData", isDirectory: true)
    }

    // MARK: - Public Methods

    /// Start a new recording session
    func startRecording(
        cameraName: String,
        resolution: CGSize,
        composerConfig: ShotComposer.Config,
        detectorConfig: PersonDetector.Config
    ) {
        guard !isRecording else { return }
        guard hasUserConsentedToTrainingData else {
            lastErrorDescription = "Training data recording requires explicit operator consent."
            Self.logger.error("Training data recording blocked because consent has not been granted")
            return
        }

        deleteExpiredSessions()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let id = "session_\(timestamp)"

        // Create session directory
        let sessionDir = outputDirectory.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("Failed to create session directory: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Create frames.jsonl file
        let framesFile = sessionDir.appendingPathComponent("frames.jsonl")
        FileManager.default.createFile(atPath: framesFile.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: framesFile.path) else {
            Self.logger.error("Failed to open frames.jsonl for writing")
            lastErrorDescription = "Failed to open frames.jsonl for writing."
            return
        }

        // Store state
        sessionWriter = TrainingDataSessionWriter(fileHandle: handle)
        sessionDirectory = sessionDir
        sessionId = id
        sessionStartTime = Date()
        frameIndex = 0
        buffer = []
        pendingWriteTasks = []
        stats = .init()
        lastErrorDescription = nil

        // Build metadata (finalized on stop)
        let isoFormatter = ISO8601DateFormatter()
        pendingMetadata = SessionMetadata(
            sessionId: id,
            startTime: isoFormatter.string(from: Date()),
            fps: 30,
            resolution: ResolutionData(width: Int(resolution.width), height: Int(resolution.height)),
            cameraName: cameraName,
            labelSource: manualCropOverride != nil ? "manual" : "auto",
            composerConfig: ComposerConfigData(
                deadzoneThreshold: composerConfig.deadzoneThreshold,
                smoothingFactor: Double(composerConfig.smoothingFactor),
                targetHoldDuration: composerConfig.targetHoldDuration,
                stageHorizontalMargin: composerConfig.stageHorizontalMargin,
                stageVerticalMargin: composerConfig.stageVerticalMargin
            ),
            detectorConfig: DetectorConfigData(
                confidenceThreshold: Double(detectorConfig.confidenceThreshold),
                maxPersons: detectorConfig.maxPersons,
                highAccuracy: detectorConfig.useHighAccuracy
            )
        )

        isRecording = true
        Self.logger.notice("Started recording session: \(id, privacy: .public)")
    }

    /// Stop the current recording session
    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false

        // Flush remaining buffer
        if !buffer.isEmpty {
            let batch = buffer
            buffer = []
            flushBuffer(batch)
        }

        await finishPendingWrites()

        // Finalize metadata
        if var metadata = pendingMetadata, let sessionDir = sessionDirectory {
            let isoFormatter = ISO8601DateFormatter()
            metadata.endTime = isoFormatter.string(from: Date())
            metadata.durationSeconds = stats.sessionDuration
            metadata.totalFrames = stats.framesRecorded

            let metadataFile = sessionDir.appendingPathComponent("metadata.json")
            let metaEncoder = JSONEncoder()
            metaEncoder.keyEncodingStrategy = .convertToSnakeCase
            metaEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let data = try metaEncoder.encode(metadata)
                try data.write(to: metadataFile, options: [.atomic])
            } catch {
                lastErrorDescription = "Failed to write recording metadata: \(error.localizedDescription)"
                Self.logger.error("Failed to write recording metadata: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try await sessionWriter?.close()
        } catch {
            lastErrorDescription = "Failed to close recording file: \(error.localizedDescription)"
            Self.logger.error("Failed to close recording file: \(error.localizedDescription, privacy: .public)")
        }

        sessionWriter = nil
        sessionDirectory = nil
        sessionId = nil
        sessionStartTime = nil
        pendingMetadata = nil

        Self.logger.notice("Stopped recording. Frames: \(self.stats.framesRecorded)")
    }

    /// Record a single frame observation
    func recordFrame(
        timestamp: Double,
        persons: [PersonDetector.DetectedPerson],
        currentCrop: CropEngine.CropRect,
        idealCrop: CropEngine.CropRect?,
        isInterpolating: Bool
    ) {
        guard isRecording else { return }

        // Subsample check
        guard frameIndex % config.subsampleRate == 0 else {
            frameIndex += 1
            return
        }

        // Build speaker data from primary person
        let primaryPerson = persons.first
        let speakerData: SpeakerData? = primaryPerson.map { person in
            let bbox = person.boundingBox
            return SpeakerData(
                x: bbox.midX,
                y: bbox.midY,
                z: bbox.height > 0.01 ? 1.0 / bbox.height : 0.0,
                bbox: [bbox.origin.x, bbox.origin.y, bbox.width, bbox.height],
                confidence: Double(person.confidence)
            )
        }

        // Build keypoint data
        let keypointData: KeypointData? = primaryPerson?.poseKeypoints.map { kp in
            KeypointData(
                headX: kp.head.x,
                headY: kp.head.y,
                waistX: kp.waist.x,
                waistY: kp.waist.y,
                poseConfidence: Double(kp.confidence)
            )
        }

        // Build current crop data
        let currentCropData = CropData(
            x: currentCrop.origin.x,
            y: currentCrop.origin.y,
            w: currentCrop.size.width,
            h: currentCrop.size.height,
            zoom: currentCrop.size.height > 0.01 ? 1.0 / currentCrop.size.height : 1.0
        )

        // Build ideal crop data (manual override or auto from ShotComposer)
        let idealSource: CropEngine.CropRect
        let sourceLabel: String
        if let manual = manualCropOverride {
            idealSource = manual
            sourceLabel = "manual"
        } else if let auto_ = idealCrop {
            idealSource = auto_
            sourceLabel = "auto"
        } else {
            idealSource = currentCrop
            sourceLabel = "auto"
        }

        let idealCropData = IdealCropData(
            x: idealSource.origin.x,
            y: idealSource.origin.y,
            w: idealSource.size.width,
            h: idealSource.size.height,
            zoom: idealSource.size.height > 0.01 ? 1.0 / idealSource.size.height : 1.0,
            source: sourceLabel
        )

        let observation = FrameObservation(
            t: timestamp,
            frameIdx: frameIndex,
            speaker: speakerData,
            keypoints: keypointData,
            currentCrop: currentCropData,
            idealCrop: idealCropData,
            interpolating: isInterpolating
        )

        // Encode to JSON + newline
        guard var data = try? jsonEncoder.encode(observation) else {
            stats.droppedFrames += 1
            frameIndex += 1
            return
        }
        data.append(0x0A) // newline

        buffer.append(data)

        // Flush if buffer is full
        if buffer.count >= config.bufferSize {
            let batch = buffer
            buffer = []
            flushBuffer(batch)
        }

        frameIndex += 1
        stats.framesRecorded += 1
        if let start = sessionStartTime {
            stats.sessionDuration = Date().timeIntervalSince(start)
        }
    }

    /// Open the output directory in Finder
    func openInFinder() {
        NSWorkspace.shared.open(outputDirectory)
    }

    func deleteExpiredSessions() {
        let maxAge = TimeInterval(config.retentionDays * 24 * 60 * 60)
        guard maxAge > 0 else { return }

        do {
            let now = Date()
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: outputDirectory.path) else { return }
            let sessionURLs = try fileManager.contentsOfDirectory(
                at: outputDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            for url in sessionURLs where url.lastPathComponent.hasPrefix("session_") {
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                guard let modifiedAt = values.contentModificationDate,
                      now.timeIntervalSince(modifiedAt) > maxAge else {
                    continue
                }
                try fileManager.removeItem(at: url)
            }
        } catch {
            lastErrorDescription = "Failed to delete expired training sessions: \(error.localizedDescription)"
            Self.logger.error("Failed to delete expired sessions: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteAllCompletedSessions() {
        guard !isRecording else { return }

        do {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: outputDirectory.path) else { return }
            let sessionURLs = try fileManager.contentsOfDirectory(
                at: outputDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in sessionURLs where url.lastPathComponent.hasPrefix("session_") {
                try fileManager.removeItem(at: url)
            }
        } catch {
            lastErrorDescription = "Failed to delete training sessions: \(error.localizedDescription)"
            Self.logger.error("Failed to delete training sessions: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private Methods

    private func flushBuffer(_ batch: [Data]) {
        guard let writer = sessionWriter else {
            stats.droppedFrames += batch.count
            lastErrorDescription = "Training data writer is not available."
            return
        }

        let combined = batch.reduce(Data()) { $0 + $1 }

        let writeTask = Task {
            try await writer.write(combined)
        }
        pendingWriteTasks.append(writeTask)

        Task { @MainActor [weak self] in
            do {
                let byteCount = try await writeTask.value
                self?.stats.fileSizeBytes += byteCount
            } catch {
                self?.stats.droppedFrames += batch.count
                self?.lastErrorDescription = "Failed to write training data: \(error.localizedDescription)"
                Self.logger.error("Failed to write training data: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func finishPendingWrites() async {
        let tasks = pendingWriteTasks
        pendingWriteTasks = []

        for task in tasks {
            do {
                _ = try await task.value
            } catch {
                lastErrorDescription = "Failed to flush training data: \(error.localizedDescription)"
                Self.logger.error("Failed to flush training data: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
