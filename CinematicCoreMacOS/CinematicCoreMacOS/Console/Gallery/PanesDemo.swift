//
//  PanesDemo.swift
//  CinematicCoreMacOS
//
//  Multiview gallery section for the CONSOLE card: the full console frame at
//  its 1280×800 minimum, strip and pill as placeholders.
//

#if DEBUG
import SwiftUI

struct PanesDemo: View {
    @ObservedObject var model: FakeConsoleModel

    var body: some View {
        MultiviewConsoleView(snapshot: model.snapshot, actions: model)
            .frame(width: MultiviewLayout.minimumSize.width, height: MultiviewLayout.minimumSize.height)
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.1)))
    }
}
#endif
