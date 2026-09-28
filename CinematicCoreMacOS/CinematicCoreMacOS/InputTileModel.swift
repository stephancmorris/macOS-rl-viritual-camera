import AppKit

/// Immutable presentation data. The console adapter supplies this from its
/// coalesced snapshot (at most 15 updates per second), never from capture.
struct InputTileModel: Identifiable {
    enum Slot: String, CaseIterable, Identifiable {
        case A, B, C, D

        var id: String { rawValue }
        var index: Int { Self.allCases.firstIndex(of: self)! }
    }

    enum Role {
        case program, preview, none

        var badge: String? {
            switch self {
            case .program: "PGM"
            case .preview: "PVW"
            case .none: nil
            }
        }
    }

    enum Health {
        case rate(String)
        case unsupported
        case noSignal

        var title: String {
            switch self {
            case .rate(let value): value
            case .unsupported: "Unsupported"
            case .noSignal: "No signal · holding slot"
            }
        }
    }

    let slot: Slot
    let isAssigned: Bool
    let role: Role
    let name: String
    let shot: String
    let health: Health
    /// The channel's latest rendered shot. Never pass a raw capture frame.
    let renderedImage: NSImage?

    var id: String { slot.id }

    init(slot: Slot, isAssigned: Bool, role: Role, name: String, shot: String,
         health: Health, renderedImage: NSImage?) {
        self.slot = slot
        self.isAssigned = isAssigned
        self.role = role
        self.name = name
        self.shot = shot
        self.health = health
        self.renderedImage = renderedImage
    }

    static func empty(_ slot: Slot) -> Self {
        .init(slot: slot, isAssigned: false, role: .none, name: "", shot: "", health: .noSignal, renderedImage: nil)
    }

    init(slot: ConsoleSnapshot.Slot, renderedImage: NSImage?) {
        let letter = Slot(rawValue: slot.channel.letter) ?? .A
        guard let input = slot.input else {
            self = .empty(letter)
            return
        }
        let role: Role = switch input.role {
        case .program: .program
        case .preview: .preview
        case .idle: .none
        }
        let health: Health = switch input.health {
        case .running(let rate): .rate(String(format: "%.1f", rate))
        case .unsupported: .unsupported
        case .missing, .reconnecting: .noSignal
        }
        self.init(slot: letter, isAssigned: true, role: role,
                  name: input.name, shot: input.shot, health: health,
                  renderedImage: renderedImage)
    }
}
