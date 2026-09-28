import SwiftUI

struct InputStripView: View {
    /// The snapshot adapter provides these four fixed slots at <=15 Hz.
    let tiles: [InputTileModel]
    let onCue: (InputTileModel.Slot) -> Void
    /// Latest operator/system note, right side of the label row.
    var note: String?
    /// Slot currently on Program. Tapping it shows the Edit Live hint instead
    /// of cueing; tiles never cut.
    var programSlot: InputTileModel.Slot?

    @State private var hint: String?

    init(snapshot: ConsoleSnapshot, actions: any ConsoleActions,
         renderedImages: [ChannelID: NSImage] = [:]) {
        self.tiles = snapshot.slots.map { InputTileModel(slot: $0, renderedImage: renderedImages[$0.channel]) }
        self.onCue = { slot in
            guard let channel = ChannelID(rawValue: slot.rawValue) else { return }
            actions.cue(channel)
        }
        self.note = snapshot.operatorNote
        self.programSlot = InputTileModel.Slot(rawValue: snapshot.programChannel.letter)
    }

    init(tiles: [InputTileModel], onCue: @escaping (InputTileModel.Slot) -> Void) {
        self.tiles = tiles
        self.onCue = onCue
    }

    static func programHint(for slot: InputTileModel.Slot) -> String {
        "Cam \(slot.rawValue) is Program · use Edit Live to change it"
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let tileWidth = (width - MultiviewLayout.tileGap * 3) / 4
            let tileSize = CGSize(width: tileWidth, height: (tileWidth * 9 / 16).rounded())
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("INPUTS · \(tiles.filter(\.isAssigned).count) OF 4")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer(minLength: 12)
                    if let text = hint ?? note {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(hint == nil ? 0.45 : 0.8))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(height: MultiviewLayout.stripLabelHeight, alignment: .top)
                HStack(spacing: MultiviewLayout.tileGap) {
                    ForEach(InputTileModel.Slot.allCases) { slot in
                        InputTileView(
                            model: tiles.first(where: { $0.slot == slot }) ?? .empty(slot),
                            size: tileSize,
                            onCue: tapped)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private func tapped(_ slot: InputTileModel.Slot) {
        if slot == programSlot {
            hint = Self.programHint(for: slot)
        } else {
            hint = nil
            onCue(slot)
        }
    }
}
