/// Display target for the operator controls. CHANNEL-CMD supplies command
/// binding; this does not change OperatorCommand.Target.
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
}
