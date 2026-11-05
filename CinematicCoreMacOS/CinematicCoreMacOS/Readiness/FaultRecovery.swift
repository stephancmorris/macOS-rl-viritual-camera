//
//  FaultRecovery.swift
//  CinematicCoreMacOS
//
//  Operator-facing recovery for capture faults. Views choose their placement;
//  a live session must keep recovery on its pane or banner, without an alert.
//

nonisolated struct FaultRecovery: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case reconnect
        case chooseAnotherCamera
        case openCameraPrivacySettings
        case chooseValidationClip
        case dismiss
    }

    enum Presentation: Equatable, Sendable {
        case banner
        case alert
    }

    let title: String
    let explanation: String
    /// In priority order, with the immediate fix first.
    let actions: [Action]
    let presentation: Presentation

    /// This switch deliberately has no default: every new CameraError needs
    /// an explanation and a way forward before it can reach an operator.
    static func evaluate(_ error: CameraError, isSessionLive: Bool) -> Self {
        let title: String
        let explanation: String
        let actions: [Action]

        switch error {
        case .noCameraAvailable:
            title = "No camera found"
            explanation = "Connect a camera, then reconnect it in Alfie."
            actions = [.reconnect, .chooseAnotherCamera, .dismiss]
        case .sessionConfigurationFailed:
            title = "Camera could not start"
            explanation = "Reconnect this camera or choose another one."
            actions = [.reconnect, .chooseAnotherCamera, .dismiss]
        case .unsupportedFormat:
            title = "Camera format unavailable"
            explanation = "Choose a camera that supports the show's frame rate."
            actions = [.chooseAnotherCamera, .dismiss]
        case .authorizationDenied:
            title = "Camera access is off"
            explanation = "Allow Alfie to use cameras in System Settings."
            actions = [.openCameraPrivacySettings, .dismiss]
        case .noValidationClipSelected:
            title = "Choose a validation clip"
            explanation = "Select a video file before starting playback."
            actions = [.chooseValidationClip, .dismiss]
        case .invalidValidationClip:
            title = "Clip could not be read"
            explanation = "Choose a video file with a readable video track."
            actions = [.chooseValidationClip, .dismiss]
        case .validationClipPlaybackFailed:
            title = "Clip playback stopped"
            explanation = "Choose the clip again or select another video file."
            actions = [.chooseValidationClip, .dismiss]
        case .deviceInUse(let owner):
            title = "Camera already assigned"
            explanation = "This camera belongs to \(owner.cameraLabel). Choose another camera."
            actions = [.chooseAnotherCamera, .dismiss]
        case .deviceMissing:
            title = "Camera disconnected"
            explanation = "Reconnect this camera or choose another one."
            actions = [.reconnect, .chooseAnotherCamera, .dismiss]
        case .noDeviceSelected:
            title = "Choose a camera"
            explanation = "Select a camera for this input."
            actions = [.chooseAnotherCamera, .dismiss]
        }

        return Self(title: title, explanation: explanation, actions: actions,
                    presentation: isSessionLive ? .banner : .alert)
    }
}
