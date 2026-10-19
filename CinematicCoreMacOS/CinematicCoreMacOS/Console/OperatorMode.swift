//
//  OperatorMode.swift
//  CinematicCoreMacOS
//
//  The operator's one choice of screen: Single Cam, Multi Cam or Webcam, always
//  in that order (MODES-SPEC, 18 Oct 2026). What used to be picked as a
//  "format" derives from it: the composer's cinematic format, the capture
//  profile and which console ContentView shows. Single Cam and Multi Cam share
//  the Stage format; they differ only in console and in whether more than one
//  input may exist. See docs/ALFIE_MULTICAMERA_SPEC.md "Operator modes".
//

import Combine
import Foundation

nonisolated enum OperatorMode: String, CaseIterable, Identifiable, Sendable {
    /// The traditional single-camera view with every Stage shot.
    case singleCam
    /// The Multiview console (Preview / Program / Take), formerly "Stage".
    case multiCam
    /// The traditional single-camera view with close-range framing.
    case webcam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .singleCam: return "Single Cam"
        case .multiCam: return "Multi Cam"
        case .webcam: return "Webcam"
        }
    }

    var detail: String {
        switch self {
        case .singleCam: return "One stage camera: wide source, crop and every Stage shot."
        case .multiCam: return "Preview and Program with Take, for more than one stage camera."
        case .webcam: return "Close-range framing for a video call or webcam."
        }
    }

    /// The value written into diagnostics manifests.
    var diagnosticsName: String {
        switch self {
        case .singleCam: return "single_cam"
        case .multiCam: return "multi_cam"
        case .webcam: return "webcam"
        }
    }

    var cinematicFormat: ShotComposer.Config.CinematicFormat {
        self == .webcam ? .webcam : .stage
    }

    var captureProfile: CaptureProfilePolicy.Profile {
        CaptureProfilePolicy.Profile(cinematicFormat)
    }

    var presentation: ConsolePresentation { ConsolePresentation.resolve(for: self) }

    var allowsMultipleInputs: Bool { presentation.allowsMultipleInputs }

    /// The modes the operator may pick, in display order. The Multiview kill
    /// switch (`DeveloperFlags.useMultiviewConsole` off) removes Multi Cam.
    static func available(multiviewEnabled: Bool) -> [OperatorMode] {
        multiviewEnabled ? allCases : allCases.filter { $0 != .multiCam }
    }

    /// This mode, or Single Cam when this one is not available.
    func resolved(multiviewEnabled: Bool) -> OperatorMode {
        Self.available(multiviewEnabled: multiviewEnabled).contains(self) ? self : .singleCam
    }
}

/// Whether the operator may change mode now (MODE-SWITCH). Stopped, any
/// change is allowed. While the show is live, leaving Multi Cam needs A to be
/// Program with no other channel, so a console swap never hides a live input
/// or changes what is routed. Every other live change is allowed: Single Cam
/// to Multi Cam keeps capture running with A as Program, and a change into or
/// out of Webcam applies its capture profile at the next Start.
nonisolated enum OperatorModeSwitch {
    struct ShowState: Equatable, Sendable {
        /// Any channel is running or starting.
        var isLive: Bool
        var programChannel: ChannelID
        /// Channels other than A that exist, running or not.
        var otherChannels: [ChannelID]
    }

    enum Decision: Equatable, Sendable {
        case allowed
        case refused(String)
    }

    static func decide(from: OperatorMode, to: OperatorMode, state: ShowState) -> Decision {
        guard from != to, state.isLive, from == .multiCam else { return .allowed }
        if state.programChannel != .a {
            return .refused("\(state.programChannel.cameraLabel) is Program. Stop the show to leave Multi Cam.")
        }
        if !state.otherChannels.isEmpty {
            let cameras = state.otherChannels.map(\.cameraLabel).joined(separator: " and ")
            return .refused("Remove \(cameras) or stop the show to leave Multi Cam.")
        }
        return .allowed
    }
}

/// Persists the operator's mode and applies it to channels. The only writer of
/// `ShotComposer.Config.cinematicFormat` in the app; the show applies the mode
/// to every channel it owns, including channels added later.
@MainActor
final class OperatorModeStore: ObservableObject {
    nonisolated static let key = "operatorMode"
    /// The two-format key the Settings picker used before the three modes.
    /// Read once to migrate, and still written so an older build launched on
    /// the same Mac opens in the matching format.
    nonisolated static let legacyFormatKey = "cinematicFormat"

    @Published private(set) var mode: OperatorMode
    /// What the operator may pick, in display order.
    let available: [OperatorMode]
    /// Called after every accepted change, with the old and new mode.
    var modeChanged: ((_ from: OperatorMode, _ to: OperatorMode) -> Void)?
    /// Whether a change may happen now; set by the show. Nil allows it.
    var switchDecision: ((_ from: OperatorMode, _ to: OperatorMode) -> OperatorModeSwitch.Decision)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard,
         multiviewEnabled: Bool = DeveloperFlags.useMultiviewConsole) {
        self.defaults = defaults
        available = OperatorMode.available(multiviewEnabled: multiviewEnabled)
        let stored = defaults.string(forKey: Self.key)
        let launch = Self.launchMode(stored: stored,
                                     legacyFormat: defaults.string(forKey: Self.legacyFormatKey))
        // Migrate once: an existing mode is never overwritten. The unresolved
        // mode is saved so turning the kill switch back on restores Multi Cam.
        if stored == nil { defaults.set(launch.rawValue, forKey: Self.key) }
        mode = launch.resolved(multiviewEnabled: multiviewEnabled)
    }

    /// The mode a launch starts in, before the kill switch. A saved mode wins;
    /// otherwise the legacy format maps Stage → Multi Cam (the console Stage
    /// showed) and Webcam → Webcam; a fresh install gets Single Cam.
    nonisolated static func launchMode(stored: String?, legacyFormat: String?) -> OperatorMode {
        if let stored, let mode = OperatorMode(rawValue: stored) { return mode }
        switch legacyFormat {
        case "stage": return .multiCam
        case "webcam": return .webcam
        default: return .singleCam
        }
    }

    /// The operator asks for a mode. Returns why it was refused, or nil when
    /// the mode is now `newMode`. A refusal changes nothing.
    @discardableResult
    func request(_ newMode: OperatorMode) -> String? {
        guard available.contains(newMode) else { return "\(newMode.title) is not available in this build." }
        if case .refused(let reason) = switchDecision?(mode, newMode) ?? .allowed { return reason }
        select(newMode)
        return nil
    }

    /// Switch modes without the live-switch check. Ignores a mode that is not
    /// available or already chosen. Operator controls use `request`.
    func select(_ newMode: OperatorMode) {
        guard available.contains(newMode), newMode != mode else { return }
        let oldMode = mode
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Self.key)
        defaults.set(newMode.cinematicFormat.rawValue, forKey: Self.legacyFormatKey)
        modeChanged?(oldMode, newMode)
    }

    /// Bring a channel's mode and composer format in line with the current mode.
    func apply(to channel: CameraManager) {
        channel.operatorMode = mode
        if channel.shotComposer.config.cinematicFormat != mode.cinematicFormat {
            channel.shotComposer.config.cinematicFormat = mode.cinematicFormat
        }
    }
}
