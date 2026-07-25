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
                    cameraManager.stopCapture()
                }
                .keyboardShortcut("s", modifiers: [.command, .option, .shift])
                .disabled(!cameraManager.isRunning)
            }
        }

        Settings {
            SettingsWindow(
                cameraManager: cameraManager,
                systemExtensionManager: systemExtensionManager,
                controller: settingsWindowController
            )
        }
    }
}
