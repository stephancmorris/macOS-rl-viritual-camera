//
//  StateGallerySnapshotTests.swift
//  CinematicCoreMacOSTests
//
//  Renders the controls whose states carry meaning (mode picker, TAKE, Edit
//  Live, Stop, the pill's lock states, the tracking and tally colours) in
//  Light and Dark. Each render checks its size and that the sheet's ground is
//  the appearance's `AlfieColor.background`, so a role that stopped following
//  the colour scheme fails here. Set ALFIE_GALLERY_SNAPSHOTS=1 (via
//  TEST_RUNNER_ALFIE_GALLERY_SNAPSHOTS=1 on xcodebuild) to also write PNGs to
//  the test host's temporary directory; ALFIE_GALLERY_SNAPSHOT_DIR chooses
//  the folder, as for the other gallery captures. Hover, pressed and focus
//  join this sheet with the shared button style.
//

#if DEBUG
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct StateGallerySnapshotTests {
    private static let size = CGSize(width: 1100, height: 760)
    private static let buttonSheetSize = CGSize(width: 1100, height: 900)

    @Test(arguments: AlfieColorContrastTests.Look.allCases)
    func rendersEveryStateInEachAppearance(look: AlfieColorContrastTests.Look) throws {
        let image = try #require(Self.render(StateGallerySheet(), look: look))
        #expect(image.pixelsWide >= Int(Self.size.width))
        #expect(image.pixelsHigh >= Int(Self.size.height))

        // The sheet's padding is bare background.
        let sample = try #require(image.colorAt(x: 4, y: 4))
        #expect(Self.isBackground(sample, of: look), "ground \(sample) is not the \(look) background")

        try Self.write(image, name: "states-\(look.rawValue).png")
    }

    /// Every member of the shared button family in every state (UX F3), and
    /// the hold-to-stop phases (D3), on each appearance's background.
    @Test(arguments: AlfieColorContrastTests.Look.allCases)
    func rendersButtonStatesInEachAppearance(look: AlfieColorContrastTests.Look) throws {
        let image = try #require(Self.render(ButtonStatesSheet(), look: look, size: Self.buttonSheetSize))
        let sample = try #require(image.colorAt(x: 4, y: 4))
        #expect(Self.isBackground(sample, of: look), "ground \(sample) is not the \(look) background")
        try Self.write(image, name: "buttons-\(look.rawValue).png")
    }

    /// D2: the live Multiview console is dark even when the system is Light;
    /// every other screen follows the operator's appearance.
    @Test(arguments: [true, false])
    func liveConsoleIsForcedDarkInLight(isLive: Bool) throws {
        let sample = AlfieColor.background.modifier(LiveConsoleAppearance(isLive: isLive))
        let image = try #require(Self.render(sample, look: .light))
        let pixel = try #require(image.colorAt(x: 40, y: 40))
        let look: AlfieColorContrastTests.Look = isLive ? .dark : .light
        #expect(Self.isBackground(pixel, of: look), "isLive \(isLive): \(pixel) is not the \(look) background")
    }

    /// The offscreen render goes through the display's colour management, so
    /// a saturated navy lands a few levels off its token. What matters is
    /// that the ground is clearly this appearance's background and not the
    /// other one's.
    private static func isBackground(_ color: NSColor, of look: AlfieColorContrastTests.Look) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return false }
        func distance(_ other: AlfieColorContrastTests.Look) -> Double {
            let e = AlfieColorContrastTests.flatten(AlfieColor.background, over: nil, other)
            return max(abs(Double(c.redComponent) - e.r), abs(Double(c.greenComponent) - e.g),
                       abs(Double(c.blueComponent) - e.b))
        }
        let other: AlfieColorContrastTests.Look = look == .dark ? .light : .dark
        return distance(look) < 0.08 && distance(look) < distance(other) / 4
    }

    @Test func refusedTakeKeepsItsReason() {
        let refused = TakeAvailability.evaluate(FakeConsoleModel(scenario: .oneInput).snapshot)
        #expect(!refused.isEligible)
        #expect(!refused.subtitle.isEmpty)
        let eligible = TakeAvailability.evaluate(FakeConsoleModel(scenario: .ready).snapshot)
        #expect(eligible.isEligible)
    }

    // MARK: Rendering

    private static func render<V: View>(_ view: V, look: AlfieColorContrastTests.Look,
                                        size: CGSize = size) -> NSBitmapImageRep? {
        let scheme: ColorScheme = look == .dark ? .dark : .light
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        let window = StateGalleryWindow(contentRect: host.frame, styleMask: [.borderless],
                                        backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: look == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private static func write(_ image: NSBitmapImageRep, name: String) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" else { return }
        let directory: URL
        if let override = environment["ALFIE_GALLERY_SNAPSHOT_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AlfieStateGallery", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png = try #require(image.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name))
        print("[STATES] wrote \(directory.appendingPathComponent(name).path)")
    }
}

/// Keeps the requested offscreen size on a hosted runner's small screen.
private final class StateGalleryWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The shared button family: a row per member, a column per state, then the
/// same members on the pill's glass, then the hold-to-stop phases.
private struct ButtonStatesSheet: View {
    private enum Column: String, CaseIterable {
        case rest = "Rest", hover = "Hover", pressed = "Pressed", focus = "Focus", disabled = "Disabled"

        var forced: AlfieForcedControlState? {
            switch self {
            case .rest, .disabled: return nil
            case .hover: return .hover
            case .pressed: return .pressed
            case .focus: return .focus
            }
        }
    }

    private struct Member: Identifiable {
        let id: String
        let title: String
        let role: AlfieButtonStyle.Role
        var isSelected = false
    }

    private static let chrome: [Member] = [
        Member(id: "primary", title: "Start session", role: .primary),
        Member(id: "secondary", title: "Check pair", role: .secondary),
        Member(id: "quiet", title: "Run sheet…", role: .quiet),
        Member(id: "destructive", title: "TAKE", role: .destructive),
        Member(id: "refusing", title: "TAKE · no Preview", role: .refusing),
        Member(id: "segment", title: "Multi Cam", role: .segment),
        Member(id: "segment-selected", title: "Single Cam", role: .segment, isSelected: true)
    ]

    private static let video: [Member] = [
        Member(id: "v-quiet", title: "Detect", role: .quiet),
        Member(id: "v-segment", title: "Waist Up", role: .segment, isSelected: true),
        Member(id: "v-toggle-on", title: "Manual", role: .toggle(isOn: true)),
        Member(id: "v-toggle-off", title: "Auto Pan", role: .toggle(isOn: false)),
        Member(id: "v-secondary", title: "+ Push in", role: .secondary),
        Member(id: "v-destructive", title: "Stop session", role: .destructive)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ForEach(Self.chrome) { member in
                stateRow(member, surface: .chrome)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.video) { member in
                    stateRow(member, surface: .video)
                }
            }
            .padding(12)
            .background(AlfieColor.onVideo.glass, in: RoundedRectangle(cornerRadius: 18))
            .background(AlfieColor.videoWell, in: RoundedRectangle(cornerRadius: 18))
            .environment(\.colorScheme, .dark)
            HStack(spacing: 18) {
                AlfieHoldToStopButton(previewPhase: .resting) {}
                AlfieHoldToStopButton(previewPhase: .holding(since: 0), previewProgress: 0.5) {}
                AlfieHoldToStopButton(previewPhase: .needsHold) {}
                AlfieHoldToStopButton(previewPhase: .stopping, previewProgress: 1) {}
                AlfieHoldToStopButton(previewPhase: .failed) {}
            }
            .padding(12)
            .background(AlfieColor.onVideo.glass, in: RoundedRectangle(cornerRadius: 18))
            .background(AlfieColor.videoWell, in: RoundedRectangle(cornerRadius: 18))
            .environment(\.colorScheme, .dark)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AlfieColor.background)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("").frame(width: 130, alignment: .leading)
            ForEach(Column.allCases, id: \.self) { column in
                Text(column.rawValue.uppercased())
                    .font(ConsoleStyle.label(10))
                    .foregroundStyle(AlfieColor.tertiaryText)
                    .frame(width: 150)
            }
        }
    }

    private func stateRow(_ member: Member, surface: AlfieButtonStyle.Surface) -> some View {
        HStack(spacing: 12) {
            Text(member.id)
                .font(ConsoleStyle.label(10))
                .foregroundStyle(surface == .video ? AlfieColor.onVideo.secondary : AlfieColor.tertiaryText)
                .frame(width: 130, alignment: .leading)
            ForEach(Column.allCases, id: \.self) { column in
                Button {} label: {
                    Text(member.title)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .alfieButtonStyle(member.role, surface: surface, isSelected: member.isSelected,
                                  cornerRadius: 8)
                .disabled(column == .disabled && member.role != .refusing && member.role != .destructive)
                .environment(\.alfieForcedControlState, column.forced)
                .frame(width: 150)
            }
        }
    }
}

