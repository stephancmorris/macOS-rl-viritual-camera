//
//  DirectorNextDemo.swift
//  CinematicCoreMacOS
//
//  C-03 gallery. The next-shot panel stays 600×70. AUTO appears only when
//  Alfie set that input's shot.
//

#if DEBUG
import SwiftUI

struct DirectorNextDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            labeled("Prepared shot") {
                NextShotPanel(status: Self.readyStatus.withDirector(Self.preparing))
                    .frame(width: 600, height: MultiviewLayout.barHeight)
            }
            labeled("No shot prepared") {
                NextShotPanel(status: Self.readyStatus.withDirector(Self.nothingPrepared))
                    .frame(width: 600, height: MultiviewLayout.barHeight)
            }
            HStack(spacing: 16) {
                labeled("Alfie set this shot") {
                    tile(.b, badge: true)
                }
                labeled("Operator set this shot") {
                    tile(.b, badge: false)
                }
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(ConsoleStyle.label(11))
                .foregroundStyle(.white.opacity(0.55))
            content()
        }
    }

    private func tile(_ channel: ChannelID, badge: Bool) -> some View {
        let model = InputTileModel(
            slot: .B,
            isAssigned: true,
            role: .preview,
            name: "Band side",
            shot: "Waist Up",
            health: .rate("50.0"),
            renderedImage: nil)
        return InputTileView(
            model: model,
            onCue: { _ in },
            directorBadge: badge && Self.preparing.showsAutoBadge(on: channel) ? NextShotStatus.DirectorSection.autoBadge : nil)
    }

    static let preparing = NextShotStatus.DirectorSection(
        level: .assist,
        activity: .active(.preparing(input: .b, shot: DirectorShot(preset: .stage(.waistUp)), settled: true)),
        prepared: .init(input: .b, shot: DirectorShot(preset: .stage(.waistUp))),
        nextCut: nil,
        alfieSetShot: [.b],
        qualified: .init(assist: true, auto: false, backup: false),
        handedToAlfie: true,
        runSheet: nil)

    static let nothingPrepared = NextShotStatus.DirectorSection(
        level: .assist,
        activity: .abstaining(.previewIsSafeWide),
        prepared: nil,
        nextCut: nil,
        alfieSetShot: [],
        qualified: .init(assist: true, auto: false, backup: false),
        handedToAlfie: true,
        runSheet: nil)

    static var readyStatus: NextShotStatus {
        NextShotStatus.make(FakeConsoleModel.snapshot(for: .ready, standard: .p50))
    }
}
#endif
