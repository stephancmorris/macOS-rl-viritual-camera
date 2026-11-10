//
//  XPCConnectionManager.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/3/2026.
//

import Foundation
import os.log
import Security

/// The code-signing requirement each side of the virtual-camera XPC link
/// demands of its peer: an Apple-issued certificate, the expected bundle
/// identifier, and the same team as this process. The service name is
/// app-group prefixed, but that only limits who can register it; this check
/// is what proves the peer is our extension (CR-016). The extension applies
/// the same rule to the host (CR-003). Kept in step with
/// `ExtensionSecurityPolicy` in CinematicCoreExtensionProvider.swift.
nonisolated enum XPCPeerRequirement {
    static let extensionIdentifier = "Morris.CinematicCoreMacOS.CinematicCoreExtension"

    /// The requirement text, or nil when either value could inject into it.
    static func requirement(identifier: String, teamID: String) -> String? {
        let teamOK = teamID.count == 10 && teamID.unicodeScalars.allSatisfy {
            ("A"..."Z").contains($0) || ("0"..."9").contains($0)
        }
        let identifierOK = !identifier.isEmpty && identifier.unicodeScalars.allSatisfy {
            ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-"
        }
        guard teamOK, identifierOK else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// The extension requirement for this build, or nil when this process has
    /// no team signature to compare against (an unsigned or ad-hoc build).
    static func forExtension() -> String? {
        guard let team = XPCSigningIdentity.ownTeamIdentifier() else { return nil }
        return requirement(identifier: extensionIdentifier, teamID: team)
    }
}

/// A bounded ping attempt. Scheduling is injectable; callback identity makes
/// cancelled/superseded deadlines inert even if their scheduler still fires.
@MainActor
final class XPCPingVerification {
    typealias Schedule = (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let schedule: Schedule
    private var pending: (generation: UInt64, attempt: UUID)?

    init(schedule: @escaping Schedule = { delay, fire in
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            fire()
        }
    }) {
        self.schedule = schedule
    }

    func begin(generation: UInt64, onTimeout: @escaping @MainActor (UInt64) -> Void) -> UUID {
        let attempt = UUID()
        pending = (generation, attempt)
        schedule(3) { [weak self] in
            guard let self, self.pending?.generation == generation,
                  self.pending?.attempt == attempt else { return }
            self.pending = nil
            onTimeout(generation)
        }
        return attempt
    }

    func acceptReply(generation: UInt64, attempt: UUID) -> Bool {
        guard pending?.generation == generation, pending?.attempt == attempt else { return false }
        pending = nil
        return true
    }

    func cancel() { pending = nil }
}

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
    private let verification: XPCPingVerification
    private(set) var connectionGeneration: UInt64 = 0
    private var reconnectTask: Task<Void, Never>?
    private var shouldMaintainConnection = false
    private var reconnectAttemptCount = 0
    private var nextReconnectDelay: TimeInterval?
    private let logger = Logger(subsystem: "com.alfie", category: "XPC")
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
    
    init(verificationSchedule: XPCPingVerification.Schedule? = nil) {
        if let verificationSchedule {
            verification = XPCPingVerification(schedule: verificationSchedule)
        } else {
            verification = XPCPingVerification()
        }
    }

    // MARK: - Connection Management
    
    /// Establish XPC connection to the system extension
    func connect() {
        logger.notice(
            "XPC connect requested; service=\(CinematicCoreXPC.machServiceName, privacy: .public); state=\(String(describing: self.connectionState), privacy: .public); shouldMaintain=\(self.shouldMaintainConnection, privacy: .public)"
        )
        AlfieDiagnosticsLog.append(
            "XPC",
            "connect requested service=\(CinematicCoreXPC.machServiceName) state=\(String(describing: connectionState)) shouldMaintain=\(shouldMaintainConnection)"
        )
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
        
        let newConnection = NSXPCConnection(
            machServiceName: CinematicCoreXPC.machServiceName,
            options: []
        )
        newConnection.remoteObjectInterface = NSXPCInterface(with: CinematicCoreXPCProtocol.self)

        // Only talk to a listener signed as our extension by our team. A
        // mismatched peer invalidates the connection before a surface id is
        // sent. Without a team signature there is nothing to verify against,
        // so refuse rather than connect unchecked.
        guard let requirement = XPCPeerRequirement.forExtension() else {
            let message = "This build has no team signature, so the virtual camera extension cannot be verified."
            logger.error("XPC connect refused: no team signature to verify the extension against")
            AlfieDiagnosticsLog.append("XPC", "connect refused: no team signature to verify the extension against")
            lastErrorDescription = message
            connectionState = .error(message)
            onStateChange?()
            return
        }
        newConnection.setCodeSigningRequirement(requirement)

        connectionGeneration &+= 1
        let generation = connectionGeneration

        // Handle connection interruption (extension crashed or was killed)
        newConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.connectionGeneration == generation else { return }
                self.handleInterruption()
            }
        }
        
        // Handle connection invalidation (connection explicitly closed)
        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.connectionGeneration == generation else { return }
                self.handleInvalidation()
            }
        }
        
        connection = newConnection
        newConnection.resume()
        
        // Verify connection with ping
        verifyConnection()
    }
    
    /// Disconnect from the extension
    func disconnect() {
        verification.cancel()
        logger.info("🔌 Disconnecting XPC connection...")
        shouldMaintainConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        connectionGeneration &+= 1
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
        verification.cancel()
        logger.notice(
            "XPC forceReconnect requested; service=\(CinematicCoreXPC.machServiceName, privacy: .public); state=\(String(describing: self.connectionState), privacy: .public); lastError=\(self.lastErrorDescription ?? "none", privacy: .public)"
        )
        AlfieDiagnosticsLog.append(
            "XPC",
            "forceReconnect requested service=\(CinematicCoreXPC.machServiceName) state=\(String(describing: connectionState)) lastError=\(lastErrorDescription ?? "none")"
        )
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
            connectionGeneration &+= 1
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

        let generation = connectionGeneration
        return connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                guard let self, self.connectionGeneration == generation else { return }
                self.verification.cancel()
                self.logger.error("XPC proxy error: \(error.localizedDescription)")
                AlfieDiagnosticsLog.append("XPC", "proxy error: \(error.localizedDescription)")
                self.lastErrorDescription = error.localizedDescription
                self.connectionState = .error(error.localizedDescription)
                self.onStateChange?()
                self.connectionGeneration &+= 1
                self.connection?.invalidate()
                self.connection = nil
                self.scheduleReconnect(reason: "remote proxy error")
            }
        } as? CinematicCoreXPCProtocol
    }
    
    // MARK: - Connection Verification
    
    private func verifyConnection() {
        logger.notice(
            "Verifying XPC connection with ping; service=\(CinematicCoreXPC.machServiceName, privacy: .public)"
        )
        AlfieDiagnosticsLog.append("XPC", "verifyConnection service=\(CinematicCoreXPC.machServiceName)")
        guard let proxy = remoteProxy() else {
            logger.error("Failed to get remote proxy")
            AlfieDiagnosticsLog.append("XPC", "verifyConnection failed: remote proxy unavailable")
            lastErrorDescription = "Failed to create the XPC remote proxy."
            connectionState = .error("Failed to create the XPC remote proxy.")
            onStateChange?()
            scheduleReconnect(reason: "proxy creation failure")
            return
        }
        
        let generation = connectionGeneration
        let attempt = verification.begin(generation: generation) { [weak self] expiredGeneration in
            guard let self, self.connectionGeneration == expiredGeneration, self.connection != nil else { return }
            let message = "The virtual camera connection check timed out."
            self.logger.error("XPC ping verification timed out")
            AlfieDiagnosticsLog.append("XPC", "ping verification timed out")
            self.connectionGeneration &+= 1
            self.connection?.invalidate()
            self.connection = nil
            self.lastErrorDescription = message
            self.connectionState = .error(message)
            self.scheduleReconnect(reason: "verification timeout")
        }
        proxy.ping { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.connectionGeneration == generation, self.connection != nil,
                      self.verification.acceptReply(generation: generation, attempt: attempt) else { return }
                self.logger.info("✓ XPC connection verified")
                AlfieDiagnosticsLog.append("XPC", "connection verified")
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
        verification.cancel()
        logger.warning("⚠️ XPC connection interrupted")
        AlfieDiagnosticsLog.append("XPC", "connection interrupted")
        connectionGeneration &+= 1
        connection?.invalidate()
        connection = nil
        lastErrorDescription = "The CMIO extension connection was interrupted."
        connectionState = .error("The CMIO extension connection was interrupted.")
        onStateChange?()
        scheduleReconnect(reason: "interruption")
    }
    
    private func handleInvalidation() {
        verification.cancel()
        logger.info("XPC connection invalidated")
        AlfieDiagnosticsLog.append("XPC", "connection invalidated")
        connection = nil

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

    private func formattedDelay(_ delay: TimeInterval) -> String {
        if delay >= 10 {
            return String(format: "%.0fs", delay)
        }

        return String(format: "%.1fs", delay)
    }
}
