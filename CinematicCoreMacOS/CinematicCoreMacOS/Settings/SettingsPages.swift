//
//  SettingsPages.swift
//  CinematicCoreMacOS
//
//  One view per Settings sidebar entry. Pages hold only controls; every live
//  statistic is on Diagnostics.
//

import AppKit
import Metal
import SwiftUI

// MARK: - General

struct GeneralSettingsPage: View {
    @ObservedObject var systemExtensionManager: SystemExtensionActivationManager
    @AppStorage(AppAppearance.userDefaultsKey) private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        SettingsPage(title: "General", subtitle: "How Alfie looks on this Mac.") {
            SettingsSectionLabel("Appearance")
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ForEach(AppAppearance.allCases) { option in
                        AppearanceTile(option: option, isSelected: option == appearance) {
                            appearanceRaw = option.rawValue
                            option.apply()
                        }
                    }
                }
                Text("System follows the macOS setting. Appearance never touches the Program feed.")
                    .font(.system(size: 12))
                    .foregroundStyle(AlfieColor.secondaryText)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AlfieColor.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AlfieColor.separator))

            SettingsSectionLabel("About")
            SettingsCard {
                SettingsRow(title: "Build") { SettingsValueText(buildString) }
                SettingsRow(title: "Camera extension") { SettingsValueText(extensionStatus) }
                SettingsRow(title: "GPU") { SettingsValueText(gpuName) }
            }
        }
    }

    private var buildString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var extensionStatus: String {
        if systemExtensionManager.isInstallReady {
            return "cmio · loaded"
        }
        switch systemExtensionManager.status {
        case .unknown: return "cmio · unknown"
        case .notInstalled: return "cmio · not installed"
        case .activationRequested: return "cmio · activating"
        case .awaitingUserApproval: return "cmio · awaiting approval"
        case .installed: return "cmio · loaded"
        case .failed: return "cmio · failed"
        }
    }

    private var gpuName: String {
        MTLCreateSystemDefaultDevice()?.name ?? "Metal unavailable"
    }
}

/// A miniature window in the appearance it stands for. System shows both
/// halves because it can be either.
private struct AppearanceTile: View {
    let option: AppAppearance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: 132, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(AlfieColor.border))
                Text(option.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AlfieColor.text)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? AlfieColor.accent : AlfieColor.border,
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title) appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var preview: some View {
        switch option {
        case .system:
            HStack(spacing: 0) {
                MiniWindow(isDark: false)
                MiniWindow(isDark: true)
            }
        case .light:
            MiniWindow(isDark: false)
        case .dark:
            MiniWindow(isDark: true)
        }
    }
}

private struct MiniWindow: View {
    let isDark: Bool

    var body: some View {
        // Fixed colours: each tile shows its own appearance whatever the
        // window's current one is.
        let sidebar = isDark ? Color(red: 0.07, green: 0.08, blue: 0.10) : Color(red: 0.93, green: 0.93, blue: 0.94)
        let ground = isDark ? Color(red: 0.055, green: 0.063, blue: 0.082) : Color(red: 0.96, green: 0.96, blue: 0.97)
        let card = isDark ? Color(red: 0.094, green: 0.106, blue: 0.129) : .white
        let accent = isDark ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color(red: 0.0, green: 0.4, blue: 0.84)
        HStack(spacing: 0) {
            sidebar.frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(card).frame(height: 14)
                RoundedRectangle(cornerRadius: 3).fill(card).frame(height: 14)
                RoundedRectangle(cornerRadius: 3).fill(accent).frame(width: 26, height: 6)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ground)
        }
    }
}

// MARK: - Show & cameras

