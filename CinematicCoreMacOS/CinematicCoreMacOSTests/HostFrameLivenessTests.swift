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
        var epochs = HostConnectionEpochs()
        let old = epochs.reserve()
        let oldActivated = epochs.activate(old)
        #expect(oldActivated)
        let replacement = epochs.reserve()
        let replacementActivated = epochs.activate(replacement)
        #expect(replacementActivated)
        let oldReactivated = epochs.activate(old)
        #expect(!oldReactivated)
        #expect(!epochs.isCurrent(old))
        #expect(epochs.isCurrent(replacement))
    }

    @Test func reservingAnUnverifiedConnectionCannotStopTheCurrentHost() {
        var epochs = HostConnectionEpochs()
        let authenticated = epochs.reserve()
        let activated = epochs.activate(authenticated)
        #expect(activated)
        let unverified = epochs.reserve()
        // Listener acceptance and its later invalidation have no authority
        // over the active host until a signed service request is delivered.
        #expect(epochs.active == authenticated)
        #expect(!epochs.isCurrent(unverified))
        let stillActive = epochs.activate(authenticated)
        #expect(stillActive)
        #expect(epochs.active == authenticated)
    }
}
