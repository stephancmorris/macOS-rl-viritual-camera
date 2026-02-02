//
//  CinematicCoreXPCProtocol.swift
//  CinematicCore
//
//  Created by Stephan Morris on 2/3/2026.
//

import Foundation

/// XPC Protocol for communication between host app and system extension
/// Enables zero-copy IOSurface sharing for 4K video frames
@objc protocol CinematicCoreXPCProtocol {
    
    /// Send a video frame's IOSurface ID to the virtual camera extension
    /// - Parameters:
    ///   - surfaceID: The IOSurface identifier from CVPixelBuffer
    ///   - timestamp: Presentation timestamp in seconds (CMTime converted to Double)
    ///   - width: Frame width in pixels
    ///   - height: Frame height in pixels
    func sendVideoFrame(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32)
    
    /// Notify extension of capture session status changes
    /// - Parameter isRunning: Whether the capture session is active
    func updateCaptureStatus(isRunning: Bool)
    
    /// Ping to verify XPC connection is alive
    /// - Parameter reply: Completion handler that returns when connection is verified
    func ping(reply: @escaping () -> Void)
}

/// Constants for XPC service configuration
enum CinematicCoreXPC {
    /// Mach service name for XPC communication
    /// Must match the extension's Info.plist NSExtension > NSExtensionAttributes > NSExtensionMachServiceName
    static let machServiceName = "com.cinematiccore.extension"
    
    /// XPC connection configuration
    static let connectionInterruptionRetryDelay: TimeInterval = 1.0
    static let maxConnectionRetries = 5
}
