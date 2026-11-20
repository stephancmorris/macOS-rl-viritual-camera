//
//  ShotMoveLadder.swift
//  CinematicCoreMacOS
//
//  G-01 stage 3. Owns the shot-move state that used to be private stored
//  properties of CameraManager: the move in progress, and the Director owner
//  of a slow Director move with its liveness check. The camera's published
//  `zoomMoveDirection` keeps a private setter; this type reports direction
//  changes through `directionDidChange`, which CameraManager installs.
//

import CoreGraphics
import Foundation

@MainActor
final class ShotMoveLadder {
    /// One shot move: a single step along the ladder, with the heights the
    /// crop moves between.
    struct Move {
        var origin: OperatorCommand.Preset
        var destination: OperatorCommand.Preset
        var originHeight: CGFloat
        var destinationHeight: CGFloat
        var direction: OperatorCommand.ZoomDirection
        var originIsUncropped = false
        var destinationIsUncropped = false
        var commandOrigin: OperatorCommand.Origin = .operatorUI

        /// The same step run backwards, as an operator move.
        func reversed(direction: OperatorCommand.ZoomDirection) -> Move {
            Move(origin: destination, destination: origin,
                 originHeight: destinationHeight, destinationHeight: originHeight,
                 direction: direction, originIsUncropped: destinationIsUncropped,
                 destinationIsUncropped: originIsUncropped)
        }
    }

    /// The move in progress, if any.
    private(set) var current: Move?
    private var directorMoveID: UUID?
    private var directorMoveIsCurrent: (() -> Bool)?
    /// Installed by the camera to publish `zoomMoveDirection`.
    var directionDidChange: ((OperatorCommand.ZoomDirection?) -> Void)?

    var isDirectorMove: Bool { current?.commandOrigin == .director }

    /// Start an operator move. Any Director owner is dropped.
    func begin(_ move: Move) {
        dropDirectorOwner()
        current = move
        directionDidChange?(move.direction)
    }

    /// Start a slow Director move owned by `id` while `isCurrent` holds.
    func beginDirector(_ move: Move, id: UUID, isCurrent: @escaping () -> Bool) {
        current = move
        directorMoveID = id
        directorMoveIsCurrent = isCurrent
        directionDidChange?(move.direction)
    }

    /// Hold an interrupted Director move's geometry as the operator's, for
    /// the reversal that follows in the same turn. Publishes nothing: the
    /// operator move that follows does.
    func adoptAsOperatorMove(_ move: Move) {
        var move = move
        move.commandOrigin = .operatorUI
        current = move
    }

    /// End the move and drop any Director owner.
    func clear() {
        dropDirectorOwner()
        endMove()
    }

    /// End the move. A Director owner, if any, is left as it was; with no
    /// Director move in progress it no longer owns anything.
    func endMove() {
        current = nil
        directionDidChange?(nil)
    }

    /// Forget the Director owner without ending the move.
    func dropDirectorOwner() {
        directorMoveID = nil
        directorMoveIsCurrent = nil
    }

    /// True while `id` owns the Director move in progress.
    func hasDirectorMove(id: UUID) -> Bool {
        directorMoveID == id && isDirectorMove
    }

    /// The owner of a Director move in progress that has lost its liveness.
    func staleDirectorMove() -> UUID? {
        guard let id = directorMoveID, isDirectorMove, directorMoveIsCurrent?() != true else { return nil }
        return id
    }

    /// The owner of a Director move in progress, if any.
    var directorOwner: UUID? { isDirectorMove ? directorMoveID : nil }

    /// The shot ladder for a format: wide to tight.
    static func ladder(for format: ShotComposer.Config.CinematicFormat) -> [OperatorCommand.Preset] {
        format == .webcam ? [.webcam(.wide), .webcam(.tight)] :
            [.stage(.wide), .stage(.fullBody), .stage(.waistUp)]
    }

    /// The crop height a preset holds outside tracking.
    static func fixedHeight(for preset: OperatorCommand.Preset) -> CGFloat {
        switch preset {
        case .stage(.wide), .webcam(.wide): return 1
        case .stage(.fullBody): return 0.8
        case .stage(.waistUp), .webcam(.tight): return 0.5
        }
    }
}
