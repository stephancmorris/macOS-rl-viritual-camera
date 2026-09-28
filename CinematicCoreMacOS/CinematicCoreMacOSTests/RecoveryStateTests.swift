import Testing
@testable import Alfie

struct RecoveryStateTests {
    @Test func labelsFollowTheComposerWithoutChangingItsHold() {
        #expect(RecoveryState(phase: .inactive, galleryReady: false, trackingOwnsControl: false).statusLabel == "Pick subject")
        #expect(RecoveryState(phase: .acquiring, galleryReady: false, trackingOwnsControl: true).statusLabel == "Acquiring…")
        #expect(RecoveryState(phase: .tracking, galleryReady: true, trackingOwnsControl: true).statusLabel == "Locked")
        let hold = RecoveryState(phase: .hold, galleryReady: true, trackingOwnsControl: true)
        #expect(hold.statusLabel == "Recovering")
        #expect(hold.isRecovering && hold.allowsDirectSelection)
        let waiting = RecoveryState(phase: .wideWaiting, galleryReady: true, trackingOwnsControl: true)
        #expect(waiting.statusLabel == "Searching")
        #expect(waiting.action == .none)
        #expect(waiting.isRecovering && waiting.allowsDirectSelection)
    }

    @Test func resumeRequiresRetainedReadySubjectEvidence() {
        for phase: RecoveryState.Phase in [.tracking, .hold, .wideWaiting] {
            let ready = RecoveryState(phase: phase, galleryReady: true, trackingOwnsControl: false)
            #expect(ready.canResume)
            #expect(ready.statusLabel == "Resume")
            #expect(ready.action == .resume)
            let unready = RecoveryState(phase: phase, galleryReady: false, trackingOwnsControl: false)
            #expect(!unready.canResume)
            #expect(unready.statusLabel == "Pick subject")
            #expect(unready.action != .resume)
        }
        for phase: RecoveryState.Phase in [.inactive, .acquiring] {
            #expect(!RecoveryState(phase: phase, galleryReady: true, trackingOwnsControl: false).canResume)
        }
    }
}
