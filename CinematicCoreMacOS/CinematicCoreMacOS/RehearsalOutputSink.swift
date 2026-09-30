//
//  RehearsalOutputSink.swift
//  CinematicCoreMacOS
//
//  Development-only Program destination (DeveloperFlags.allowRehearsalOutput):
//  accepts every frame and sends it nowhere, so a show — and Take — can be
//  rehearsed on a Mac with one screen and no virtual-camera client. Never a
//  fallback in release builds: the sink is only injected when the flag is on.
//

import CoreVideo
import Foundation

final class RehearsalOutputSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .rehearsal
    var isAvailable: Bool { true }
    var summary: String { "Rehearsal: Program frames are accepted and sent nowhere. Development builds only." }
    var detail: String { "Nothing reaches the ATEM or a video app. Choose Direct output (HDMI / USB-C) or Virtual Camera for a real show." }
    var lastErrorDescription: String? { nil }
    var playoutFrameRate: Double? { nil }
    var presentationObservability: String { "Rehearsal: handoff = frame accepted and discarded; nothing is presented" }
    var onStateChange: (() -> Void)?

    func connect() {}
    func disconnect() {}
    func updateCaptureStatus(isRunning: Bool) {}

    @discardableResult
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { true }
}
