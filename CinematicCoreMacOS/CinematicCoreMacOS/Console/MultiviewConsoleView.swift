//
//  MultiviewConsoleView.swift
//  CinematicCoreMacOS
//
//  The Multiview console frame (Option 3): Preview pane left, Program pane
//  right, next-shot panel under Preview, Take bar under Program, the input
//  row, and the operator pill. View layer only — it reads one ConsoleSnapshot
//  and sends ConsoleActions; the input row and pill are slots filled by the
//  INPUT-STRIP and PILL-TARGET cards.
//
//  Not wired into ContentView yet: live pane pictures need ROUTER.
//

import SwiftUI

struct MultiviewConsoleView<Strip: View, Pill: View>: View {
    let snapshot: ConsoleSnapshot
    let actions: any ConsoleActions
    /// Fills the input row: label row (y498) plus the tile grid (y518).
    let strip: Strip
    /// Bottom-centred, 12 pt from the window bottom.
    let pill: Pill

    init(
        snapshot: ConsoleSnapshot,
        actions: any ConsoleActions,
        @ViewBuilder strip: () -> Strip,
        @ViewBuilder pill: () -> Pill
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.strip = strip()
        self.pill = pill()
    }

    var body: some View {
        GeometryReader { geo in
            let layout = MultiviewLayout(size: geo.size)
            let availability = TakeAvailability.evaluate(snapshot)
            ZStack(alignment: .topLeading) {
                ConsoleStyle.background

                header
                    .place(layout.header)

                ProgramPreviewPane(
                    model: .preview(from: snapshot),
                    onPaneView: actions.setPaneView,
                    onReconnect: actions.reconnect)
                    .place(layout.previewPane)

                ProgramPreviewPane(
                    model: .program(from: snapshot),
                    onPaneView: actions.setPaneView,
                    onReconnect: actions.reconnect,
                    onDoneEditing: { actions.setEditLive(false) })
                    .place(layout.programPane)

                NextShotPanel(status: .make(snapshot, availability: availability))
                    .place(layout.nextPanel)

                TakeBarView(
                    availability: availability,
                    onTake: actions.take,
                    onSetEditLive: actions.setEditLive)
                    .place(layout.takeBar)

                strip
                    .place(layout.stripLabel.union(layout.strip))

                pill
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, MultiviewLayout.pillBottomInset)
            }
        }
        .frame(minWidth: MultiviewLayout.minimumSize.width, minHeight: MultiviewLayout.minimumSize.height)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("ALFIE")
                .font(.system(size: 15, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(.white)
            Text("MULTIVIEW · \(snapshot.showStandard.title)")
                .font(ConsoleStyle.label(11))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
        .padding(.horizontal, MultiviewLayout.sideInset)
    }
}

extension MultiviewConsoleView where Strip == InputStripView, Pill == ConsoleSlotPlaceholder {
    /// Console with the input strip and a placeholder pill, for the gallery
    /// until PILL-TARGET binds the live pill to a channel.
    init(snapshot: ConsoleSnapshot, actions: any ConsoleActions) {
        self.init(snapshot: snapshot, actions: actions) {
            InputStripView(snapshot: snapshot, actions: actions)
        } pill: {
            ConsoleSlotPlaceholder(title: "OPERATOR PILL · PILL-TARGET", width: 720, height: 46)
        }
    }
}

/// Dashed stand-in for a console slot owned by another card.
struct ConsoleSlotPlaceholder: View {
    let title: String
    var width: CGFloat?
    var height: CGFloat?

    var body: some View {
        Text(title)
            .font(ConsoleStyle.label(11))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: width ?? .infinity, maxHeight: height ?? .infinity)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
    }
}

private extension View {
    /// Pins a view to an absolute rect inside a top-leading ZStack.
    func place(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}
