//
//  CameraManager+ShotMoves.swift
//  CinematicCoreMacOS
//
//  G-01 stage 3. Shot presets and operator zoom moves: the camera side. The
//  move in progress and its Director owner live privately in
//  `ShotMoveLadder`. The slow Director admission and the per-frame ladder
//  step stay in CameraManager.swift, next to the revision and crop state
//  they write.
//

import CoreGraphics
import Foundation

extension CameraManager {
    var isZoomLimited: Bool {
        activeMode != .wide && (cropEngine?.isZoomLimited == true ||
            (activeMode == .autoTracking && cropEngine?.hasZoomAdjustment != true && shotComposer.isZoomLimitedByQuality))
    }
    var framingTitle: String {
        shotComposer.config.activeFramingTitle + (cropEngine?.hasZoomAdjustment == true ? " · Adjusted" : "")
    }
    var selectedShot: OperatorCommand.Preset {
        shotComposer.config.cinematicFormat == .webcam ? .webcam(shotComposer.config.webcamPreset) : .stage(shotComposer.config.shotPreset)
    }
    var directorShot: DirectorShot { .init(preset: selectedShot) }

    var shotLadder: [OperatorCommand.Preset] {
        ShotMoveLadder.ladder(for: shotComposer.config.cinematicFormat)
    }
    func canBeginZoom(_ direction: OperatorCommand.ZoomDirection) -> Bool {
        if let move = shotMoves.current { return direction != move.direction }
        if activeMode == .wide { return direction == .pushIn }
        guard let index = shotLadder.firstIndex(of: selectedShot) else { return false }
        return direction == .pushIn ? index < shotLadder.count - 1 : index > 0
    }
    func selectPreset(_ preset: OperatorCommand.Preset) {
        cancelOperatorMotion()
        cropEngine?.clearZoomAdjustment()
        choosePreset(preset)
        boostFramingTransition()
    }

    /// A tap owns exactly one destination, not an unbounded held velocity.
    func beginZoom(_ direction: OperatorCommand.ZoomDirection) {
        guard canBeginZoom(direction), let engine = cropEngine else { return }
        shotMoves.dropDirectorOwner()
        let visible = lastGoodProgramCrop ?? engine.currentCrop
        let move: ShotMoveLadder.Move
        if let prior = shotMoves.current {
            move = prior.reversed(direction: direction)
        } else {
            let origin = selectedShot
            let ladder = shotLadder
            let index = ladder.firstIndex(of: origin) ?? 0
            let next = min(ladder.count - 1, max(0, index + (direction == .pushIn ? 1 : -1)))
            let destination = ladder[next]
            let height = activeMode == .autoTracking
                ? shotComposer.destinationHeight(for: destination) : ShotMoveLadder.fixedHeight(for: destination)
            // No known subject geometry: retain the shot rather than inventing a tracked crop.
            guard let height else { return }
            let originHeight = activeMode == .wide ? widestSafeCrop().size.height :
                (activeMode == .autoTracking ? shotComposer.destinationHeight(for: origin) : ShotMoveLadder.fixedHeight(for: origin))
            move = .init(origin: origin, destination: destination,
                         originHeight: originHeight ?? visible.size.height, destinationHeight: height,
                         direction: direction, originIsUncropped: activeMode == .wide)
        }
        if activeMode == .wide {
            setOperationMode(.manualCrop)
        }
        if activeMode == .manualCrop { manualCropPoint = visible.center }
        shotMoves.begin(move)
        engine.beginZoom(direction, to: move.destinationHeight, visibleCrop: visible)
        refreshMotionInputs()
    }

    /// Never cancels an operator move that superseded this Director owner.
    func cancelDirectorShotMove(id: UUID) {
        guard shotMoves.hasDirectorMove(id: id) else { return }
        cropEngine?.endZoom()
        shotMoves.clear()
    }

    func hasDirectorShotMove(id: UUID) -> Bool {
        shotMoves.hasDirectorMove(id: id)
    }
}
