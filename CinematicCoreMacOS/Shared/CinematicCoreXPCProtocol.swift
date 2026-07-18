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
    /// Mach service name for XPC communication.
    /// Must match CMIOExtensionMachServiceName in the extension's Info.plist
    /// (both the NSExtensionAttributes and top-level CMIOExtension entries).
    ///
    /// MUST be prefixed by the shared app group
    /// "EPZDEPSV69.Morris.CinematicCoreMacOS" (i.e.
    /// $(TeamIdentifierPrefix)Morris.CinematicCoreMacOS in the entitlements):
    /// both processes are sandboxed, and the sandbox only allows mach-lookup /
    /// registration of names prefixed by one of the process's application
    /// groups. The previous un-prefixed name was denied by the sandbox, so the
    /// host's connection never verified and no frames crossed XPC.
    static let machServiceName = "EPZDEPSV69.Morris.CinematicCoreMacOS.extension"
    
    /// XPC connection configuration
    static let initialConnectionRetryDelay: TimeInterval = 1.0
    static let maxConnectionRetryDelay: TimeInterval = 30.0
}
