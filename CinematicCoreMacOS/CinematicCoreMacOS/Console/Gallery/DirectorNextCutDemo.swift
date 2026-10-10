//
//  DirectorNextCutDemo.swift
//  CinematicCoreMacOS
//
//  C-06 gallery. Auto names the countdown. Backup names the next cut and
//  leaves the duration off. The 2 second value is a fixture, not a default.
//

#if DEBUG
import SwiftUI

struct DirectorNextCutCard: Identifiable {
    var id: String
    var title: String
    var controller: FakeNextCutConsole
}

enum DirectorNextCutGallery {
    /// Walkthrough example. Not a product default (A4 is open).
    static let noticeExample = TimeInterval(2)

    static let auto = NextShotStatus.DirectorSection(
        level: .auto,
        activity: .active(.preparing(input: .b, shot: waistUp, settled: true)),
        prepared: .init(input: .b, shot: waistUp),
        nextCut: .init(input: .b, countdown: noticeExample, cancellable: true),
        alfieSetShot: [.b],
        qualified: .init(assist: true, auto: true, backup: false),
        handedToAlfie: true,
        runSheet: nil)

    static let backup = NextShotStatus.DirectorSection(
        level: .backup,
        activity: .active(.ready(input: .b, shot: waistUp)),
        prepared: .init(input: .b, shot: waistUp),
        nextCut: .init(input: .b, countdown: nil, cancellable: false),
        alfieSetShot: [.b],
        qualified: .init(assist: true, auto: true, backup: true),
        handedToAlfie: true,
        runSheet: nil)

    static let cards: [DirectorNextCutCard] = [
        DirectorNextCutCard(id: "auto-notice", title: "Auto · next cut", controller: FakeNextCutConsole(section: auto)),
        DirectorNextCutCard(id: "backup-next", title: "Backup · no countdown", controller: FakeNextCutConsole(section: backup)),
    ]

    private static let waistUp = DirectorShot(preset: .stage(.waistUp))
}

struct DirectorNextCutDemo: View {
    @StateObject private var live = FakeNextCutConsole(section: DirectorNextCutGallery.auto)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Esc cancels a cut that can be cancelled. The notice length is supplied with the cut.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Text("LIVE")
                .font(ConsoleStyle.label(11))
                .foregroundStyle(.white.opacity(0.55))
            DirectorNextCutNotice(controller: live)
            ForEach(DirectorNextCutGallery.cards) { card in
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title.uppercased())
                        .font(ConsoleStyle.label(11))
                        .foregroundStyle(.white.opacity(0.55))
                    DirectorNextCutNotice(controller: card.controller, ownsShortcut: false)
                }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }
}
#endif
