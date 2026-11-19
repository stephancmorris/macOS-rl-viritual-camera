import CoreGraphics
import Foundation

/// Decision core, stage 2: one frozen picture of the show at one Director
/// tick. Everything that decides or records reads this picture, so a decision
/// can be replayed from it. Values only; no camera, show or clock access.
///
/// Unknown stays unknown: a camera with no world-model row has no `people`,
/// and a row that scanned only part of the picture keeps that coverage.
/// Nothing here turns either into "nobody".
nonisolated struct DirectorScene: Sendable {
    /// From the world model. Counts and side-to-side positions for rules only;
    /// never boxes of people in logs.
    struct People: Equatable, Sendable {
        let coverage: WorldModel.Coverage
        let observedAt: TimeInterval?
        let count: Int
        /// Box centre x, 0...1, sorted left to right.
        let positions: [CGFloat]

        init(coverage: WorldModel.Coverage, observedAt: TimeInterval?, count: Int, positions: [CGFloat]) {
            self.coverage = coverage; self.observedAt = observedAt; self.count = count; self.positions = positions
        }

        /// nil when the camera has no row: not "nobody", just not known.
        init?(_ camera: WorldModel.Camera?) {
            guard let camera else { return nil }
            self.init(coverage: camera.coverage, observedAt: camera.observedAt, count: camera.people.count,
                      positions: camera.people.map(\.box.midX).sorted())
        }
    }

    struct Input: Sendable {
        let channel: ChannelID
        let running: Bool
        let sourceMissing: Bool
        let revisions: ChannelRevisions
        let sourceGeneration: UInt64
        /// The camera's current shot (`CameraManager.directorShot`).
        let shot: DirectorShot
        let format: DirectorShotPolicy.InputFormat
        /// What the evidence adapter was given this tick.
        let sample: ChannelEvidenceSample
        /// The adapter's debounced state after this tick's sample; nil without an adapter.
        let state: DirectorEvidenceAdapter.ChannelState?
        let settledFor: TimeInterval
        let people: People?
    }

    let now: TimeInterval
    let evidenceRevision: UInt64
    let program: ChannelID
    let preview: ChannelID?
    /// Preview's Take availability as the operator's Take would see it this
    /// tick; nil without a Preview or a rendered Preview frame.
    let previewTake: TakeAvailability?
    let routeGeneration: UInt64
    /// In `ChannelID` order.
    let inputs: [Input]
    /// When Program's (input, shot) pair last changed, or attach time.
    let programStartedAt: TimeInterval
    /// The newest tick Program was wide, or attach time.
    let lastWideAt: TimeInterval
    /// Program's previous shots, oldest first; at most `DirectorSceneBuilder.historyLimit`.
    let history: [DirectorShotPolicy.History]
    let segmentType: SegmentType
    let style: DirectorStyle?

    func input(_ channel: ChannelID) -> Input? { inputs.first { $0.channel == channel } }
    var programShot: DirectorShot? { input(program)?.shot }
}
