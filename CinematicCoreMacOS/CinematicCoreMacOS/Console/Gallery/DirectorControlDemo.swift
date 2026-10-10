//
//  DirectorControlDemo.swift
//  CinematicCoreMacOS
//
//  C-02 gallery. One live control, plus the states operators see.
//  Shortcut Command Shift H is on the live control only.
//

#if DEBUG
import SwiftUI

struct DirectorControlDemo: View {
    @StateObject private var live = FakeDirectorConsole()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shortcut \(DirectorHandShortcut.title) hands control to Alfie, or takes over. Esc is reserved for the next-cut notice.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            DirectorModeControl(controller: live)
            ForEach(DirectorControlGallery.cards) { card in
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title.uppercased())
                        .font(ConsoleStyle.label(11))
                        .foregroundStyle(.white.opacity(0.55))
                    DirectorModeControl(controller: card.controller, ownsShortcut: false, refusal: card.refusal)
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }
}

struct DirectorControlCard: Identifiable {
    nonisolated var id: String
    var title: String
    var controller: FakeDirectorConsole
    /// A refusal the card shows as if the controller had just returned it.
    var refusal: String? = nil
}

enum DirectorControlGallery {
    /// Stable ids for tests. The cards themselves are main-actor values.
    nonisolated static let cardIDs = [
        "launch-manual", "qualified-still-manual", "assist-handed", "refused", "takeover",
    ]

    static let cards: [DirectorControlCard] = [
        DirectorControlCard(
            id: "launch-manual",
            title: "Launch · Manual",
            controller: FakeDirectorConsole(section: .atLaunch(qualified: .none))),
        DirectorControlCard(
            id: "qualified-still-manual",
            title: "Qualified rig · still Manual",
            controller: FakeDirectorConsole(
                section: .atLaunch(qualified: .init(assist: true, auto: true, backup: true)))),
        DirectorControlCard(
            id: "assist-handed",
            title: "Assist · Hand to Alfie",
            controller: FakeDirectorConsole(section: NextShotStatus.DirectorSection(
                level: .assist,
                activity: .active(.watching),
                prepared: nil,
                nextCut: nil,
                alfieSetShot: [],
                qualified: .init(assist: true, auto: false, backup: false),
                handedToAlfie: true,
                runSheet: nil))),
        DirectorControlCard(
            id: "refused",
            title: "Auto · not qualified",
            controller: FakeDirectorConsole(
                section: .atLaunch(qualified: .init(assist: true, auto: false, backup: false))),
            refusal: "Auto, not qualified"),
        DirectorControlCard(
            id: "takeover",
            title: "Paused · you took over",
            controller: FakeDirectorConsole(section: NextShotStatus.DirectorSection(
                level: .assist,
                activity: .paused(.operatorTookOver),
                prepared: nil,
                nextCut: nil,
                alfieSetShot: [],
                qualified: .init(assist: true, auto: true, backup: false),
                handedToAlfie: false,
                runSheet: nil))),
    ]
}
#endif
