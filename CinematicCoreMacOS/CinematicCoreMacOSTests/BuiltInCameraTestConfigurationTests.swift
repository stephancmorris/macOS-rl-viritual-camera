import Foundation
import Testing
@testable import Alfie

@MainActor struct BuiltInCameraTestConfigurationTests {
    private func show() -> ShowCoordinator {
        ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
    }

    @Test func explicitTestChoiceAppliesToAttachedAndFutureInputs() {
        let show = show()
        #expect(!show.isBuiltInCameraTestEnabled && !show.channelA.builtInCameraTestEnabled)
        let b = show.addChannel(.b)
        #expect(!b.builtInCameraTestEnabled)
        #expect(show.setBuiltInCameraTestEnabled(true))
        #expect(show.isBuiltInCameraTestEnabled && show.channelA.builtInCameraTestEnabled && b.builtInCameraTestEnabled)
        b.sessionStopRunningForTesting = {}
        show.removeChannel(.b)
        let replacement = show.addChannel(.b)
        replacement.sessionStopRunningForTesting = {}
        #expect(replacement !== b && replacement.builtInCameraTestEnabled)
        #expect(show.setBuiltInCameraTestEnabled(false))
        #expect(!show.isBuiltInCameraTestEnabled && !show.channelA.builtInCameraTestEnabled && !replacement.builtInCameraTestEnabled)
        #expect(b.builtInCameraTestEnabled) // Retired inputs are no longer configured.
    }

    @Test(arguments: ["aRunning", "bRunning", "aStarting", "bStarting"])
    func changingTestChoiceRefusesWhileAnyInputIsLive(_ state: String) {
        let show = show()
        let inputB = show.addChannel(.b)
        for enabled in [false, true] {
            show.channelA.setRunningForTesting(false)
            show.channelA.setStartingForTesting(false)
            inputB.setRunningForTesting(false)
            inputB.setStartingForTesting(false)
            #expect(show.setBuiltInCameraTestEnabled(enabled))
            switch state {
            case "aRunning": show.channelA.setRunningForTesting(true)
            case "bRunning": inputB.setRunningForTesting(true)
            case "aStarting": show.channelA.setStartingForTesting(true)
            case "bStarting": inputB.setStartingForTesting(true)
            default: Issue.record("Unknown fixture")
            }
            #expect(!show.setBuiltInCameraTestEnabled(!enabled))
            #expect(show.isBuiltInCameraTestEnabled == enabled)
            #expect(show.channelA.builtInCameraTestEnabled == enabled && inputB.builtInCameraTestEnabled == enabled)
        }
    }

    @Test func choiceSurvivesNewShowButDoesNotBecomeANewLaunchDefault() {
        let show = show()
        show.channelA.sessionStopRunningForTesting = {}
        #expect(show.setBuiltInCameraTestEnabled(true))
        show.prepareForNewShow()
        #expect(show.isBuiltInCameraTestEnabled && show.channelA.builtInCameraTestEnabled)
        let fresh = self.show()
        #expect(!fresh.isBuiltInCameraTestEnabled && !fresh.channelA.builtInCameraTestEnabled)
    }
}
