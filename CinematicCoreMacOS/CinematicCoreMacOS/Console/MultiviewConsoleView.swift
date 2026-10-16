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
    /// Live pane pictures. nil in the gallery, which draws placeholders.
    var panePicture: ((PaneModel) -> AnyView)?
    /// Show-level controls at the right of the header (live console only).
    var headerTrailing: AnyView?
    /// Alfie's status. Nil until the live console is given a director controller.
    var director: NextShotStatus.DirectorSection?

    init(
        snapshot: ConsoleSnapshot,
        actions: any ConsoleActions,
        director: NextShotStatus.DirectorSection? = nil,
        @ViewBuilder strip: () -> Strip,
        @ViewBuilder pill: () -> Pill
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.director = director
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

                pane(.preview(from: snapshot))
                    .place(layout.previewPane)

                pane(.program(from: snapshot))
                    .place(layout.programPane)

                NextShotPanel(status: NextShotStatus.make(snapshot, availability: availability).withDirector(director))
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

    @ViewBuilder
    private func pane(_ model: PaneModel) -> some View {
        if let panePicture {
            ProgramPreviewPane(
                model: model,
                onPaneView: actions.setPaneView,
                onReconnect: actions.reconnect,
                onDoneEditing: { actions.setEditLive(false) }
            ) { panePicture(model) }
        } else {
            ProgramPreviewPane(
                model: model,
                onPaneView: actions.setPaneView,
                onReconnect: actions.reconnect,
                onDoneEditing: { actions.setEditLive(false) })
        }
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
            if let headerTrailing { headerTrailing }
        }
        // The window has a hidden title bar: the traffic lights sit over the
        // header's left end and the inspector handle over its right end.
        .padding(.leading, MultiviewLayout.headerLeadingInset)
        .padding(.trailing, MultiviewLayout.headerTrailingInset)
    }
}

extension MultiviewConsoleView where Strip == InputStripView, Pill == ConsoleSlotPlaceholder {
    /// Console with the input strip and a placeholder pill, for the gallery
    /// until PILL-TARGET binds the live pill to a channel.
    init(snapshot: ConsoleSnapshot, actions: any ConsoleActions, director: NextShotStatus.DirectorSection? = nil) {
        let badges = Set(ChannelID.allCases.filter { director?.showsAutoBadge(on: $0) == true })
        self.init(snapshot: snapshot, actions: actions, director: director) {
            InputStripView(snapshot: snapshot, actions: actions, autoBadgeChannels: badges)
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
