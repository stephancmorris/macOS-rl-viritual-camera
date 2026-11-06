//
//  TrackAGallerySnapshotTests.swift
//  CinematicCoreMacOSTests
//
//  Track A captures (UX J3, J4, J5, J12) over a synthetic picture: the
//  pill's lock states, a hovered candidate, the on-picture hints, the
//  Webcam use states and its one-time note. Footage stays dark in every
//  appearance, so each scene renders once, plus Reduce Transparency.
//  Set ALFIE_GALLERY_SNAPSHOTS=1 (TEST_RUNNER_ALFIE_GALLERY_SNAPSHOTS=1 on
//  xcodebuild) and ALFIE_GALLERY_SNAPSHOT_DIR to write the PNGs.
//

import AppKit
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct TrackAGallerySnapshotTests {
    private static let size = CGSize(width: 1000, height: 560)

    @Test(arguments: [false, true])
    func rendersTrackingScene(reduceTransparency: Bool) throws {
        let image = try #require(render(TrackingScene(), reduceTransparency: reduceTransparency))
        #expect(image.pixelsWide > 0)
        try write(image, name: reduceTransparency ? "track-a-tracking-reduce-transparency.png" : "track-a-tracking.png")
    }

    @Test(arguments: [false, true])
    func rendersWebcamScene(reduceTransparency: Bool) throws {
        let image = try #require(render(WebcamScene(), reduceTransparency: reduceTransparency))
        #expect(image.pixelsWide > 0)
        try write(image, name: reduceTransparency ? "track-a-webcam-reduce-transparency.png" : "track-a-webcam.png")
    }

    @Test func rendersPillGroupsAndStop() throws {
        let image = try #require(render(PillScene(), reduceTransparency: false, size: CGSize(width: 1240, height: 420)))
        #expect(image.pixelsWide > 0)
        try write(image, name: "track-a-pill.png")
    }

    // MARK: Rendering

    private func render<V: View>(_ view: V, reduceTransparency: Bool, size: CGSize? = nil) -> NSBitmapImageRep? {
        let size = size ?? Self.size
        var display = AlfieDisplayPreferences()
        display.reduceTransparency = reduceTransparency
        let host = NSHostingView(rootView: view
            .environment(\.colorScheme, .dark)
            .environment(\.alfieDisplayOverride, display)
            .frame(width: size.width, height: size.height))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        let window = TrackAGalleryWindow(contentRect: host.frame, styleMask: [.borderless],
                                         backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func write(_ image: NSBitmapImageRep, name: String) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" else { return }
        let directory: URL
        if let override = environment["ALFIE_GALLERY_SNAPSHOT_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieStateGallery", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png = try #require(image.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name))
        print("[TRACK-A] wrote \(directory.appendingPathComponent(name).path)")
    }
}

private final class TrackAGalleryWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// A synthetic stage: dark at the left, bright at the right, so a scrim is
/// shown over both extremes. Not a camera picture.
private struct SyntheticFootage: View {
    var body: some View {
        LinearGradient(colors: [Color(white: 0.06), Color(white: 0.35), Color(white: 0.96)],
                       startPoint: .leading, endPoint: .trailing)
    }
}

private func person(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, confidence: Float = 0.91)
    -> PersonDetector.DetectedPerson {
    PersonDetector.DetectedPerson(id: UUID(), boundingBox: CGRect(x: x, y: y, width: w, height: h),
                                  confidence: confidence, timestamp: 0, poseKeypoints: nil,
                                  faceBoundingBox: nil, faceLandmarkRatios: nil)
}

/// J3: candidates (one under the pointer), a locked subject, and both hints.
private struct TrackingScene: View {
    private let imageSize = CGSize(width: 1920, height: 1080)

    var body: some View {
        HStack(spacing: 0) {
            pane(title: "Detect: pointer over the left person", hints: nil) { size in
                ZStack {
                    let hovered = person(0.12, 0.15, 0.2, 0.6)
                    box(hovered, size: size, hovered: true)
                    box(person(0.6, 0.12, 0.22, 0.62, confidence: 0.84), size: size)
                }
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
            pane(title: "Hold: the subject is lost", hints: .init(candidatesClickable: true, showsRecoveryHint: true,
                                                                   isLocked: true)) { size in
                box(person(0.55, 0.15, 0.2, 0.6, confidence: 0.77), size: size)
            }
        }
        .overlay(alignment: .bottom) {
            TrackingHintLabel(text: TrackingHintCopy.firstLock)
                .padding(.bottom, 24)
        }
    }

    private func box(_ person: PersonDetector.DetectedPerson, size: CGSize, hovered: Bool = false) -> some View {
        BoundingBoxView(person: person, displayBoundingBox: person.boundingBox, imageSize: imageSize, viewSize: size,
                        isLocked: false, isActive: false, isRecovering: false, framingTitle: "Wide",
                        onSelect: nil, isHovered: hovered)
    }

    private func pane<Content: View>(title: String, hints: TrackingPresentation?,
                                     @ViewBuilder content: @escaping (CGSize) -> Content) -> some View {
        GeometryReader { geometry in
            ZStack {
                SyntheticFootage()
                content(geometry.size)
                if let hints {
                    TrackingHintLabel(text: hints.showsRecoveryHint ? TrackingHintCopy.recovery : TrackingHintCopy.firstLock)
                        .position(x: geometry.size.width / 2, y: geometry.size.height - 120)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AlfieColor.onVideo.emphasis)
                    .padding(6)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .position(x: geometry.size.width / 2, y: 18)
            }
        }
    }
}

/// J5: the three use states and the one-time note, over dark and bright.
private struct WebcamScene: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            SyntheticFootage()
            VStack(alignment: .leading, spacing: 14) {
                WebcamUsageChip(state: .inUse)
                WebcamUsageChip(state: .notInUse)
                WebcamUsageChip(state: .unknown)
                WebcamTipCard(onDismiss: {})
            }
            .padding(24)
            VStack(alignment: .trailing, spacing: 14) {
                WebcamUsageChip(state: .inUse)
                WebcamUsageChip(state: .notInUse)
                WebcamUsageChip(state: .unknown)
                WebcamTipCard(onDismiss: {})
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// J4 and J12: the lock states with their glyph, and the pill's Stop phases.
private struct PillScene: View {
    @StateObject private var manager = CameraManager()

    var body: some View {
        ZStack {
            SyntheticFootage()
            VStack(spacing: 22) {
                OperatorPill(cameraManager: manager)
                HStack(spacing: 18) {
                    ForEach(OperatorPill.LockState.allCases, id: \.self) { state in
                        HStack(spacing: 8) {
                            PillLockIndicator(state: state)
                            Text(state.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(state.labelColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(OperatorPillBackground(cornerRadius: 11))
                    }
                }
                HStack(spacing: 14) {
                    AlfieHoldToStopButton(confirmationMessage: StopRouteCopy.confirmation(for: .virtualCamera),
                                          previewPhase: .resting, onStop: {})
                    AlfieHoldToStopButton(previewPhase: .holding(since: 0), previewProgress: 0.6, onStop: {})
                    AlfieHoldToStopButton(previewPhase: .needsHold, onStop: {})
                    AlfieHoldToStopButton(previewPhase: .stopping, onStop: {})
                    AlfieHoldToStopButton(previewPhase: .failed, onStop: {})
                }
            }
        }
    }
}
