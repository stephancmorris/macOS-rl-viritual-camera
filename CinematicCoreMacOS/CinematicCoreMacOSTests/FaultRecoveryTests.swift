import Testing
@testable import Alfie

struct FaultRecoveryTests {
    nonisolated struct Example: Sendable {
        let error: CameraError
        let title: String
        let actions: [FaultRecovery.Action]
    }

    nonisolated static let examples: [Example] = [
        .init(error: .noCameraAvailable, title: "No camera found",
              actions: [.reconnect, .chooseAnotherCamera, .dismiss]),
        .init(error: .sessionConfigurationFailed, title: "Camera could not start",
              actions: [.reconnect, .chooseAnotherCamera, .dismiss]),
        .init(error: .unsupportedFormat, title: "Camera format unavailable",
              actions: [.chooseAnotherCamera, .dismiss]),
        .init(error: .authorizationDenied, title: "Camera access is off",
              actions: [.openCameraPrivacySettings, .dismiss]),
        .init(error: .noValidationClipSelected, title: "Choose a validation clip",
              actions: [.chooseValidationClip, .dismiss]),
        .init(error: .invalidValidationClip, title: "Clip could not be read",
              actions: [.chooseValidationClip, .dismiss]),
        .init(error: .validationClipPlaybackFailed("Internal decoder detail"), title: "Clip playback stopped",
              actions: [.chooseValidationClip, .dismiss]),
        .init(error: .deviceInUse(.b), title: "Camera already assigned",
              actions: [.chooseAnotherCamera, .dismiss]),
        .init(error: .deviceMissing, title: "Camera disconnected",
              actions: [.reconnect, .chooseAnotherCamera, .dismiss]),
        .init(error: .noDeviceSelected, title: "Choose a camera",
              actions: [.chooseAnotherCamera, .dismiss]),
    ]

    @Test(arguments: examples, [true, false])
    func everyFaultOffersItsFixInTheAppropriatePresentation(example: Example, isLive: Bool) {
        let recovery = FaultRecovery.evaluate(example.error, isSessionLive: isLive)

        #expect(recovery.title == example.title)
        #expect(!recovery.explanation.isEmpty)
        #expect(recovery.actions == example.actions)
        #expect(recovery.actions.first != .dismiss)
        #expect(recovery.presentation == (isLive ? .banner : .alert))
    }

    @Test(arguments: ChannelID.allCases)
    func assignedCameraNamesItsCurrentChannel(owner: ChannelID) {
        let recovery = FaultRecovery.evaluate(.deviceInUse(owner), isSessionLive: true)
        #expect(recovery.explanation.contains(owner.cameraLabel))
        #expect(recovery.actions == [.chooseAnotherCamera, .dismiss])
    }

    @Test func decoderDetailsDoNotBecomeOperatorCopy() {
        let recovery = FaultRecovery.evaluate(
            .validationClipPlaybackFailed("/private/clip.mov: internal decoder detail"),
            isSessionLive: true)
        #expect(!recovery.explanation.contains("/private/"))
        #expect(!recovery.explanation.contains("decoder"))
        #expect(recovery.actions.first == .chooseValidationClip)
    }

    @Test func pureMappingCanRunAwayFromMainActor() async {
        let recovery = await Task.detached {
            FaultRecovery.evaluate(.deviceMissing, isSessionLive: true)
        }.value
        #expect(recovery.presentation == .banner)
        #expect(recovery.actions.first == .reconnect)
    }
}
