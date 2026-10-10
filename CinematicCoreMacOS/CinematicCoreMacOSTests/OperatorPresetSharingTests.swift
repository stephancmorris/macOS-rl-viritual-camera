import Testing
@testable import Alfie

/// B-00: Director logic is `nonisolated`, so it must be able to hash, compare
/// and store the app's shot presets without hopping to the MainActor.
nonisolated private struct PresetHolder: Hashable, Sendable {
    let preset: OperatorCommand.Preset
}

nonisolated private func ladder() -> [OperatorCommand.Preset] {
    ShotComposer.Config.ShotPreset.allCases.map { .stage($0) } +
        ShotComposer.Config.WebcamPreset.allCases.map { .webcam($0) }
}

nonisolated private func distinct(_ presets: [OperatorCommand.Preset]) -> Set<OperatorCommand.Preset> {
    Set(presets)
}

struct OperatorPresetSharingTests {
    @Test func presetsAreHashableFromNonisolatedCode() {
        let all = ladder()
        #expect(all.count == 5)
        #expect(distinct(all + all).count == 5)
        #expect(Set([PresetHolder(preset: .stage(.waistUp)), PresetHolder(preset: .stage(.waistUp))]).count == 1)
    }

    @Test func stageAndWebcamPresetsNeverCollide() {
        #expect(OperatorCommand.Preset.stage(.wide) != .webcam(.wide))
        #expect(distinct([.stage(.wide), .webcam(.wide)]).count == 2)
    }

    @Test func presetsCrossIsolationBoundaries() async {
        let fromTask = await Task.detached { ladder() }.value
        #expect(fromTask == ladder())
    }
}
