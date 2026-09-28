//
//  TakeBarDemo.swift
//  CinematicCoreMacOS
//
//  Multiview gallery section for the TAKE-BAR card, at its 600×70 size.
//

#if DEBUG
import SwiftUI

struct TakeBarDemo: View {
    @ObservedObject var model: FakeConsoleModel

    var body: some View {
        TakeBarView(
            availability: .evaluate(model.snapshot),
            onTake: model.take,
            onSetEditLive: model.setEditLive)
            .frame(width: 600, height: MultiviewLayout.barHeight)
            .padding(12)
            .background(ConsoleStyle.background)
    }
}
#endif