struct ShowSettingsPage: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var show: ShowCoordinator
    @AppStorage(ShowStandard.userDefaultsKey) private var showStandardRaw = ShowStandard.p50.rawValue

    var body: some View {
        SettingsPage(title: "Show & cameras",
                     subtitle: "What kind of show you run. Assign CAM A–D on the Show setup screen.") {
            SettingsSectionLabel("Show")
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mode")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AlfieColor.text)
                    OperatorModePicker(store: show.operatorModes,
                                       cameras: OperatorModeChoice.Cameras(cameraManager.availableCameras),
                                       style: .form)
                        .labelsHidden()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)

                SettingsRow(title: "Show standard",
                            detail: "Must match the ATEM switcher's video standard.",
                            timing: .nextStart) {
                    Picker("Show standard", selection: $showStandardRaw) {
                        ForEach(ShowStandard.allCases) { standard in
                            Text(standard.title).tag(standard.rawValue)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if cameraManager.availableCameras.contains(where: \.isBuiltIn) {
                SettingsSectionLabel("Cameras")
                SettingsCard {
                    SettingsRow(title: "Built-in camera testing",
                                detail: ShowSetupModel.builtInCameraTestDetail) {
                        Toggle("Built-in camera testing", isOn: Binding(
                            get: { show.isBuiltInCameraTestEnabled },
                            set: { _ = show.setBuiltInCameraTestEnabled($0) }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(show.isAnyChannelLive)
                            .help("Stop all cameras before changing built-in camera testing.")
                    }
                }
            }
        }
    }
}

// MARK: - Output

struct OutputSettingsPage<SystemExtensionManager: SystemExtensionStatusProviding>: View {
    @ObservedObject var programOutput: ProgramOutputManager
    @ObservedObject var systemExtensionManager: SystemExtensionManager

    /// Persisted Program Display target (0 = automatic), read live by
    /// `DisplayOutputSink`.
    @AppStorage(ProgramDisplaySelection.userDefaultsKey) private var programDisplayID = 0
    @State private var availableDisplays: [ProgramDisplayOption] = ProgramDisplayOption.current()

    var body: some View {
        SettingsPage(title: "Output", subtitle: "Where the Program feed goes.") {
            routeStatus
                .padding(.top, 20)

            SettingsSectionLabel("Route")
            SettingsCard {
                SettingsRow(title: "Preferred route") {
                    Picker("Preferred route", selection: $programOutput.preferredRoute) {
                        ForEach(programOutput.configuredRoutes) { route in
                            Label(route.title, systemImage: route.systemImage).tag(route)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if programOutput.configuredRoutes.contains(.display) {
                    SettingsRow(title: "Output port",
                                detail: "The port your HDMI-to-SDI converter or ATEM is plugged into. It shows black until the show starts, then Program. At Start, Alfie switches it to the show standard; macOS restores its own setting when you switch output or quit.",
                                timing: .nextStart) {
                        Picker("Output port", selection: $programDisplayID) {
                            ForEach(availableDisplays) { option in
                                Text(option.label).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                }

                SettingsRow(title: "Virtual camera extension", detail: systemExtensionManager.summaryText) {
                    if let actionTitle = systemExtensionManager.primaryActionTitle {
                        Button {
                            Task { await systemExtensionManager.triggerPrimaryAction() }
                        } label: {
                            Label(actionTitle, systemImage: systemExtensionManager.primaryActionSystemImage)
                        }
                    } else {
                        Text(systemExtensionManager.badgeTitle)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(systemExtensionManager.outputCheckLevel.color)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification)) { _ in
                availableDisplays = ProgramDisplayOption.current()
            }

            if programOutput.configuredRoutes.contains(.display) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(AlfieColor.nextStart)
                        .accessibilityHidden(true)
                    Text("Turn on Focus / Do Not Disturb before the show so notifications can't reach the feed.")
                        .font(.system(size: 12))
                        .foregroundStyle(AlfieColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AlfieColor.nextStartSoft))
                .padding(.top, 16)
            }

            SettingsFootnote("Checklist, sink health and frame counts are on Diagnostics.")
        }
    }

    private var routeStatus: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(programOutput.activeRoute == nil ? AlfieColor.tertiaryText : AlfieColor.live)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(programOutput.activeRouteTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AlfieColor.text)
                Text(programOutput.preferredSinkReconnectStatus ?? programOutput.routingSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(AlfieColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                programOutput.reconnectPreferredRoute()
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
            .disabled(!programOutput.preferredSinkCanReconnect)
            .help("Tear down the preferred route's connection and reconnect immediately.")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AlfieColor.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AlfieColor.separator))
    }
}

// MARK: - Auto-framing

struct FramingSettingsPage: View {
    @ObservedObject var shotComposer: ShotComposer
    /// The crop engine mirrors the composer's smoothing (CR-030).
    let cropEngine: CropEngine?
    @State private var showFineTune = false

    private var isEnabled: Bool { shotComposer.config.isEnabled }

    var body: some View {
        SettingsPage(title: "Auto-framing",
                     subtitle: "How Alfie follows the speaker and frames the shot.",
                     timing: .live) {
            SettingsCard {
                SettingsRow(title: "Auto-framing",
                            detail: "Aims for a stable speaker shot when pose keypoints are available.") {
                    Toggle("Auto-framing", isOn: $shotComposer.config.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            .padding(.top, 20)

            Group {
                SettingsSectionLabel("Feel")
                feelCard

                SettingsSectionLabel("Shot")
                shotCard

                fineTuneHeader
                if showFineTune {
                    fineTuneCard
                }
            }
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
        }
        // Editing a preset-controlled value flips Feel to Custom, or back to a
        // preset if the values happen to match one.
        .onChange(of: shotComposer.config.steadyBandWidth) { syncTuningPreset() }
        .onChange(of: shotComposer.config.smoothingFactor) { syncTuningPreset() }
        .onChange(of: shotComposer.config.targetHoldDuration) { syncTuningPreset() }
        .onChange(of: shotComposer.config.autoPanSpeed) { syncTuningPreset() }
    }

    private var feelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(ShotComposer.Config.TuningPreset.selectable) { preset in
                    FeelPresetButton(preset: preset,
                                     isSelected: shotComposer.config.tuningPreset == preset) {
                        shotComposer.config.apply(preset)
                    }
                }
            }

            HStack(spacing: 8) {
                if shotComposer.config.tuningPreset == .custom {
                    SettingsTag(text: "Custom")
                }
                Text(shotComposer.config.tuningPreset == .custom
                     ? "You have fine-tuned the values below. Pick a feel to reset them."
                     : shotComposer.config.tuningPreset.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(AlfieColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if shotComposer.config.steadyFollowingEnabled {
                Rectangle().fill(AlfieColor.separator).frame(height: 1)
                SettingsSliderRow(
                    title: "Steady band",
                    detail: "The speaker moves freely inside this band before the shot re-centers. Yellow guides show it in Preview.",
                    value: cgFloatBinding(\.steadyBandWidth),
                    range: 0.04...0.30,
                    step: 0.01,
                    format: percent
                )
                .padding(.horizontal, -16)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AlfieColor.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AlfieColor.separator))
    }

    private var shotCard: some View {
        SettingsCard {
            SettingsRow(title: "Frame profile", detail: shotComposer.config.frameProfile.detail) {
                Picker("Frame profile", selection: $shotComposer.config.frameProfile) {
                    ForEach(ShotComposer.Config.FrameProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            if shotComposer.config.cinematicFormat == .stage {
                headroomRow("Full-body headroom", preset: .fullBody)
                headroomRow("Waist-up headroom", preset: .waistUp)
                SettingsRow(title: "Headroom defaults",
                            detail: "Clear space above the head, as a share of the output shot.") {
                    Button("Reset") { shotComposer.config.resetStageHeadroom() }
                }
            }
        }
    }

    private func headroomRow(_ title: String, preset: ShotComposer.Config.ShotPreset) -> some View {
        SettingsSliderRow(
            title: title,
            value: Binding(
                get: { Double(shotComposer.config.headroom(for: preset)) },
                set: { shotComposer.config.setHeadroom(CGFloat($0), for: preset) }
            ),
            range: Double(ShotComposer.Config.stageHeadroomRange.lowerBound)...Double(ShotComposer.Config.stageHeadroomRange.upperBound),
            step: 0.01,
            format: percent
        )
    }

    private var fineTuneHeader: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showFineTune.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(showFineTune ? 90 : 0))
                Text("FINE-TUNE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                Text("· changing these sets Feel to Custom")
                    .font(.system(size: 12))
            }
            .foregroundStyle(AlfieColor.tertiaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
        .padding(.top, 26)
        .padding(.bottom, 8)
        .accessibilityLabel("Fine-tune")
        .accessibilityValue(showFineTune ? "Expanded" : "Collapsed")
    }

    private var fineTuneCard: some View {
        SettingsCard {
            SettingsSliderRow(
                title: "Smoothing",
                detail: "Spring strength per frame, from Fast to Cinematic.",
                value: Binding(
                    get: { Double(shotComposer.config.smoothingFactor) },
                    // The frame path follows the composer's smoothing and the
                    // crop engine mirrors it, so write both (CR-030).
                    set: {
                        shotComposer.config.smoothingFactor = Float($0)
                        cropEngine?.config.transitionSmoothing = Float($0)
                    }
                ),
                range: 0.05...0.30,
                step: 0.01,
                format: percent
            )

            SettingsSliderRow(
                title: "Hold after loss",
                detail: "Keep the shot this long when the speaker is lost.",
                value: $shotComposer.config.targetHoldDuration,
                range: 0.25...2.0,
                step: 0.05,
                format: { String(format: "%.2f s", $0) }
            )

            SettingsRow(title: "Auto-pan speed") {
                Picker("Auto-pan speed", selection: Binding(
                    get: { ShotComposer.Config.AutoPanSpeed.nearest(to: shotComposer.config.autoPanSpeed) },
                    set: { shotComposer.config.autoPanSpeed = $0.rawValue }
                )) {
                    ForEach(ShotComposer.Config.AutoPanSpeed.allCases) { speed in
                        Text(speed.title).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            SettingsSliderRow(title: "Auto-pan height",
                              value: cgFloatBinding(\.autoPanHeight),
                              range: 0.20...0.80, step: 0.01, format: percent)

            SettingsSliderRow(title: "Stage side margin",
                              value: cgFloatBinding(\.stageHorizontalMargin),
                              range: 0.00...0.20, step: 0.01, format: percent)

            SettingsSliderRow(title: "Stage top / bottom margin",
                              value: cgFloatBinding(\.stageVerticalMargin),
                              range: 0.00...0.15, step: 0.01, format: percent)
        }
    }

    private func cgFloatBinding(_ keyPath: WritableKeyPath<ShotComposer.Config, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(shotComposer.config[keyPath: keyPath]) },
            set: { shotComposer.config[keyPath: keyPath] = CGFloat($0) }
        )
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    /// Recompute which preset (if any) the current values match, without
    /// re-applying a bundle, so it won't fight the slider that just changed.
    private func syncTuningPreset() {
        let matched = shotComposer.config.matchedPreset
        if shotComposer.config.tuningPreset != matched {
            shotComposer.config.tuningPreset = matched
        }
    }
}

private struct FeelPresetButton: View {
    let preset: ShotComposer.Config.TuningPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(preset.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isSelected ? AlfieColor.accentText : AlfieColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? AlfieColor.accentSoft : AlfieColor.controlFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? AlfieColor.accent : Color.clear, lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(preset.detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Director

/// SU-05 (AD-STYLE-UX): each kind of segment gets a feel (Pace, Wide shots,
/// When someone moves) instead of nine numbers. Every change saves itself.
struct DirectorSettingsPage: View {
    @ObservedObject var editor: DirectorFeelEditor
    @State private var showExactValues = false

    private static let segments: [SegmentType] = [.liveEvent, .presenter, .panel, .performance, .videoBreak]

    var body: some View {
        let segment = editor.selected
        let feel = editor.feel(for: segment)
        SettingsPage(title: "Director",
                     subtitle: "How Alfie paces each kind of segment. Pick a feel; exact values are optional.") {
            if !editor.message.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: editor.hasError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(editor.hasError ? AlfieColor.warning : AlfieColor.live)
                        .accessibilityHidden(true)
                    Text(editor.message)
                        .font(.system(size: 12))
                        .foregroundStyle(AlfieColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)
            }

            SettingsSectionLabel("Kinds of segment")
            SettingsCard {
                ForEach(Self.segments, id: \.self) { kind in
                    segmentRow(kind)
                }
            }
            SettingsFootnote("Live event is used when a show has no run sheet. The other kinds take effect once the show's run sheet says which segment is on.")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SettingsSectionLabel(segment.styleTitle)
                if feel == nil {
                    SettingsTag(text: "Custom")
                }
                Spacer(minLength: 0)
                if segment != .liveEvent, editor.hasOwnStyle(segment) {
                    Button("Use Live event's feel") { editor.followLiveEvent(segment) }
                        .buttonStyle(.link)
                        .padding(.top, 26)
                }
            }
            if segment != .liveEvent, !editor.hasOwnStyle(segment) {
                Text("Same as Live event. Change anything below to give \(segment.styleTitle) its own feel.")
                    .font(.system(size: 12))
                    .foregroundStyle(AlfieColor.secondaryText)
                    .padding(.leading, 4)
                    .padding(.bottom, 8)
            } else if feel == nil {
                Text("Exact values were changed by hand. Pick a feel to reset them.")
                    .font(.system(size: 12))
                    .foregroundStyle(AlfieColor.secondaryText)
                    .padding(.leading, 4)
                    .padding(.bottom, 8)
            }

            choiceGroup("Pace", columns: 3) {
                ForEach(DirectorFeel.Pace.allCases) { pace in
                    ChoiceTile(title: pace.title, detail: pace.detail, isSelected: feel?.pace == pace) {
                        editor.choose(pace: pace, for: segment)
                    }
                }
            }
            choiceGroup("Wide shots", columns: 3) {
                ForEach(DirectorFeel.WideShots.allCases) { wide in
                    ChoiceTile(title: wide.title, detail: wide.detail, isSelected: feel?.wideShots == wide) {
                        editor.choose(wideShots: wide, for: segment)
                    }
                }
            }
            choiceGroup("When someone moves", columns: 2) {
                ForEach(DirectorFeel.Movement.allCases) { movement in
                    ChoiceTile(title: movement.title, detail: movement.detail, isSelected: feel?.movement == movement) {
                        editor.choose(movement: movement, for: segment)
                    }
                }
            }

            SettingsSectionLabel("What three minutes could look like")
            DirectorRhythmStrip(style: editor.style(for: segment))

            exactValuesHeader
            if showExactValues {
                exactValuesCard(segment)
            }
        }
    }

    private func segmentRow(_ kind: SegmentType) -> some View {
        let isSelected = editor.selected == kind
        return Button {
            editor.selected = kind
        } label: {
            HStack(spacing: 12) {
                Text(kind.styleTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? AlfieColor.accentText : AlfieColor.text)
                Spacer(minLength: 8)
                Text(editor.summary(for: kind))
                    .font(.system(size: 12))
                    .foregroundStyle(AlfieColor.secondaryText)
                Image(systemName: isSelected ? "checkmark" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? AlfieColor.accentText : AlfieColor.tertiaryText)
                    .frame(width: 14)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(isSelected ? AlfieColor.accentSoft : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.styleTitle), \(editor.summary(for: kind))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choiceGroup<Content: View>(_ title: String, columns: Int,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                content()
            }
        }
    }

    private var exactValuesHeader: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showExactValues.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(showExactValues ? 90 : 0))
                Text("EXACT VALUES")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                Text("· editing these makes the feel Custom")
                    .font(.system(size: 12))
            }
            .foregroundStyle(AlfieColor.tertiaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
        .padding(.top, 26)
        .padding(.bottom, 8)
        .accessibilityLabel("Exact values")
        .accessibilityValue(showExactValues ? "Expanded" : "Collapsed")
    }

    @ViewBuilder
    private func exactValuesCard(_ segment: SegmentType) -> some View {
        if let issue = editor.exactValueIssue {
            Text(issue)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AlfieColor.warning)
                .padding(.leading, 4)
                .padding(.bottom, 8)
        }
        SettingsCard {
            ForEach(DirectorFeelEditor.Field.allCases) { field in
                SettingsRow(title: field.title, detail: field.detail) {
                    HStack(spacing: 10) {
                        SettingsValueText(field.format(editor.value(field, for: segment)))
                        Stepper(field.title, value: Binding(
                            get: { editor.value(field, for: segment) },
                            set: { editor.setValue($0, field, for: segment) }
                        ), in: field.range, step: field.step)
                        .labelsHidden()
                    }
                }
            }
            SettingsRow(title: "Cut while moving", detail: "Allow a cut while the subject is still moving.") {
                Toggle("Cut while moving", isOn: Binding(
                    get: { editor.style(for: segment).cutOnMotionAllowed },
                    set: { editor.setCutWhileMoving($0, for: segment) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }
}

private extension DirectorFeelEditor.Field {
    var title: String {
        switch self {
        case .minimumShot: "Minimum shot"
        case .preferredShot: "Preferred shot"
        case .softMaximumShot: "Soft maximum shot"
        case .wideCadence: "Wide shot every"
        case .repetitionWindow: "Repetition window"
        case .maximumMovement: "Still means under"
        case .settleTime: "Settle time"
        case .onAirMoveRate: "On-air move rate"
        }
    }

    var detail: String {
        switch self {
        case .minimumShot: "Never cut sooner than this."
        case .preferredShot: "The length Alfie aims for."
        case .softMaximumShot: "After this Alfie looks for a change. Never a forced cut."
        case .wideCadence: "A reminder to show the room, never a forced cut."
        case .repetitionWindow: "How long before the same shot is used again."
        case .maximumMovement: "Subject speed, in frame widths per second."
        case .settleTime: "How long someone must stay still."
        case .onAirMoveRate: "Fastest reframe on Program, in shot steps per second."
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .minimumShot, .preferredShot, .softMaximumShot: 0...600
        case .wideCadence: 5...600
        case .repetitionWindow: 0...1200
        case .maximumMovement: 0...1
        case .settleTime: 0...10
        case .onAirMoveRate: 0.05...2
        }
    }

    var step: Double {
        switch self {
        case .minimumShot, .preferredShot, .softMaximumShot: 1
        case .wideCadence, .repetitionWindow: 5
        case .maximumMovement: 0.01
        case .settleTime: 0.25
        case .onAirMoveRate: 0.05
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .minimumShot, .preferredShot, .softMaximumShot, .wideCadence, .repetitionWindow:
            String(format: "%.0f s", value)
        case .maximumMovement: String(format: "%.2f frame/s", value)
        case .settleTime: String(format: "%.2f s", value)
        case .onAirMoveRate: String(format: "%.2f steps/s", value)
        }
    }
}

/// One option in a feel group.
private struct ChoiceTile: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? AlfieColor.accentText : AlfieColor.text)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AlfieColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AlfieColor.accentSoft : AlfieColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? AlfieColor.accent : AlfieColor.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Three minutes of cuts for a style, from the real Director policy
/// (`DirectorRhythmPreview`, SU-06).
struct DirectorRhythmStrip: View {
    let style: DirectorStyle

    var body: some View {
        let blocks = DirectorRhythmPreview.shots(for: style)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let gaps = CGFloat(max(blocks.count - 1, 0)) * 2
                let unit = max(geo.size.width - gaps, 0) / DirectorRhythmPreview.span
                HStack(spacing: 2) {
                    ForEach(blocks) { block in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(block.isWide ? AlfieColor.tertiaryText.opacity(0.55) : AlfieColor.accent)
                            .frame(width: unit * block.length)
                    }
                }
            }
            .frame(height: 30)
            .accessibilityHidden(true)

            HStack(spacing: 16) {
                legend(color: AlfieColor.accent, title: "Close shot")
                legend(color: AlfieColor.tertiaryText.opacity(0.55), title: "Wide")
                Spacer(minLength: 0)
                Text(Self.summary(blocks))
                    .font(.system(size: 12))
                    .foregroundStyle(AlfieColor.secondaryText)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AlfieColor.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AlfieColor.separator))
        .accessibilityElement(children: .combine)
    }

    /// Cut count and the range of finished shot lengths (the last shot is
    /// cut off by the end of the preview).
    static func summary(_ shots: [DirectorRhythmPreview.Shot]) -> String {
        let finished = shots.dropLast().map(\.length)
        guard let shortest = finished.min(), let longest = finished.max() else {
            return "No cut in three minutes"
        }
        return String(format: "About %d cuts · shots %.0f–%.0f s", finished.count, shortest, longest)
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(.system(size: 12)).foregroundStyle(AlfieColor.secondaryText)
        }
    }
}

// MARK: - Detection & render

struct EngineSettingsPage: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var personDetector: PersonDetector

    var body: some View {
        SettingsPage(title: "Detection & render",
                     subtitle: "Engine settings. The defaults suit most shows.",
                     timing: .live) {
            SettingsSectionLabel("Person detection")
            SettingsCard {
                SettingsRow(title: "High accuracy",
                            detail: "More accurate but slower. Detection runs in short bursts from the Detect button.") {
                    Toggle("High accuracy", isOn: $personDetector.config.useHighAccuracy)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsSliderRow(
                    title: "Confidence threshold",
                    detail: "Ignore people detected below this confidence.",
                    value: Binding(
                        get: { Double(personDetector.config.confidenceThreshold) },
                        set: { personDetector.config.confidenceThreshold = Float($0) }
                    ),
                    range: 0.1...1.0,
                    step: 0.05,
                    format: { String(format: "%.0f%%", $0 * 100) }
                )
                SettingsRow(title: "Max people tracked") {
                    Stepper(value: $personDetector.config.maxPersons, in: 1...10) {
                        SettingsValueText("\(personDetector.config.maxPersons)")
                    }
                }
            }

            if let cropEngine = cameraManager.cropEngine {
                RenderSettingsCard(cropEngine: cropEngine, shotComposer: cameraManager.shotComposer)
            } else {
                SettingsSectionLabel("Render")
                SettingsCard {
                    SettingsRow(title: "Crop engine unavailable",
                                detail: "Metal crop controls are unavailable on this Mac or failed to initialize in the current session.")
                }
            }
        }
    }
}

private struct RenderSettingsCard: View {
    @ObservedObject var cropEngine: CropEngine
    @ObservedObject var shotComposer: ShotComposer

    private var resolutionOptions: [(String, CGSize)] {
        switch shotComposer.config.frameProfile {
        case .livestream:
            return []
        case .portrait:
            return [
                ("1080 × 1920 (Vertical HD)", CGSize(width: 1080, height: 1920)),
                ("720 × 1280 (Vertical SD)", CGSize(width: 720, height: 1280)),
                ("2160 × 3840 (Vertical 4K)", CGSize(width: 2160, height: 3840))
            ]
        }
    }

    var body: some View {
        SettingsSectionLabel("Render")
        SettingsCard {
            SettingsRow(title: "High quality", detail: "Better image quality, slightly more GPU.") {
                Toggle("High quality", isOn: $cropEngine.config.useHighQuality)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            SettingsRow(title: "Output resolution", detail: shotComposer.config.frameProfile.detail) {
                if shotComposer.config.frameProfile == .livestream {
                    HStack(spacing: 8) {
                        SettingsValueText("1920 × 1080")
                        SettingsTag(text: "Locked")
                    }
                } else {
                    Picker("Output resolution", selection: $cropEngine.config.outputSize) {
                        ForEach(resolutionOptions, id: \.0) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}

// MARK: - Diagnostics

struct DiagnosticsSettingsPage<SystemExtensionManager: SystemExtensionStatusProviding>: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var programOutput: ProgramOutputManager
    @ObservedObject var personDetector: PersonDetector
    @ObservedObject var shotComposer: ShotComposer
    @ObservedObject var systemExtensionManager: SystemExtensionManager
    @ObservedObject var shadowExportModel: DirectorShadowExportModel

    var body: some View {
        SettingsPage(title: "Diagnostics", subtitle: "Read-only. Values fill in while a show is running.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                tile("Detection", [
                    ("People", "\(personDetector.displayedStats.personsDetectedCount)"),
                    ("Last / avg", String(format: "%.1f / %.1f ms",
                                          personDetector.displayedStats.lastDetectionTime * 1000,
                                          personDetector.displayedStats.averageDetectionTime * 1000)),
                    ("Frames", "\(personDetector.displayedStats.totalFramesProcessed)")
                ])
                if let cropEngine = cameraManager.cropEngine {
                    CropStatsTile(cropEngine: cropEngine)
                }
                tile("Composer", [
                    ("Target", shotComposer.hasActiveTarget ? "Yes" : "No"),
                    ("Lock", shotComposer.activeTargetID == nil ? "None" : "Tracking"),
                    ("Override", shotComposer.isManualLockActive ? "Locked" : "Auto")
                ])
                tile("Program feed", [
                    ("Sent", "\(programOutput.framesSent)"),
                    ("Dropped", "\(programOutput.droppedFrames)"),
                    ("Drop rate", String(format: "%.0f/min", programOutput.dropRatePerMinute))
                ])
            }
            .padding(.top, 20)

            if !programOutput.stageLatencies.isEmpty {
                SettingsSectionLabel("Latency · last 5 s")
                SettingsCard {
                    ForEach(programOutput.stageLatencies, id: \.id) { latency in
                        SettingsRow(title: latency.stage.title) {
                            SettingsValueText(String(format: "%.1f ms", latency.averageDuration * 1000))
                        }
                    }
                }
            }

            if let cropEngine = cameraManager.cropEngine {
                SettingsSectionLabel("Crop")
                SettingsCard {
                    SettingsRow(title: "Manual crop") {
                        HStack(spacing: 8) {
                            Button("Reset to full frame") {
                                cropEngine.resetToFullFrame(aspect: shotComposer.normalizedAspect)
                            }
                            Button("Jump to target") {
                                cropEngine.jumpToTarget()
                            }
                        }
                    }
                }
            }

            SettingsSectionLabel("Bring-up checklist")
            SettingsCard {
                checkRow(title: "Virtual camera extension",
                         status: systemExtensionManager.badgeTitle,
                         detail: systemExtensionManager.summaryText,
                         level: systemExtensionManager.outputCheckLevel)
                ForEach(programOutput.bringUpChecks) { check in
                    checkRow(title: check.title, status: check.status, detail: check.detail, level: check.level)
                }
            }

            if !programOutput.sinkStatuses.isEmpty {
                SettingsSectionLabel("Sink health")
                SettingsCard {
                    ForEach(programOutput.sinkStatuses, id: \.id) { status in
                        SettingsRow(title: status.route.title, detail: "\(status.summary) \(status.detail)") {
                            Text(status.level.title)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(status.level.color)
                        }
                    }
                }
            }

            SettingsSectionLabel("Session log")
            SettingsCard {
                SettingsRow(title: "Recording to",
                            detail: "A CSV row every ~5 s while capture runs: memory, frame timings, dropped frames and thermal state.") {
                    SettingsValueText(programOutput.diagnosticsFileName ?? "Not capturing")
                }
                SettingsRow(title: "Thermal state") {
                    SettingsValueText(DiagnosticsLog.thermalStateName(ProcessInfo.processInfo.thermalState).capitalized)
                }
                SettingsRow(title: "Logs") {
                    Button("Reveal in Finder") { DiagnosticsLog.openInFinder() }
                }
            }

            SettingsSectionLabel("Shadow metadata export")
            DirectorShadowExportView(model: shadowExportModel)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AlfieColor.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AlfieColor.separator))
        }
    }

    private func tile(_ title: String, _ rows: [(String, String)]) -> some View {
        DiagnosticsTile(title: title, rows: rows)
    }

    private func checkRow(title: String, status: String, detail: String, level: OutputCheckLevel) -> some View {
        SettingsRow(title: title, detail: detail) {
            Text(status)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(level.color)
        }
    }
}

private struct CropStatsTile: View {
    @ObservedObject var cropEngine: CropEngine

    var body: some View {
        DiagnosticsTile(title: "Render", rows: [
            ("Last / avg", String(format: "%.2f / %.2f ms",
                                  cropEngine.stats.lastRenderTime * 1000,
                                  cropEngine.stats.averageRenderTime * 1000)),
            ("Frames", "\(cropEngine.stats.totalFramesRendered)"),
            ("Interpolating", cropEngine.isInterpolating ? "Yes" : "No")
        ])
    }
}

private struct DiagnosticsTile: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(AlfieColor.tertiaryText)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows, id: \.0) { row in
                Rectangle().fill(AlfieColor.separator).frame(height: 1)
                HStack {
                    Text(row.0)
                        .foregroundStyle(AlfieColor.secondaryText)
                    Spacer(minLength: 8)
                    Text(row.1)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AlfieColor.text)
                }
                .font(.system(size: 12))
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AlfieColor.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AlfieColor.separator))
    }
}
