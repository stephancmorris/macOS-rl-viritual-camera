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
    /// Optional live picture per channel. The live console supplies one that
    /// samples the channel's rendered output; without it tiles draw
    /// `InputTileModel.renderedImage` (gallery, tests).
    var tilePicture: ((ChannelID) -> AnyView)?

    @State private var hint: String?

    init(snapshot: ConsoleSnapshot, actions: any ConsoleActions,
         renderedImages: [ChannelID: NSImage] = [:],
         tilePicture: ((ChannelID) -> AnyView)? = nil) {
        self.tiles = snapshot.slots.map { InputTileModel(slot: $0, renderedImage: renderedImages[$0.channel]) }
        self.onCue = { slot in
            guard let channel = ChannelID(rawValue: slot.rawValue) else { return }
            actions.cue(channel)
        }
        self.note = snapshot.operatorNote
        self.programSlot = InputTileModel.Slot(rawValue: snapshot.programChannel.letter)
        self.tilePicture = tilePicture
    }

    init(tiles: [InputTileModel], onCue: @escaping (InputTileModel.Slot) -> Void) {
        self.tiles = tiles
        self.onCue = onCue
    }

    static func programHint(for slot: InputTileModel.Slot) -> String {
        "Cam \(slot.rawValue) is Program · use Edit Live to change it"
    }

    /// How long the Program-tile hint stays in the label row.
    static let hintDuration: Duration = .seconds(4)

    /// A tile tap. Program shows the hint and does nothing else; any other
    /// tile cues through the console's action. Returns the hint to show, if
    /// any. Never cuts, never changes routing itself.
    func tap(_ slot: InputTileModel.Slot) -> String? {
        if slot == programSlot { return Self.programHint(for: slot) }
        onCue(slot)
        return nil
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
                        let model = tiles.first(where: { $0.slot == slot }) ?? .empty(slot)
                        InputTileView(
                            model: model,
                            size: tileSize,
                            picture: model.isAssigned ? tilePicture?(model.channel) : nil,
                            onCue: { hint = tap($0) })
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .task(id: hint) {
            guard hint != nil else { return }
            try? await Task.sleep(for: Self.hintDuration)
            if !Task.isCancelled { hint = nil }
        }
    }
}
