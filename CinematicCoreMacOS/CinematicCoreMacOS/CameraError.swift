//
//  CameraError.swift
//  CinematicCoreMacOS
//

import Foundation

enum CameraError: LocalizedError {
    case noCameraAvailable
    case sessionConfigurationFailed
    case unsupportedFormat
    case authorizationDenied
    case noValidationClipSelected
    case invalidValidationClip
    case validationClipPlaybackFailed(String)
    /// The selected camera belongs to another channel.
    case deviceInUse(ChannelID)
    /// The selected camera is not connected. Alfie does not substitute another.
    case deviceMissing
    /// No camera chosen for a channel that may not auto-select one.
    case noDeviceSelected

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return "No camera device found"
        case .sessionConfigurationFailed:
            return "Failed to configure capture session"
        case .unsupportedFormat:
            return "Camera has no capture format compatible with the selected show frame rate"
        case .authorizationDenied:
            return "Camera access denied"
        case .noValidationClipSelected:
            return "Choose a validation clip before starting clip playback"
        case .invalidValidationClip:
            return "The selected validation clip does not contain a readable video track"
        case .validationClipPlaybackFailed(let message):
            return "Validation clip playback failed: \(message)"
        case .deviceInUse(let owner):
            return "This camera is already used by \(owner.cameraLabel)"
        case .deviceMissing:
            return "The selected camera is not connected. Reconnect it or choose another camera."
        case .noDeviceSelected:
            return "Choose a camera for this input"
        }
    }
}
