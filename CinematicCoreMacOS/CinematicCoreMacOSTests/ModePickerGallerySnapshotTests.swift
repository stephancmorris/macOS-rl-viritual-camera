#if DEBUG
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@Suite(.serialized)
@MainActor
struct ModePickerGallerySnapshotTests {
    private func store(_ mode: OperatorMode = .singleCam) -> OperatorModeStore {
        let defaults = UserDefaults(suiteName: "mode-journey-\(UUID())")!
        defaults.set(mode.rawValue, forKey: OperatorModeStore.key)
        return OperatorModeStore(defaults: defaults, multiviewEnabled: true)
    }

    @Test(arguments: OperatorMode.allCases.flatMap { mode in [0, 1, 2].map { (mode, $0) } }, [false, true])
    func modesAndCameraChoices(scenario: (OperatorMode, Int), dark: Bool) throws {
        let (mode, count) = scenario
        let choice = OperatorCameraChoice(selectedID: count > 0 ? "one" : nil,
            name: count > 0 ? "FaceTime HD Camera" : "No camera selected",
            options: count == 0 ? [] : [.init(id: "one", name: "FaceTime HD Camera"), .init(id: "two", name: "Stage camera")].prefix(count).map { $0 }, onChoose: { _ in })
        try OperatorJourneySnapshot.capture(
            OperatorModePicker(store: store(mode), cameras: .init(count: count, hasBuiltIn: count > 0), style: .stoppedScreen)
                .environment(\.operatorCameraChoice, choice),
            name: "mode-\(mode.rawValue)-\(count)", dark: dark, width: 900, height: 300)
    }

    @Test func unavailableVoiceOverIncludesCameraCount() throws {
        let cameras = OperatorModeChoice.Cameras(count: 1, hasBuiltIn: true)
        let choice = try #require(OperatorModeChoice.choices(available: OperatorMode.allCases,
            current: .singleCam, cameras: cameras).first { $0.mode == .multiCam })
        #expect(OperatorModePicker.accessibilityLabel(choice, cameras: cameras) == "Multi Cam, unavailable, one camera found")
    }

    @Test func commandsFollowDiscoveryAndWithdrawWhenAnyChannelIsLive() throws {
        let store = store()
        var stopped = true
        var cameras = OperatorModeChoice.Cameras(count: 1, hasBuiltIn: true)
        func action(_ mode: OperatorMode) -> AlfieCommandAction? {
            OperatorModePicker.command(mode, store: store, cameras: { cameras }, isStopped: { stopped })
        }
        #expect(action(.singleCam) != nil)
        #expect(action(.multiCam) == nil)
        #expect(action(.webcam) != nil)
        cameras.count = 2
        let retained = try #require(action(.multiCam))
        stopped = false
        for mode in OperatorMode.allCases { #expect(action(mode) == nil) }
        retained.perform()
        #expect(store.mode == .singleCam)
        stopped = true
        cameras.count = 1
        retained.perform()
        #expect(store.mode == .singleCam)
        cameras.count = 2
        retained.perform()
        #expect(store.mode == .multiCam)
    }

    @Test func hiddenModesHaveNoCommands() {
        let store = store()
        #expect(OperatorModePicker.command(.webcam, store: store,
            cameras: { .init(count: 2, hasBuiltIn: false) }, isStopped: { true }) == nil)
        let limited = OperatorModeStore(defaults: UserDefaults(suiteName: "mode-limited-\(UUID())")!, multiviewEnabled: false)
        #expect(OperatorModePicker.command(.multiCam, store: limited,
            cameras: { .init(count: 2, hasBuiltIn: true) }, isStopped: { true }) == nil)
    }
}
#endif
