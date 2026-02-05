//
//  XPCConnectionManager.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/3/2026.
//

import Foundation
import os.log

/// Manages XPC connection to the Camera Extension
/// Handles connection lifecycle, retries, and error recovery
@MainActor
final class XPCConnectionManager {

    // MARK: - Properties

    private var connection: NSXPCConnection?
    private var connectionRetries = 0
    private let logger = Logger(subsystem: "com.cinematiccore.app", category: "XPC")
    private var noConnectionWarningCount = 0
    private let maxNoConnectionWarnings = 10
    
    var isConnected: Bool {
        connection != nil
    }
    
    // MARK: - Connection Management
    
    /// Establish XPC connection to the system extension
    func connect() {
        guard connection == nil else {
            logger.info("XPC connection already exists")
            return
        }
        
        logger.info("🔌 Establishing XPC connection to extension...")
        
        let newConnection = NSXPCConnection(serviceName: CinematicCoreXPC.machServiceName)
        newConnection.remoteObjectInterface = NSXPCInterface(with: CinematicCoreXPCProtocol.self)
        
        // Handle connection interruption (extension crashed or was killed)
        newConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.handleInterruption()
            }
        }
        
        // Handle connection invalidation (connection explicitly closed)
        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.handleInvalidation()
            }
        }
        
        connection = newConnection
        newConnection.resume()
        
        // Verify connection with ping
        verifyConnection()
    }
    
    /// Disconnect from the extension
    func disconnect() {
        logger.info("🔌 Disconnecting XPC connection...")
        connection?.invalidate()
        connection = nil
        connectionRetries = 0
    }
    
    // MARK: - Remote Proxy Access
    
    /// Get remote proxy for sending messages
    /// - Returns: Remote object proxy or nil if not connected
    func remoteProxy() -> CinematicCoreXPCProtocol? {
        guard let connection = connection else {
            // Only log the first N warnings to avoid spam
            if noConnectionWarningCount < maxNoConnectionWarnings {
                noConnectionWarningCount += 1
                logger.warning("Cannot get remote proxy - no connection (\(self.noConnectionWarningCount)/\(self.maxNoConnectionWarnings) warnings)")
            } else if noConnectionWarningCount == maxNoConnectionWarnings {
                noConnectionWarningCount += 1
                logger.warning("Cannot get remote proxy - suppressing further warnings")
            }
            return nil
        }

        // Reset warning count when we have a connection
        noConnectionWarningCount = 0

        return connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.logger.error("XPC proxy error: \(error.localizedDescription)")
        } as? CinematicCoreXPCProtocol
    }
    
    // MARK: - Connection Verification
    
    private func verifyConnection() {
        guard let proxy = remoteProxy() else {
            logger.error("Failed to get remote proxy")
            attemptReconnect()
            return
        }
        
        proxy.ping { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.logger.info("✓ XPC connection verified")
                self.connectionRetries = 0
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func handleInterruption() {
        logger.warning("⚠️ XPC connection interrupted")
        connection = nil
        attemptReconnect()
    }
    
    private func handleInvalidation() {
        logger.info("XPC connection invalidated")
        connection = nil
    }
    
    private func attemptReconnect() {
        guard connectionRetries < CinematicCoreXPC.maxConnectionRetries else {
            logger.error("❌ Max XPC reconnection attempts reached")
            return
        }
        
        connectionRetries += 1
        logger.info("Attempting XPC reconnection (\(self.connectionRetries)/\(CinematicCoreXPC.maxConnectionRetries))...")
        
        Task {
            try? await Task.sleep(for: .seconds(CinematicCoreXPC.connectionInterruptionRetryDelay))
            await connect()
        }
    }
}
