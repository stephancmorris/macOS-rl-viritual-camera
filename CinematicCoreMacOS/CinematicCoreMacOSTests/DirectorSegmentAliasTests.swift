import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorSegmentAliasTests {
    @Test func aliasesStayStableAfterManyOtherSegmentsWithoutExposingTheirIDs() {
        let aliases = DirectorSegmentAliases(), first = UUID()
        let firstToken = aliases.token(for: first)
        var outputs: Set<UUID> = [firstToken]
        for _ in 0..<1_000 {
            let id = UUID(), token = aliases.token(for: id)
            #expect(token != id && outputs.insert(token).inserted)
        }
        #expect(firstToken != first && aliases.token(for: first) == firstToken)
        #expect(outputs.count == 1_001)
    }

    @Test func independentAndRenewedSessionsCannotLinkTheSameSegmentAlias() {
        let segment = UUID(), first = DirectorSegmentAliases(), second = DirectorSegmentAliases()
        let before = first.token(for: segment)
        #expect(second.token(for: segment) != before)
        first.renew()
        #expect(first.token(for: segment) != before)
        #expect(first.token(for: segment) == first.token(for: segment))
    }
}
