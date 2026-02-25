//
//  CinematicAgent.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/25/2026.
//  Ticket: APP-02 - CoreML RL Agent Integration
//

import Combine
import CoreML
import CoreGraphics
import Foundation

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

    // MARK: - Published State

    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var modelStatus: String = "No model loaded"
    @Published private(set) var lastPredictedCrop: CropEngine.CropRect?

    // MARK: - Constants (must match cinematic_env.py exactly)

    private let maxPanSpeed:  Float = 0.02
    private let maxTiltSpeed: Float = 0.02
    private let maxZoomSpeed: Float = 0.05
    private let maxZoom:      Float = 4.0
    private let aspectRatio:  Float = 16.0 / 9.0

    // MARK: - Private State

    private var model: MLModel?

    /// Speaker center from the previous frame (for velocity computation)
    private var previousSpeakerCenter: CGPoint?

    /// Agent's internal crop state — updated each predict() call
    private var cropX:    Float = 0.0
    private var cropY:    Float = 0.0
    private var cropZoom: Float = 1.0

    // MARK: - Lifecycle

    init() {
        loadModel()
    }

    // MARK: - Model Loading

    private func loadModel() {
        guard let url = Bundle.main.url(
            forResource: "CinematicFraming",
            withExtension: "mlpackage"
        ) else {
            modelStatus = "Model not found in bundle"
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            model = try MLModel(contentsOf: url, configuration: config)
            isModelLoaded = true
            modelStatus = "Model loaded (Neural Engine)"
        } catch {
            modelStatus = "Failed to load: \(error.localizedDescription)"
        }
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

    /// Clear tracking state (e.g. on subject change or session end).
    func reset() {
        previousSpeakerCenter = nil
        cropX    = 0.0
        cropY    = 0.0
        cropZoom = 1.0
        lastPredictedCrop = nil
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
                return currentCrop
            }

            let dx = actionArray[0].floatValue * maxPanSpeed
            let dy = actionArray[1].floatValue * maxTiltSpeed
            let dz = actionArray[2].floatValue * maxZoomSpeed

            let newCrop = applyCropUpdate(dx: dx, dy: dy, dz: dz)
            lastPredictedCrop = newCrop
            return newCrop

        } catch {
            return currentCrop
        }
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
        // Update zoom, clamped [1, maxZoom]
        cropZoom = max(1.0, min(maxZoom, cropZoom + dz))

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
