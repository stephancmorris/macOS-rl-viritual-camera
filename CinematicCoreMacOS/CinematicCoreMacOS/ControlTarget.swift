import SwiftUI

/// Display target for the operator controls. The command binding lives in
/// ShowCoordinator (CHANNEL-CMD) and PillCommandSink; this only names the
/// target for the chip, the border and VoiceOver.
enum ControlTarget: Equatable {
    case singleCamera
    case preview(channel: ChannelID)
    case editingLive(channel: ChannelID)

    var camera: String? {
        switch self {
        case .singleCamera: nil
        case .preview(let channel), .editingLive(let channel): channel.letter
        }
    }

    var channel: ChannelID? {
        switch self {
        case .singleCamera: nil
        case .preview(let channel), .editingLive(let channel): channel
        }
    }

    var chipTitle: String? {
        switch self {
        case .singleCamera: nil
        case .preview(let channel): "CAM \(channel.letter) · PREVIEW"
        case .editingLive(let channel): "CAM \(channel.letter) · EDITING LIVE"
        }
    }

    var compactChipTitle: String? {
        switch self {
        case .singleCamera: nil
        case .preview(let channel): "\(channel.letter) · PVW"
        case .editingLive(let channel): "\(channel.letter) · LIVE"
        }
    }

    var isEditingLive: Bool {
        if case .editingLive = self { true } else { false }
    }

    /// "Cam B, Preview" / "Cam A, Editing live"; nil for the single camera,
    /// whose control labels stay exactly as they were.
    var accessibilityContext: String? {
        switch self {
        case .singleCamera: nil
        case .preview(let channel): "Cam \(channel.letter), Preview"
        case .editingLive(let channel): "Cam \(channel.letter), Editing live"
        }
    }

    /// A control's VoiceOver label with the target appended, so every control
    /// announces which camera it acts on ("Push in, Cam B, Preview").
    func accessibleLabel(_ control: String) -> String {
        accessibilityContext.map { "\(control), \($0)" } ?? control
    }
}

extension View {
    /// Announce the control with its target in a show; leave the single
    /// camera's labels untouched.
    @ViewBuilder
    func targetLabel(_ target: ControlTarget, _ control: String) -> some View {
        if target.accessibilityContext != nil {
            accessibilityLabel(target.accessibleLabel(control))
        } else {
            self
        }
    }
}
