import AppKit
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct PillTargetTests {
    @Test func targetStatesFitTheMultiviewWidth() {
        let manager = CameraManager()
        manager.shotComposer.config.cinematicFormat = .stage
        for target in [ControlTarget.preview(channel: .b), .editingLive(channel: .a)] {
            let view = NSHostingView(rootView: OperatorPill(cameraManager: manager, controlTarget: target))
            #expect(view.fittingSize.width <= 1232, "Target pill width \(view.fittingSize.width)")
        }
    }
}
