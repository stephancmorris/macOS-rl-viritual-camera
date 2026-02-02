//
//  main.swift
//  CinematicCoreExtension
//
//  Created by Stephan Morris on 2/2/2026.
//

import Foundation
import CoreMediaIO

let providerSource = CinematicCoreExtensionProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

CFRunLoopRun()
