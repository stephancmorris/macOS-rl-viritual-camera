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

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Properties

    private var connection: NSXPCConnection?
    private var reconnectTask: Task<Void, Never>?
    private var shouldMaintainConnection = false
    private var reconnectAttemptCount = 0
    private var nextReconnectDelay: TimeInterval?
    private var suppressNextInvalidationReconnect = false
    private let logger = Logger(subsystem: "com.cinematiccore.app", category: "XPC")
    private var noConnectionWarningCount = 0
    private let maxNoConnectionWarnings = 10

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var lastErrorDescription: String?
    var onStateChange: (() -> Void)?
    
    var isConnected: Bool {
        connection != nil
    }

    var canReconnect: Bool {
        shouldMaintainConnection
    }

    var reconnectStatusDescription: String? {
        if let delay = nextReconnectDelay {
            return "Retry \(reconnectAttemptCount) scheduled in \(formattedDelay(delay))."
        }

        if reconnectAttemptCount > 0, shouldMaintainConnection {
            return "Reconnect attempts: \(reconnectAttemptCount)."
        }

        return nil
    }
    
    // MARK: - Connection Management
    
    /// Establish XPC connection to the system extension
    func connect() {
        shouldMaintainConnection = true
        reconnectTask?.cancel()
        reconnectTask = nil
        nextReconnectDelay = nil

        guard connection == nil else {
            logger.info("XPC connection already exists")
            onStateChange?()
            return
        }
        
        logger.info("🔌 Establishing XPC connection to extension...")
        connectionState = .connecting
        lastErrorDescription = nil
        onStateChange?()
        
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
        shouldMaintainConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.invalidate()
        connection = nil
        reconnectAttemptCount = 0
        nextReconnectDelay = nil
        connectionState = .disconnected
        lastErrorDescription = nil
        onStateChange?()
    }

    /// Force an immediate reconnect attempt without waiting for backoff.
    func forceReconnect() {
        guard shouldMaintainConnection else {
            connect()
            return
        }

        logger.info("Forcing immediate XPC reconnect")
        reconnectTask?.cancel()
        reconnectTask = nil
        nextReconnectDelay = nil
        reconnectAttemptCount = 0

        if let connection {
            suppressNextInvalidationReconnect = true
            self.connection = nil
            connection.invalidate()
        }

        connectionState = .connecting
        onStateChange?()
        connect()
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
            Task { @MainActor in
                self?.logger.error("XPC proxy error: \(error.localizedDescription)")
                self?.lastErrorDescription = error.localizedDescription
                self?.connectionState = .error(error.localizedDescription)
                self?.onStateChange?()
                self?.scheduleReconnect(reason: "remote proxy error")
            }
        } as? CinematicCoreXPCProtocol
    }
    
    // MARK: - Connection Verification
    
    private func verifyConnection() {
        guard let proxy = remoteProxy() else {
            logger.error("Failed to get remote proxy")
            lastErrorDescription = "Failed to create the XPC remote proxy."
            connectionState = .error("Failed to create the XPC remote proxy.")
            onStateChange?()
            scheduleReconnect(reason: "proxy creation failure")
            return
        }
        
        proxy.ping { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.logger.info("✓ XPC connection verified")
                self.reconnectAttemptCount = 0
                self.nextReconnectDelay = nil
                self.reconnectTask = nil
                self.lastErrorDescription = nil
                self.connectionState = .connected
                self.onStateChange?()
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func handleInterruption() {
        logger.warning("⚠️ XPC connection interrupted")
        connection = nil
        lastErrorDescription = "The CMIO extension connection was interrupted."
        connectionState = .error("The CMIO extension connection was interrupted.")
        onStateChange?()
        scheduleReconnect(reason: "interruption")
    }
    
    private func handleInvalidation() {
        logger.info("XPC connection invalidated")
        connection = nil
        if suppressNextInvalidationReconnect {
            suppressNextInvalidationReconnect = false
            connectionState = shouldMaintainConnection ? .connecting : .disconnected
            onStateChange?()
            return
        }

        if shouldMaintainConnection {
            lastErrorDescription = "The CMIO extension connection was invalidated."
            connectionState = .error("The CMIO extension connection was invalidated.")
            onStateChange?()
            scheduleReconnect(reason: "invalidation")
            return
        }

        connectionState = .disconnected
        onStateChange?()
    }

    private func scheduleReconnect(reason: String) {
        guard shouldMaintainConnection else {
            logger.info("Skipping reconnect scheduling because maintenance is disabled")
            return
        }

        guard reconnectTask == nil else {
            logger.info("Reconnect already scheduled after \(reason, privacy: .public)")
            return
        }

        reconnectAttemptCount += 1
        let delay = min(
            CinematicCoreXPC.initialConnectionRetryDelay * pow(2.0, Double(max(0, reconnectAttemptCount - 1))),
            CinematicCoreXPC.maxConnectionRetryDelay
        )
        nextReconnectDelay = delay
        logger.info(
            "Scheduling XPC reconnect attempt \(self.reconnectAttemptCount) in \(delay, privacy: .public)s after \(reason, privacy: .public)"
        )
        onStateChange?()

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            await MainActor.run {
                guard self.shouldMaintainConnection else {
                    self.reconnectTask = nil
                    self.nextReconnectDelay = nil
                    self.onStateChange?()
                    return
                }

                self.reconnectTask = nil
                self.nextReconnectDelay = nil
                self.connect()
            }
        }
    }

    private func formattedDelay(_ delay: TimeInterval) -> String {
        if delay >= 10 {
            return String(format: "%.0fs", delay)
        }

        return String(format: "%.1fs", delay)
    }
}
