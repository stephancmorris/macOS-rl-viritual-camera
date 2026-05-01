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
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var settingsWindowController = SettingsWindowController()

    var body: some Scene {
        WindowGroup("Alfie") {
            ContentView(
                cameraManager: cameraManager,
                systemExtensionManager: systemExtensionManager,
                settingsWindowController: settingsWindowController
            )
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsWindow(
                cameraManager: cameraManager,
                systemExtensionManager: systemExtensionManager,
                controller: settingsWindowController
            )
        }
    }
}
