//
//  SettingsWindow.swift
//  CinematicCoreMacOS
//
//  Created by Codex on 4/27/2026.
//
//  Settings are grouped by what the operator is doing (Show, Framing,
//  Advanced) rather than by engine module. Read-only numbers live on the
//  Diagnostics page, so every other page holds only things you can change.
//

import Combine
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case show
    case output
    case framing
    case director
    case engine
    case diagnostics

    var id: String { rawValue }

    /// The pages this build shows. Director is hidden until the Director runs
    /// in this build (SU-5).
    static var available: [SettingsTab] {
        allCases.filter { $0 != .director || DeveloperFlags.runDirectorShadow }
    }

    enum Group: String, CaseIterable, Identifiable {
        case show = "Show"
        case framing = "Framing"
        case advanced = "Advanced"

        var id: String { rawValue }

        var tabs: [SettingsTab] {
            SettingsTab.available.filter { $0.group == self }
        }
    }

    var group: Group {
        switch self {
        case .general, .show, .output: return .show
        case .framing, .director: return .framing
        case .engine, .diagnostics: return .advanced
        }
    }

    var title: String {
        switch self {
        case .general: return "General"
        case .show: return "Show & cameras"
        case .output: return "Output"
        case .framing: return "Auto-framing"
        case .director: return "Director"
        case .engine: return "Detection & render"
        case .diagnostics: return "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .show: return "video"
        case .output: return "dot.radiowaves.left.and.right"
        case .framing: return "person.crop.rectangle"
        case .director: return "film.stack"
        case .engine: return "cpu"
        case .diagnostics: return "waveform.path.ecg"
        }
    }

    /// Words a search in the sidebar matches, beyond the title.
    var keywords: [String] {
        switch self {
        case .general:
            return ["appearance", "theme", "light", "dark", "system", "build", "version", "gpu", "extension"]
        case .show:
            return ["mode", "single cam", "multi cam", "webcam", "show standard", "1080p50", "atem", "built-in camera", "testing"]
        case .output:
            return ["route", "port", "hdmi", "usb-c", "display", "virtual camera", "reconnect", "focus", "extension"]
        case .framing:
            return ["composer", "feel", "preset", "steady", "band", "balanced", "slow pan", "fast follow", "locked down",
                    "frame profile", "portrait", "livestream", "headroom", "smoothing", "responsiveness", "spring",
                    "hold", "auto pan", "margin", "deadzone"]
        case .director:
            return ["style", "segment", "shot length", "cadence", "repetition", "movement", "settle", "cut"]
        case .engine:
            return ["detection", "accuracy", "confidence", "max persons", "people", "quality", "resolution", "crop", "render"]
        case .diagnostics:
            return ["stats", "statistics", "frames", "dropped", "latency", "logs", "thermal", "checklist", "sink",
                    "shadow", "export", "metadata", "reset to full frame", "jump to target"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return title.lowercased().contains(query) || keywords.contains { $0.contains(query) }
    }
}

final class SettingsWindowController: ObservableObject {
    @Published var selectedTab: SettingsTab = .framing

    func open(_ tab: SettingsTab) {
        selectedTab = tab
    }
}

struct SettingsWindow: View {
    @ObservedObject var cameraManager: CameraManager
    /// Owns the operator mode and built-in camera testing.
    @ObservedObject var show: ShowCoordinator
    @ObservedObject var systemExtensionManager: SystemExtensionActivationManager
    @ObservedObject var controller: SettingsWindowController
    var onDirectorPreferencesChanged: (DirectorPreferences) -> Void = { _ in }
    var shadowLogProvider: () -> DirectorShadowLog? = { nil }
    @StateObject private var shadowExportModel = DirectorShadowExportModel()
    @StateObject private var directorEditor = DirectorFeelEditor.makeForSettings()
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(SettingsTab.Group.allCases) { group in
                    let tabs = group.tabs.filter { $0.matches(searchText) }
                    if !tabs.isEmpty {
                        Section {
                            ForEach(tabs) { tab in
                                Label(tab.title, systemImage: tab.systemImage)
                                    .tag(tab)
                            }
                        } header: {
                            Text(group.rawValue.uppercased())
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundStyle(AlfieColor.tertiaryText)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search settings")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            page(controller.selectedTab)
                .navigationTitle(controller.selectedTab.title)
        }
        .frame(minWidth: 820, idealWidth: 960, minHeight: 600, idealHeight: 720)
        .onAppear {
            directorEditor.onPreferencesChanged = onDirectorPreferencesChanged
            shadowExportModel.logProvider = shadowLogProvider
        }
    }

    /// The sidebar can report no selection; the window always shows a page.
    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { controller.selectedTab },
            set: { if let tab = $0 { controller.selectedTab = tab } }
        )
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsPage(systemExtensionManager: systemExtensionManager)
        case .show:
            ShowSettingsPage(cameraManager: cameraManager, show: show)
        case .output:
            OutputSettingsPage(
                programOutput: cameraManager.programOutput,
                systemExtensionManager: systemExtensionManager
            )
        case .framing:
            FramingSettingsPage(shotComposer: cameraManager.shotComposer, cropEngine: cameraManager.cropEngine)
        case .director:
            DirectorSettingsPage(editor: directorEditor)
        case .engine:
            EngineSettingsPage(cameraManager: cameraManager, personDetector: cameraManager.personDetector)
        case .diagnostics:
            DiagnosticsSettingsPage(
                cameraManager: cameraManager,
                programOutput: cameraManager.programOutput,
                personDetector: cameraManager.personDetector,
                shotComposer: cameraManager.shotComposer,
                systemExtensionManager: systemExtensionManager,
                shadowExportModel: shadowExportModel
            )
        }
    }
}

#Preview {
    let show = ShowCoordinator()
    SettingsWindow(
        cameraManager: show.channelA,
        show: show,
        systemExtensionManager: SystemExtensionActivationManager(),
        controller: SettingsWindowController()
    )
}
