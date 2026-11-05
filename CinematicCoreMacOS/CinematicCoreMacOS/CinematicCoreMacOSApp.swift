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
            AlfieCommands(fallbackStop: show.isAnyChannelLive ? AlfieCommandAction(perform: {
                cameraManager.programOutput.noteDiagnostics("stopped via hotkey")
                show.stopShow(origin: .operatorUI)
            }) : nil)
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
