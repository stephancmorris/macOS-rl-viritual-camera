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

    var body: some Scene {
        WindowGroup {
            ContentView(systemExtensionManager: systemExtensionManager)
        }
    }
}
