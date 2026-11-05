import Testing
@testable import Alfie

@MainActor
struct AlfieCommandResolutionTests {
    private final class Calls {
        var focused = 0
        var fallback = 0
        var detect = 0
    }

    @Test func liveAppStopResolvesWithoutAnyFocusedPublisher() {
        let calls = Calls()
        let fallback = AlfieCommandAction(perform: { calls.fallback += 1 })
        let resolved = AlfieCommandActions.resolve(focused: [:], fallbackStop: fallback)
        #expect(calls.fallback == 0)
        resolved[.stopSession]?.perform()
        #expect(calls.fallback == 1)
    }

    @Test func stoppedAppWithoutPublishersHasNoStopAction() {
        let resolved = AlfieCommandActions.resolve(focused: [:], fallbackStop: nil)
        #expect(resolved[.stopSession] == nil)
        #expect(resolved.actions.isEmpty)
    }

    @Test func focusedStopTakesPrecedenceOverTheAppFallback() {
        let calls = Calls()
        let focused: [AlfieCommandCatalog.ID: AlfieCommandAction] = [
            .stopSession: AlfieCommandAction(perform: { calls.focused += 1 })
        ]
        let resolved = AlfieCommandActions.resolve(focused: focused,
            fallbackStop: AlfieCommandAction(perform: { calls.fallback += 1 }))
        #expect(calls.focused == 0)
        #expect(calls.fallback == 0)
        resolved[.stopSession]?.perform()
        #expect(calls.focused == 1)
        #expect(calls.fallback == 0)
    }

    @Test func fallbackAddsOnlyStopAndPreservesEveryFocusedEntry() {
        let calls = Calls()
        let focused: [AlfieCommandCatalog.ID: AlfieCommandAction] = [
            .detect: AlfieCommandAction(perform: { calls.detect += 1 })
        ]
        let resolved = AlfieCommandActions.resolve(focused: focused,
            fallbackStop: AlfieCommandAction(perform: { calls.fallback += 1 }))
        #expect(Set(resolved.actions.keys) == [.detect, .stopSession])
        for id in AlfieCommandCatalog.ID.allCases where id != .detect && id != .stopSession {
            #expect(resolved[id] == nil)
        }
        #expect(focused[.stopSession] == nil)
        resolved[.detect]?.perform()
        #expect(calls.detect == 1)
        #expect(calls.fallback == 0)
    }

    @Test func resolutionCanRunOffMainActorWithoutRunningActions() async {
        let calls = Calls()
        let fallback = AlfieCommandAction(perform: { calls.fallback += 1 })
        let resolved = await Task.detached {
            AlfieCommandActions.resolve(focused: [:], fallbackStop: fallback)
        }.value
        #expect(resolved[.stopSession] != nil)
        #expect(calls.fallback == 0)
    }
}