/// One sheet of every stateful control, on the appearance's background.
private struct StateGallerySheet: View {
    private let twoCameras = OperatorModeChoice.Cameras(devices: [(uniqueID: "a", isBuiltIn: false),
                                                                 (uniqueID: "b", isBuiltIn: true)])
    private let oneCamera = OperatorModeChoice.Cameras(devices: [(uniqueID: "a", isBuiltIn: false)])

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            row("Mode picker · all available, then Multi Cam disabled") {
                HStack(spacing: 24) {
                    OperatorModePicker(store: Self.store(), cameras: twoCameras, style: .stoppedScreen)
                    OperatorModePicker(store: Self.store(), cameras: oneCamera, style: .setupHeader)
                }
            }
            row("TAKE · eligible, refused with its reason, Edit Live on") {
                HStack(spacing: 16) {
                    ForEach([FakeConsoleModel.Scenario.ready, .oneInput, .editLive], id: \.self) { scenario in
                        TakeBarView(availability: .evaluate(FakeConsoleModel(scenario: scenario).snapshot))
                            .frame(width: 330, height: MultiviewLayout.barHeight)
                    }
                }
            }
            row("Pill lock states · on the glass over footage") {
                HStack(spacing: 18) {
                    ForEach(OperatorPill.LockState.allCases, id: \.self) { state in
                        HStack(spacing: 8) {
                            Circle().fill(state.dotColor).frame(width: 7, height: 7)
                            Text(state.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(state.labelColor)
                        }
                    }
                    Button {} label: { StopSessionLabel() }
                        .alfieButtonStyle(.destructive, surface: .video, cornerRadius: 14)
                }
                .padding(12)
                .background(AlfieColor.onVideo.glass, in: RoundedRectangle(cornerRadius: 22))
                .background(AlfieColor.videoWell, in: RoundedRectangle(cornerRadius: 22))
            }
            row("Tracking and tally on footage") {
                HStack(spacing: 10) {
                    chip("PERSON · 92%", AlfieColor.tracking.candidate, text: AlfieColor.onBrightFill)
                    chip("ACQUIRING", AlfieColor.tracking.acquiring, text: AlfieColor.onBrightFill)
                    chip("SUBJECT · MEDIUM", AlfieColor.tracking.locked, text: AlfieColor.onBrightFill)
                    chip("PGM", AlfieColor.tally.program, text: AlfieColor.onFill)
                    chip("PVW", AlfieColor.tally.preview, text: AlfieColor.onBrightFill)
                    chip("CAM A · PROGRAM", AlfieColor.tally.programChip, text: AlfieColor.onFill)
                    chip("CAM B", AlfieColor.tally.previewChip, text: AlfieColor.onFill)
                }
                .padding(12)
                .background(AlfieColor.videoWell, in: RoundedRectangle(cornerRadius: 10))
            }
            row("Text roles") {
                HStack(spacing: 18) {
                    Text("Text").foregroundStyle(AlfieColor.text)
                    Text("Secondary").foregroundStyle(AlfieColor.secondaryText)
                    Text("Tertiary").foregroundStyle(AlfieColor.tertiaryText)
                    Text("Disabled").foregroundStyle(AlfieColor.disabledText)
                    Text("Link").foregroundStyle(AlfieColor.accentText)
                    Text("Live").foregroundStyle(AlfieColor.live)
                    Text("Warning").foregroundStyle(AlfieColor.warning)
                    Text("Error").foregroundStyle(AlfieColor.danger)
                    Text("Next start").foregroundStyle(AlfieColor.nextStart)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(12)
                .background(AlfieColor.card, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AlfieColor.background)
    }

    private static func store() -> OperatorModeStore {
        OperatorModeStore(defaults: UserDefaults(suiteName: "alfie-states-\(UUID().uuidString)")!,
                          multiviewEnabled: true)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(ConsoleStyle.label(10))
                .foregroundStyle(AlfieColor.tertiaryText)
            content()
        }
    }

    private func chip(_ title: String, _ fill: Color, text: Color) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
    }
}
#endif
