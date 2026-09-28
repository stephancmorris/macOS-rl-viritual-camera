import SwiftUI

struct InputTileView: View {
    let model: InputTileModel
    var size = CGSize(width: 299, height: 168)
    let onCue: (InputTileModel.Slot) -> Void

    /// Program red 3 pt, Preview green 3 pt, others 1 pt neutral (INPUT-STRIP).
    private var ring: (color: Color, width: CGFloat) {
        switch model.role {
        case .program: return (ConsoleStyle.programRed, 3)
        case .preview: return (ConsoleStyle.previewGreen, 3)
        case .none: return (Color.white.opacity(model.isAssigned ? 0.18 : 0.28), 1)
        }
    }

    var body: some View {
        Button {
            onCue(model.slot)
        } label: {
            ZStack(alignment: .bottomLeading) {
                background

                if model.isAssigned {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Cam \(model.slot.rawValue)")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer(minLength: 4)
                            if let badge = model.role.badge {
                                Text(badge)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(badgeColor, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Text(tileDetail)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text(model.health.title)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(model.healthColor)
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.7))
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Input \(model.slot.rawValue) · not assigned")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Add a camera in Setup")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(12)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            // Idle assigned tiles are slightly dimmed so PGM / PVW stand out.
            .opacity(model.isAssigned && model.role == .none ? 0.8 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(ring.color, style: StrokeStyle(lineWidth: ring.width, dash: model.isAssigned ? [] : [5, 4]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!model.isAssigned)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(model.isAssigned ? "Cue this camera for Preview. Does not Take." : "Assign a camera in Setup.")
    }

    private var background: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.11)
            if let image = model.renderedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            if case .noSignal = model.health, model.isAssigned {
                Color.black.opacity(0.55)
            }
        }
    }

    private var badgeColor: Color {
        switch model.role {
        case .program: Color(red: 1, green: 0.27, blue: 0.23)
        case .preview: Color(red: 0.19, green: 0.75, blue: 0.44)
        case .none: .clear
        }
    }

    /// Name and shot stay visible even when the source drops: the slot keeps
    /// its identity, and the amber health line says it is holding.
    private var tileDetail: String {
        [model.name, model.shot].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var accessibilityTitle: String {
        guard model.isAssigned else { return "Input \(model.slot.rawValue), not assigned" }
        let role = switch model.role {
        case .program: "Program"
        case .preview: "Preview"
        case .none: "Input"
        }
        return "\(role), Cam \(model.slot.rawValue), \(tileDetail), \(model.health.title)"
    }
}

private extension InputTileModel {
    var healthColor: Color {
        switch health {
        case .rate: .white.opacity(0.85)
        case .unsupported, .noSignal: .orange
        }
    }
}
