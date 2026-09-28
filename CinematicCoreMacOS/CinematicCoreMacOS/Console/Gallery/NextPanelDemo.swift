//
//  NextPanelDemo.swift
//  CinematicCoreMacOS
//
//  Multiview gallery section for the NEXT-PANEL card, at its 600×70 size.
//

#if DEBUG
import SwiftUI

struct NextPanelDemo: View {
    @ObservedObject var model: FakeConsoleModel

    var body: some View {
        NextShotPanel(status: .make(model.snapshot))
            .frame(width: 600, height: MultiviewLayout.barHeight)
            .padding(12)
            .background(ConsoleStyle.background)
    }
}
#endif
