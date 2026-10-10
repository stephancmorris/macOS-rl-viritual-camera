import SwiftUI

struct InputTileView: View {
    let model: InputTileModel
    var size = CGSize(width: 299, height: 168)
    /// Live picture for this tile's channel (the console supplies one that
    /// samples the channel's rendered output). nil falls back to
    /// `model.renderedImage`, which the gallery and tests use.
    var picture: AnyView?
    let onCue: (InputTileModel.Slot) -> Void
    /// "AUTO" when Alfie set this input's current shot. Nil leaves the reserved slot empty.
    var directorBadge: String? = nil

    /// Width kept clear at the top right for the director badge.
    static let directorBadgeReserve: CGFloat = 64

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
            ZStack {
                background

                if model.isAssigned {
                    VStack(spacing: 0) {
                        header
                        Spacer(minLength: 0)
                        footer
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Input \(model.slot.rawValue) · not assigned")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Add a camera in Setup")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(model.accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    /// "Cam A" and the role badge, top left. The top right is the AUTO slot.
    private var header: some View {
        HStack(spacing: 6) {
            Text("Cam \(model.slot.rawValue)")
                .font(.system(size: 13, weight: .semibold))
            if let badge = model.role.badge {
                Text(badge)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(badgeColor, in: RoundedRectangle(cornerRadius: 4))
            }
            Spacer(minLength: 4)
            directorBadgeSlot
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 2)
        .padding(10)
    }

    /// Name · shot bottom left, delivered rate or health bottom right. The
    /// name and shot stay visible when the source drops; the amber health
    /// line says the slot is holding.
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(tileDetail)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(model.health.title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(model.healthColor)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.7))
    }

    private var background: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.11)
            if let picture {
                picture
            } else if let image = model.renderedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            if case .noSignal = model.health, model.isAssigned {
                Color.black.opacity(0.55)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// Occupies the reserved top-right slot. Empty unless Alfie set this shot.
    private var directorBadgeSlot: some View {
        Group {
            if let directorBadge {
                Text(directorBadge)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(ConsoleStyle.previewGreen, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: Self.directorBadgeReserve, alignment: .trailing)
    }

    private var accessibilityLabel: String {
        guard let directorBadge else { return model.accessibilityLabel }
        return model.accessibilityLabel + ". \(directorBadge), Alfie set this shot"
    }

    private var badgeColor: Color {
        switch model.role {
        case .program: ConsoleStyle.programRed
        case .preview: ConsoleStyle.previewGreen
        case .none: .clear
        }
    }

    private var tileDetail: String {
        [model.name, model.shot].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private extension InputTileModel {
    var healthColor: Color {
        switch health {
        case .rate: .white.opacity(0.85)
        case .unsupported, .noSignal: ConsoleStyle.amber
        }
    }
}
