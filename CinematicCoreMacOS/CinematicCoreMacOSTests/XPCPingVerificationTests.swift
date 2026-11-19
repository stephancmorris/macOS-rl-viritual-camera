import Foundation
import Testing
@testable import Alfie

@MainActor
struct XPCPingVerificationTests {
    private final class Clock {
        var jobs: [(delay: TimeInterval, fire: @MainActor () -> Void)] = []
        func schedule(_ delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
            jobs.append((delay, fire))
        }
    }

    @Test func unansweredPingExpiresOnceAfterTheRequestedDeadline() {
        let clock = Clock()
        let gate = XPCPingVerification(schedule: clock.schedule)
        var expired: [UInt64] = []
        let attempt = gate.begin(generation: 42) { expired.append($0) }
        #expect(clock.jobs.count == 1 && clock.jobs[0].delay == 3)
        #expect(expired.isEmpty)
        clock.jobs[0].fire()
        clock.jobs[0].fire()
        #expect(expired == [42])
        #expect(!gate.acceptReply(generation: 42, attempt: attempt))
    }

    @Test func promptReplyMakesItsDeadlineInert() {
        let clock = Clock()
        let gate = XPCPingVerification(schedule: clock.schedule)
        var expired = false
        let attempt = gate.begin(generation: 1) { _ in expired = true }
        #expect(gate.acceptReply(generation: 1, attempt: attempt))
        clock.jobs[0].fire()
        #expect(!expired)
    }

    @Test func disconnectCancellationRejectsBothLateCallbacks() {
        let clock = Clock()
        let gate = XPCPingVerification(schedule: clock.schedule)
        var expired = false
        let attempt = gate.begin(generation: 1) { _ in expired = true }
        gate.cancel()
        clock.jobs[0].fire()
        #expect(!gate.acceptReply(generation: 1, attempt: attempt))
        #expect(!expired)
    }

    @Test func previousGenerationCannotExpireOrVerifyItsReplacement() {
        let clock = Clock()
        let gate = XPCPingVerification(schedule: clock.schedule)
        var expired: [UInt64] = []
        let old = gate.begin(generation: 1) { expired.append($0) }
        let current = gate.begin(generation: 2) { expired.append($0) }
        clock.jobs[0].fire()
        #expect(expired.isEmpty)
        #expect(!gate.acceptReply(generation: 1, attempt: old))
        #expect(gate.acceptReply(generation: 2, attempt: current))
        clock.jobs[1].fire()
        #expect(expired.isEmpty)
    }

    @Test func aSecondAttemptInTheSameGenerationHasItsOwnDeadline() {
        let clock = Clock()
        let gate = XPCPingVerification(schedule: clock.schedule)
        var expired: [UInt64] = []
        let old = gate.begin(generation: 1) { expired.append($0) }
        _ = gate.begin(generation: 1) { expired.append($0) }
        clock.jobs[0].fire()
        #expect(!gate.acceptReply(generation: 1, attempt: old))
        #expect(expired.isEmpty)
        clock.jobs[1].fire()
        #expect(expired == [1])
    }
}
