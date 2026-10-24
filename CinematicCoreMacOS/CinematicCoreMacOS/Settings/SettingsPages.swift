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

struct DirectorSettingsPage: View {
    @ObservedObject var editor: DirectorStyleEditor

    var body: some View {
        let draft = editor.binding(for: editor.selected)
        SettingsPage(title: "Director",
                     subtitle: "Pace for each kind of segment. Live event is required. The level is never saved.") {
            SettingsCard {
                SettingsRow(title: "Style", detail: editor.message.isEmpty ? "Using the saved styles." : editor.message) {
                    if editor.hasError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AlfieColor.warning)
                            .accessibilityLabel("Style problem")
                    }
                }
                SettingsRow(title: "Segment") {
                    Picker("Segment", selection: $editor.selected) {
                        ForEach(SegmentType.allCases, id: \.self) { segment in
                            Text(segment.styleTitle).tag(segment)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.top, 20)

            SettingsSectionLabel("Shot length · \(editor.selected.styleTitle)")
            HStack(spacing: 12) {
                labelledField("Minimum", text: draft.minimumShotDuration)
                labelledField("Preferred", text: draft.preferredShotDuration)
                labelledField("Soft maximum", text: draft.softMaximumShotDuration)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AlfieColor.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AlfieColor.separator))

            SettingsSectionLabel("Rhythm")
            SettingsCard {
                fieldRow("Wide cadence", text: draft.wideCadence)
                fieldRow("Repetition window", text: draft.repetitionWindow)
            }

            SettingsSectionLabel("Movement")
            SettingsCard {
                fieldRow("Maximum movement", text: draft.maximumMovement)
                fieldRow("Settle time", text: draft.settleTime)
                fieldRow("On-air move rate", text: draft.onAirMoveRate)
                SettingsRow(title: "Cut while moving") {
                    Picker("Cut while moving", selection: cutChoice(draft)) {
                        Text("Not set").tag(CutChoice.notSet)
                        Text("No").tag(CutChoice.no)
                        Text("Yes").tag(CutChoice.yes)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            HStack {
                Spacer()
                Button("Save styles") { editor.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!editor.canSave)
            }
            .padding(.top, 16)
        }
    }

    private func labelledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AlfieColor.secondaryText)
            TextField(title, text: text, prompt: Text("Not set"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .accessibilityLabel("\(title) shot length")
        }
        .frame(maxWidth: .infinity)
    }

    private func fieldRow(_ title: String, text: Binding<String>) -> some View {
        SettingsRow(title: title) {
            TextField(title, text: text, prompt: Text("Not set"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 140)
                .accessibilityLabel(title)
        }
    }

    private func cutChoice(_ draft: Binding<DirectorStyleDraft>) -> Binding<CutChoice> {
        Binding(
            get: {
                switch draft.wrappedValue.cutOnMotionAllowed {
                case nil: .notSet
                case false: .no
                case true: .yes
                }
            },
            set: { choice in
                draft.wrappedValue.cutOnMotionAllowed = switch choice {
                case .notSet: nil
                case .no: false
                case .yes: true
                }
            })
    }

    private enum CutChoice: Hashable {
        case notSet, no, yes
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
