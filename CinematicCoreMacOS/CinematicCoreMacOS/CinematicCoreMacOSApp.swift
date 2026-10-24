//
//  CinematicCoreMacOSApp.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/2/2026.
//

import SwiftUI

@main
struct CinematicCoreMacOSApp: App {
    @StateObject private var systemExtensionManager = SystemExtensionActivationManager()
    /// Owns the single program output and the channels.
    @StateObject private var show: ShowCoordinator
    /// Always derive A from the retained show. Independent StateObject storage
    /// for this alias could preserve a camera from a different show instance.
    private var cameraManager: CameraManager { show.channelA }
    @StateObject private var settingsWindowController = SettingsWindowController()

    init() {
        // StateObject defers this factory until its retained storage needs an
        // instance. Recreating the App value must not construct or start a
        // second show whose camera/output can escape into another scene.
        _show = StateObject(wrappedValue: Self.makeShow())
    }

    private static func makeShow() -> ShowCoordinator {
        let show = ShowCoordinator()
        show.startDirectorShadow()
        #if DEBUG
        DebugLaunchHooks.startWindowDumps()
        #endif
        return show
    }

    var body: some Scene {
        WindowGroup("Alfie") {
            ContentView(
                cameraManager: cameraManager,
                systemExtensionManager: systemExtensionManager,
                settingsWindowController: settingsWindowController,
                show: show
            )
            .onAppear { AppAppearance.current.apply() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // A real menu command, not just a key handler on the button. Two
            // reasons: it works wherever focus sits inside the app, and macOS
            // lets the operator rebind it themselves in System Settings →
            // Keyboard → Keyboard Shortcuts → App Shortcuts, which only works
            // for named menu items. No rebuild needed to change the combo.
            //
            // ⌘⌥⇧S is deliberately awkward: this kills a live program feed, so
            // it must be impossible to hit by accident mid-show.
            CommandMenu("Session") {
                Button("Stop Session") {
                    cameraManager.programOutput.noteDiagnostics("stopped via hotkey")
                    // Show-level Stop: stops every input, not just camera A.
                    show.stopShow(origin: .operatorUI)
                }
                .keyboardShortcut("s", modifiers: [.command, .option, .shift])
                .disabled(!show.isAnyChannelLive)
            }
        }

        Settings {
            SettingsWindow(
                cameraManager: cameraManager,
                show: show,
                systemExtensionManager: systemExtensionManager,
                controller: settingsWindowController,
                onDirectorPreferencesChanged: { [show] in show.directorPreferencesChanged($0) },
                shadowLogProvider: { [show] in show.shadowLogForExport }
            )
        }

        #if DEBUG
        // Multiview component gallery (Window menu), gated inside the scene by
        // DeveloperFlags.exposeMultiviewGallery. Not compiled into Release.
        MultiviewGalleryScene()
        #endif
    }
}
