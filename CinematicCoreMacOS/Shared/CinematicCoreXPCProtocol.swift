//
//  CinematicCoreXPCProtocol.swift
//  CinematicCore
//
//  Created by Stephan Morris on 2/3/2026.
//

import Foundation
import IOSurface
import Security

/// XPC Protocol for communication between host app and system extension
/// Enables zero-copy IOSurface sharing for 4K video frames
@objc protocol CinematicCoreXPCProtocol {

    /// Agree the frame transport before any frame is sent (F-03). The host
    /// sends `FrameTransport.surfaceObject`; the extension replies with the
    /// version it accepted, or `FrameTransport.refused`. An extension built
    /// before F-03 does not know this message and never replies, so the host
    /// sends it no frames.
    func negotiateFrameTransport(_ hostVersion: Int, reply: @escaping (Int) -> Void)

    /// Send a Program frame to the virtual camera extension. The IOSurface
    /// object crosses XPC by secure coding, so the extension receives its own
    /// reference to the surface rather than a global ID to look up.
    /// - Parameters:
    ///   - surface: The frame's IOSurface, from its CVPixelBuffer
    ///   - timestamp: Presentation timestamp in seconds (CMTime converted to Double)
    ///   - width: Frame width in pixels
    ///   - height: Frame height in pixels
    func sendVideoFrame(surface: IOSurface, timestamp: Double, width: Int32, height: Int32)

    /// The pre-F-03 message, which carried a global IOSurface ID. Kept only
    /// so a new extension can recognise an old host and refuse its frames
    /// with one clear log line. The host never sends it.
    func sendVideoFrame(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32)

    /// Notify extension of capture session status changes
    /// - Parameter isRunning: Whether the capture session is active
    func updateCaptureStatus(isRunning: Bool)
    
    /// Tell the extension what rate the host is producing frames at, so the
    /// extension's playout clock (the timer that drains the frame queue) can
    /// match it. The host freezes `ShowStandard.current` when output starts,
    /// then restores that same session rate after a reconnect. The reply
    /// acknowledges that the extension accepted one of its advertised rates.
    /// - Parameter frameRate: Exact playout frame rate in fps (e.g. 50,
    ///   60000/1001, 60)
    func updatePlayoutFrameRate(_ frameRate: Double, reply: @escaping (Bool) -> Void)
    
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

enum XPCSigningIdentity {
    /// Team identifier of this process, or nil when it is unsigned or ad-hoc
    /// signed. Each side of the XPC link reads its own signature.
    nonisolated static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
