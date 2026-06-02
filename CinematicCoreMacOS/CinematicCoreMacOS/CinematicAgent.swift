//
//  CinematicAgent.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/25/2026.
//  Ticket: APP-02 - CoreML RL Agent Integration
//

import Combine
@preconcurrency import CoreML
import CoreGraphics
import Foundation
import OSLog

/// RL-trained cinematic framing agent backed by a CoreML model.
///
/// Loads `CinematicFraming.mlpackage` from the app bundle, maintains internal
/// crop state, and predicts pan/tilt/zoom velocity actions each frame.
/// Designed to replace `ShotComposer` when toggled on in `CameraManager`.
///
/// Observation vector (18-dim) and action semantics exactly match
/// `training/cinematic_env.py` and `training/bc_dataset.py`.
@MainActor
final class CinematicAgent: ObservableObject {

    private nonisolated static let logger = Logger(subsystem: "com.alfie", category: "CinematicAgent")

    // MARK: - Published State

    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var modelStatus: String = "Model idle"
    @Published private(set) var lastPredictedCrop: CropEngine.CropRect?
    @Published private(set) var inferenceFailureCount: Int = 0
    @Published private(set) var lastInferenceErrorDescription: String?

    // MARK: - Constants (must match cinematic_env.py exactly)

    private let maxPanSpeed:  Float = 0.02
    private let maxTiltSpeed: Float = 0.02
    private let maxZoomSpeed: Float = 0.05
    /// Model normalization constant. Must match `cinematic_env.py` exactly —
    /// the PPO observation normalizes zoom against this value, so changing it
    /// shifts what the network sees and breaks the trained policy.
    private let maxZoom:      Float = 4.0
    private let aspectRatio:  Float = 16.0 / 9.0

    /// Runtime quality clamp derived from the source resolution. The smallest
    /// crop the agent is allowed to take is one resolution tier below the
    /// source (e.g. 4K source → 1080p min crop = 2× max zoom). Updated by
    /// `updateSourceResolution(_:)` whenever capture format changes.
    private var qualityMaxZoom: Float = 2.0

    // MARK: - Private State

    private var model: MLModel?

    /// Speaker center from the previous frame (for velocity computation)
    private var previousSpeakerCenter: CGPoint?

    /// Agent's internal crop state — updated each predict() call
    private var cropX:    Float = 0.0
    private var cropY:    Float = 0.0
    private var cropZoom: Float = 1.0
    private var modelLoadWorkItem: DispatchWorkItem?
    private var lastInferenceStatusUpdate = Date.distantPast

    // MARK: - Lifecycle

    init() {}

    deinit {
        modelLoadWorkItem?.cancel()
    }

    // MARK: - Model Loading

    func ensureModelLoaded() {
        guard model == nil, modelLoadWorkItem == nil else { return }
        loadModel()
    }

