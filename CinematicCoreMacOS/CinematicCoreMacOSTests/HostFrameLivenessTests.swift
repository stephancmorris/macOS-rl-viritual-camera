import Foundation
import Testing
@testable import Alfie

struct HostFrameLivenessTests {
    @Test func shortQueueGapsRemainLiveUntilTheOneSecondBoundary() {
        for now in [10.0, 10.02, 10.1, 10.999] {
            #expect(!HostFrameLiveness.shouldStopReceiving(isReceiving: true, lastArrival: 10, now: now))
        }
        #expect(HostFrameLiveness.shouldStopReceiving(isReceiving: true, lastArrival: 10, now: 11))
        #expect(HostFrameLiveness.shouldStopReceiving(isReceiving: true, lastArrival: 10, now: 12))
    }

    @Test func stoppedStateDoesNotRepeatedlyExpire() {
        #expect(!HostFrameLiveness.shouldStopReceiving(isReceiving: false, lastArrival: nil, now: 100))
    }

    @Test func newArrivalResumesAfterTimeout() {
        #expect(HostFrameLiveness.shouldStopReceiving(isReceiving: true, lastArrival: 10, now: 12))
        #expect(!HostFrameLiveness.shouldStopReceiving(isReceiving: true, lastArrival: 12, now: 12.02))
    }

    @Test func missingOrInvalidArrivalCannotKeepTheReceivingFlagAlive() {
        for arrival: Double? in [nil, .nan, .infinity, 20] {
            #expect(HostFrameLiveness.shouldStopReceiving(isReceiving: true, lastArrival: arrival, now: 10))
        }
    }

    @Test func delayedOldConnectionCannotAffectTheReplacement() {
        let old = UUID(), replacement = UUID()
        #expect(HostFrameLiveness.isCurrentConnection(old, active: old))
        #expect(!HostFrameLiveness.isCurrentConnection(old, active: replacement))
        #expect(HostFrameLiveness.isCurrentConnection(replacement, active: replacement))
        #expect(!HostFrameLiveness.isCurrentConnection(old, active: nil))
    }
}
