import Testing
@testable import Alfie

@MainActor struct DirectorAuthorityTests {
    @Test func levelsAndGate() {
        var state = DirectorAuthority()
        #expect(!state.mayPropose)
        #expect(state.apply(.enable(.suggest)).state.mayPropose)
        #expect(!state.mayPrepare)
        #expect(state.apply(.enable(.autoPrepare)).state.mayPrepare)
        #expect(state.apply(.enable(.autoDirect)).state.level == .autoPrepare)
        #expect(!state.mayTake)
        #expect(state.apply(.disable).state.level == .off)
    }

    @Test func manualWinsPendingWork() {
        var state = DirectorAuthority()
        state.apply(.enable(.autoPrepare))
        let old = state.epoch
        let result = state.apply(.manualCommand)
        #expect(result.cancellations == [.proposal, .prepare, .take])
        #expect(!state.admits(old))
        #expect(state.admits(state.epoch))
        let second = state.epoch
        state.apply(.operatorTake)
        #expect(!state.admits(second))
        state.apply(.stopShow)
        #expect(!state.admits(state.epoch))
    }

    @Test func pausePinEditLiveAndLoss() {
        var state = DirectorAuthority()
        state.apply(.enable(.autoPrepare))
        #expect(!state.apply(.pause).state.mayPrepare)
        #expect(state.apply(.resume).state.mayPrepare)
        #expect(!state.apply(.pin(.a)).state.mayPrepare)
        #expect(state.apply(.unpin).state.mayPrepare)
        #expect(!state.apply(.editLive(true)).state.mayPrepare)
        #expect(state.apply(.editLive(false)).state.mayPrepare)
        let token = state.epoch
        #expect(state.apply(.sourceLoss(.a)).cancellations.contains(.take))
        #expect(!state.admits(token))
    }

    @Test func sectionHasNoRoutingEffect() {
        var state = DirectorAuthority()
        state.apply(.enable(.autoPrepare))
        #expect(state.section(proposal: .b).proposal == .b)
        #expect(state.section().authority == .directorMayCue)
        state.apply(.pause)
        #expect(state.section(proposal: .b).proposal == nil)
        #expect(state.section().authority == .operatorOnly)
    }
}
