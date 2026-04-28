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

    var body: some Scene {
        WindowGroup("Alfie") {
            ContentView(
                cameraManager: cameraManager,
                systemExtensionManager: systemExtensionManager
            )
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsWindow(cameraManager: cameraManager)
        }
    }
}