    private func loadModel() {
        modelLoadWorkItem?.cancel()
        modelLoadWorkItem = nil
        isModelLoaded = false
        modelStatus = "Loading model..."

        guard let url = Bundle.main.url(
            forResource: "CinematicFraming",
            withExtension: "mlpackage"
        ) else {
            modelStatus = "Model not found in bundle"
            return
        }

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            do {
                // .mlpackage must be compiled before loading; compileModel produces a
                // temporary .mlmodelc that is valid for this process lifetime.
                let compiledURL = try MLModel.compileModel(at: url)
                let config = MLModelConfiguration()
                config.computeUnits = .cpuAndNeuralEngine
                let loadedModel = try MLModel(contentsOf: compiledURL, configuration: config)

                guard workItem?.isCancelled == false else { return }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.model = loadedModel
                    self.isModelLoaded = true
                    self.modelStatus = "Model loaded (Neural Engine)"
                    self.modelLoadWorkItem = nil
                }
            } catch {
                guard workItem?.isCancelled == false else { return }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.modelStatus = "Failed to load: \(error.localizedDescription)"
                    self.modelLoadWorkItem = nil
                }
            }
        }

        guard let workItem else { return }
        modelLoadWorkItem = workItem
        DispatchQueue.global(qos: .utility).async(execute: workItem)
    }

    // MARK: - Public Interface

    /// Sync internal crop state when switching from rule-based to ML mode.
    /// Call this before the first `predict()` call to avoid a jump.
    func initialize(from crop: CropEngine.CropRect) {
        cropX    = Float(crop.origin.x)
        cropY    = Float(crop.origin.y)
        cropZoom = crop.size.height > 0.001 ? Float(1.0 / crop.size.height) : 1.0
        previousSpeakerCenter = nil
    }

    /// Update the resolution-derived quality clamp. Call whenever the
    /// capture format changes (e.g. on camera switch or `activeFormat` change).
    /// Smallest allowed crop is one resolution tier below the source.
    func updateSourceResolution(width: Int, height: Int) {
        let newCap = Self.qualityMaxZoom(forSourceHeight: height)
        guard newCap != qualityMaxZoom else { return }
        qualityMaxZoom = newCap
        Self.logger.notice("Quality clamp updated: source \(width)x\(height), maxZoom=\(newCap, privacy: .public)")
    }

    /// Map source pixel height to the maximum zoom that keeps the crop at or
    /// above the next resolution tier down (e.g. 4K → min crop 1080p → 2×).
    /// Delegates to `CropEngine.QualityFloor`, the single source of truth for
    /// the resolution-tier table — zoom is the reciprocal of the min crop
    /// height fraction.
    static func qualityMaxZoom(forSourceHeight height: Int) -> Float {
        let fraction = CropEngine.QualityFloor.forSource(height: height).minCropHeightFraction
        guard fraction > 0 else { return 1.0 }
        return 1.0 / Float(fraction)
    }

    /// Clear tracking state (e.g. on subject change or session end).
    func reset() {
        previousSpeakerCenter = nil
        cropX    = 0.0
        cropY    = 0.0
        cropZoom = 1.0
        lastPredictedCrop = nil
        lastInferenceErrorDescription = nil
    }

    /// Run one inference step.
    ///
    /// - Parameters:
    ///   - person: The primary detected person this frame (nil if no detection).
    ///   - currentCrop: The crop engine's current crop, used only as fallback
    ///     if the model is unavailable.
    /// - Returns: The new target crop for this frame.
    func predict(
        person: PersonDetector.DetectedPerson?,
        currentCrop: CropEngine.CropRect
    ) -> CropEngine.CropRect {
        guard let model else {
            return currentCrop
        }

        // Build 18-dim observation
        let obs = buildObservation(person: person)

        // Build MLMultiArray input (shape: [1, 18])
        guard let input = try? MLMultiArray(shape: [1, 18], dataType: .float32) else {
            recordInferenceFailure("Could not allocate model input.")
            return currentCrop
        }
        for (i, value) in obs.enumerated() {
            input[i] = NSNumber(value: value)
        }

        // Run inference
        do {
            let inputProvider = try MLDictionaryFeatureProvider(
                dictionary: ["observation": input]
            )
            let output = try model.prediction(from: inputProvider)

            guard let actionArray = output.featureValue(for: "action")?.multiArrayValue else {
                recordInferenceFailure("Model output did not include an action tensor.")
                return currentCrop
            }

            guard actionArray.count >= 3 else {
                recordInferenceFailure("Model action tensor had \(actionArray.count) value(s); expected 3.")
                return currentCrop
            }

            let dx = actionArray[0].floatValue * maxPanSpeed
            let dy = actionArray[1].floatValue * maxTiltSpeed
            let dz = actionArray[2].floatValue * maxZoomSpeed

            let newCrop = applyCropUpdate(dx: dx, dy: dy, dz: dz)
            lastPredictedCrop = newCrop
            lastInferenceErrorDescription = nil
            return newCrop

        } catch {
            recordInferenceFailure(error.localizedDescription)
            return currentCrop
        }
    }

    private func recordInferenceFailure(_ message: String) {
        inferenceFailureCount += 1
        lastInferenceErrorDescription = message

        let now = Date()
        guard now.timeIntervalSince(lastInferenceStatusUpdate) >= 2 else { return }
        lastInferenceStatusUpdate = now
        modelStatus = "Inference fallback: \(message)"
    }

    // MARK: - Observation Vector

    /// Build the 18-dim float observation vector.
    /// Indices match `bc_dataset.py:build_observation()` exactly.
    private func buildObservation(
        person: PersonDetector.DetectedPerson?
    ) -> [Float] {
        let hasPerson: Float = person != nil ? 1.0 : 0.0

        let spX:  Float
        let spY:  Float
        let spZ:  Float
        let headX: Float
        let headY: Float
        let waistX: Float
        let waistY: Float
        let poseConf: Float

        if let p = person {
            spX = Float(p.boundingBox.midX)
            spY = Float(p.boundingBox.midY)
            // z = 1/height (depth proxy), normalised to [0,1] by dividing by 10
            spZ = min(Float(1.0 / p.boundingBox.height) / 10.0, 1.0)

            if let kp = p.poseKeypoints {
                headX    = Float(kp.head.x)
                headY    = Float(kp.head.y)
                waistX   = Float(kp.waist.x)
                waistY   = Float(kp.waist.y)
                poseConf = kp.confidence
            } else {
                headX = 0; headY = 0; waistX = 0; waistY = 0; poseConf = 0
            }
        } else {
            spX = 0; spY = 0; spZ = 0
            headX = 0; headY = 0; waistX = 0; waistY = 0; poseConf = 0
        }

        // Crop dimensions derived from internal zoom state
        let cropH = 1.0 / cropZoom
        var cropW = cropH * aspectRatio
        if cropW > 1.0 { cropW = 1.0 }
        let zoomNorm = min(cropZoom / maxZoom, 1.0)

        // Speaker velocity (frames * 30fps ≈ per-second velocity, clamped to [-1, 1])
        var velX: Float = 0
        var velY: Float = 0
        if let prev = previousSpeakerCenter, let p = person {
            let cx = Float(p.boundingBox.midX)
            let cy = Float(p.boundingBox.midY)
            velX = max(-1.0, min(1.0, (cx - Float(prev.x)) * 30.0))
            velY = max(-1.0, min(1.0, (cy - Float(prev.y)) * 30.0))
        }
        if let p = person {
            previousSpeakerCenter = CGPoint(x: p.boundingBox.midX, y: p.boundingBox.midY)
        }

        // Head/waist relative position within current crop
        var headRelY:  Float = 0
        var waistRelY: Float = 0
        if cropH > 0.01, hasPerson > 0.5 {
            headRelY  = max(0, min(1, (headY  - cropY) / cropH))
            waistRelY = max(0, min(1, (waistY - cropY) / cropH))
        }

        return [
            hasPerson, spX, spY, spZ,
            headX, headY, waistX, waistY,
            cropX, cropY, cropW, cropH,
            zoomNorm, velX, velY,
            headRelY, waistRelY, poseConf,
        ]
    }

    // MARK: - Crop Update

    /// Apply velocity deltas to internal crop state and return the new CropRect.
    /// Clamp logic mirrors `CinematicFramingEnv._apply_action()` in cinematic_env.py.
    private func applyCropUpdate(dx: Float, dy: Float, dz: Float) -> CropEngine.CropRect {
        // Update zoom, clamped [1, effectiveMaxZoom]. The effective ceiling is
        // the smaller of the model's training-time max (4.0) and the runtime
        // quality clamp derived from source resolution — the latter prevents
        // crops that would require upscaling past one resolution tier.
        let effectiveMaxZoom = min(maxZoom, qualityMaxZoom)
        cropZoom = max(1.0, min(effectiveMaxZoom, cropZoom + dz))

        // Compute crop dimensions from zoom (enforce 16:9, fit within canvas)
        var h = 1.0 / cropZoom
        var w = h * aspectRatio
        if w > 1.0 {
            w = 1.0
            h = w / aspectRatio
        }

        // Apply pan/tilt, clamped so crop stays within [0, 1] canvas
        cropX = max(0.0, min(1.0 - w, cropX + dx))
        cropY = max(0.0, min(1.0 - h, cropY + dy))

        return CropEngine.CropRect(
            origin: CGPoint(x: Double(cropX), y: Double(cropY)),
            size:   CGSize(width: Double(w),   height: Double(h))
        )
    }
}
