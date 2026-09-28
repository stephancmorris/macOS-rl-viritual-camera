//
//  PillDemo.swift
//  CinematicCoreMacOS
//
//  Multiview gallery section for the PILL-TARGET card. Stub until that card lands.
//

#if DEBUG
import SwiftUI

struct PillDemo: View {
    @ObservedObject var model: FakeConsoleModel
    @StateObject private var manager = CameraManager()

    var body: some View {
        OperatorPill(cameraManager: manager, controlTarget: target)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    private var target: ControlTarget {
        let target = model.snapshot.controlTarget
        if model.snapshot.previewChannel == nil { return .singleCamera }
        if model.snapshot.editLive { return .editingLive(channel: target.channel) }
        return .preview(channel: target.channel)
    }
}
#endif
