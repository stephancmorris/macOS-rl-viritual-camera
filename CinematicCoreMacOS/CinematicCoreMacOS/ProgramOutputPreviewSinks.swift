//
//  ProgramOutputPreviewSinks.swift
//  CinematicCoreMacOS
//

import Combine
import CoreVideo

#if DEBUG
@MainActor
final class PreviewOutputSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .virtualCamera
    var isAvailable: Bool { true }
    var summary: String { "Preview route is available." }
    var detail: String { "Used only for the SwiftUI preview." }
    var lastErrorDescription: String? { nil }
    var canReconnect: Bool { false }
    var reconnectStatus: String? { nil }
    var bringUpChecks: [OutputBringUpCheck] {
        [
            OutputBringUpCheck(
                id: "preview.virtual.link",
                title: "Virtual Camera · XPC Link",
                status: "Preview",
                detail: "Preview output sink is active only inside SwiftUI previews.",
                level: .info
            )
        ]
    }
    var onStateChange: (() -> Void)?
    func connect() {}
    func disconnect() {}
    func reconnect() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { true }
}

@MainActor
final class PreviewSystemExtensionStatusManager: ObservableObject, SystemExtensionStatusProviding {
    let badgeTitle = "Extension Ready"
    let summaryText = "Preview system extension manager is active only inside SwiftUI previews."
    let primaryActionTitle: String? = nil
    let primaryActionSystemImage = "checkmark.seal"
    let outputCheckLevel: OutputCheckLevel = .ok

    func triggerPrimaryAction() async {}
}
#endif
