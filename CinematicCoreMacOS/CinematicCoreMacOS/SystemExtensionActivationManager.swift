//
//  SystemExtensionActivationManager.swift
//  CinematicCoreMacOS
//
//  Created by Codex on 23/4/2026.
//

import AppKit
import Combine
import Foundation
import OSLog
import Security
import SwiftUI
import SystemExtensions

@MainActor
final class SystemExtensionActivationManager: NSObject, ObservableObject {
    struct FailureDetails: Equatable {
        enum RecoveryAction: Equatable {
            case retryInstall
            case openSystemSettings
        }

        let title: String
        let summary: String
        let detail: String
        let recoveryAction: RecoveryAction
    }

    enum Status: Equatable {
        case unknown
        case notInstalled
        case activationRequested
        case awaitingUserApproval
        case installed
        case failed(FailureDetails)
    }

    private enum SystemExtensionFailureCode: Int {
        case unknown = 1
        case missingEntitlement = 2
        case unsupportedParentBundleLocation = 3
        case extensionNotFound = 4
        case extensionMissingIdentifier = 5
        case duplicateExtensionIdentifier = 6
        case unknownExtensionCategory = 7
        case codeSignatureInvalid = 8
        case validationFailed = 9
        case forbiddenBySystemPolicy = 10
        case requestCanceled = 11
        case requestSuperseded = 12
        case authorizationRequired = 13
    }

    @Published private(set) var status: Status

    private let logger = Logger(
        subsystem: "com.alfie",
        category: "SystemExtensionActivation"
    )
    private let extensionIdentifier: String
    private let defaults: UserDefaults
    private let installDefaultsKey: String

    private var requestInFlight = false
    private var activationWaiters: [CheckedContinuation<Bool, Never>] = []
    private var requestKinds: [ObjectIdentifier: RequestKind] = [:]

    private enum RequestKind {
        case activation
        case properties
    }

    private enum PreflightFailure {
        case developerBuild(URL)
        case appNotInApplications(URL)
        case missingEmbeddedExtension(URL)
        case bundleIdentifierMismatch(expected: String, actual: String, bundleURL: URL)
        case missingHostEntitlement(URL)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.extensionIdentifier = Self.resolveBundledExtensionIdentifier()
        self.installDefaultsKey = "alfie.systemExtensionInstalled.\(extensionIdentifier)"
        self.status = .unknown

        super.init()

        Task { @MainActor in
            refreshInstalledState()
        }
    }

    var badgeTitle: String {
        switch status {
        case .unknown, .notInstalled:
            return "Install Required"
        case .activationRequested:
            return "Installing…"
        case .awaitingUserApproval:
            return "Approval Needed"
        case .installed:
            return "Extension Ready"
        case .failed(let details):
            return details.title
        }
    }

    var badgeSystemImage: String {
        switch status {
        case .unknown, .notInstalled:
            return "shippingbox"
        case .activationRequested:
            return "arrow.down.circle"
        case .awaitingUserApproval:
            return "exclamationmark.triangle"
        case .installed:
            return "checkmark.seal"
        case .failed:
            return "xmark.octagon"
        }
    }

    var badgeTint: Color {
        switch status {
        case .unknown, .notInstalled:
            return .orange
        case .activationRequested:
            return .blue
        case .awaitingUserApproval:
            return .yellow
        case .installed:
            return .green
        case .failed:
            return .red
        }
    }

    var summaryText: String {
        switch status {
        case .unknown, .notInstalled:
            return "Alfie needs to install its virtual camera extension before the session can start."
        case .activationRequested:
            return "The activation request has been submitted. Alfie is waiting for macOS to finish installing the extension."
        case .awaitingUserApproval:
            return "Approve Alfie in System Settings under Login Items & Extensions, then come back and start the session again."
        case .installed:
            return "The virtual camera extension is installed and ready for downstream apps."
        case .failed(let details):
            return details.summary
        }
    }

    var detailText: String {
        switch status {
        case .unknown:
            return "Checking the bundled extension status with macOS"
        case .notInstalled:
            return "Bundled extension: \(extensionIdentifier)"
        case .activationRequested:
            return "Installing \(extensionIdentifier)"
        case .awaitingUserApproval:
            return "System Settings → Login Items & Extensions"
        case .installed:
            return "Bundled extension: \(extensionIdentifier)"
        case .failed(let details):
            return details.detail
        }
    }

    var primaryActionTitle: String? {
        switch status {
        case .unknown, .notInstalled:
            return "Install Extension"
        case .awaitingUserApproval:
            return "Open System Settings"
        case .failed(let details):
            switch details.recoveryAction {
            case .retryInstall:
                return "Retry Install"
            case .openSystemSettings:
                return "Open System Settings"
            }
        case .activationRequested, .installed:
            return nil
        }
    }

    var primaryActionSystemImage: String {
        switch status {
        case .awaitingUserApproval:
            return "gearshape"
        case .failed(let details):
            switch details.recoveryAction {
            case .retryInstall:
                return "shippingbox"
            case .openSystemSettings:
                return "gearshape"
            }
        case .unknown, .notInstalled:
            return "shippingbox"
        case .activationRequested, .installed:
            return "shippingbox"
        }
    }

    var isInstallReady: Bool {
        if case .installed = status {
            return true
        }
        return false
    }

    func ensureInstalledForSessionStart() async -> Bool {
        logger.notice("ensureInstalledForSessionStart invoked while status = \(self.statusLogValue, privacy: .public)")
        AlfieDiagnosticsLog.append("SystemExtension", "ensureInstalledForSessionStart status=\(statusLogValue)")
        switch status {
        case .installed:
            return true
        case .awaitingUserApproval:
            logger.notice("Session start blocked while awaiting user approval")
            return false
        case .activationRequested:
            return await waitForActivationResolution()
        case .unknown, .notInstalled, .failed:
            submitActivationRequest()
            return await waitForActivationResolution()
        }
    }

    func triggerPrimaryAction() async {
        logger.notice(
            "Retry Install / primary extension action pressed while status = \(self.statusLogValue, privacy: .public)"
        )
        AlfieDiagnosticsLog.append("SystemExtension", "Retry Install pressed status=\(statusLogValue)")
        switch status {
        case .unknown, .notInstalled:
            _ = await ensureInstalledForSessionStart()
        case .failed(let details):
            switch details.recoveryAction {
            case .retryInstall:
                _ = await ensureInstalledForSessionStart()
            case .openSystemSettings:
                _ = openSystemSettings()
            }
        case .awaitingUserApproval:
            _ = openSystemSettings()
        case .activationRequested, .installed:
            break
        }
    }

    @discardableResult
    func openSystemSettings() -> Bool {
        let candidateURLs = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.LoginItems-Settings",
            "x-apple.systempreferences:"
        ]

        for candidate in candidateURLs {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                logger.notice("Opened System Settings using \(candidate, privacy: .public)")
                return true
            }
        }

        logger.error("Failed to open System Settings for system-extension approval")
        return false
    }

    private func submitActivationRequest() {
        guard !requestInFlight else {
            logger.notice("Ignoring duplicate activation request while one is already in flight")
            return
        }

        if let preflightFailure = preflightFailure() {
            let details = Self.failureDetails(for: preflightFailure)
            logger.error("System-extension preflight failed: \(details.detail, privacy: .public)")
            AlfieDiagnosticsLog.append("SystemExtension", "Preflight failed title=\(details.title) detail=\(details.detail)")
            markFailed(details)
            return
        }

        logger.notice(
            "Submitting activation request for \(self.extensionIdentifier, privacy: .public); appBundle=\(Bundle.main.bundleURL.path, privacy: .public); systemExtensionsDir=\(Self.systemExtensionsDirectoryURL().path, privacy: .public)"
        )
        AlfieDiagnosticsLog.append(
            "SystemExtension",
            "Submitting activation request identifier=\(extensionIdentifier) appBundle=\(Bundle.main.bundleURL.path) systemExtensionsDir=\(Self.systemExtensionsDirectoryURL().path)"
        )
        requestInFlight = true
        status = .activationRequested

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        requestKinds[ObjectIdentifier(request)] = .activation
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func refreshInstalledState() {
        logger.notice(
            "Refreshing system-extension status for \(self.extensionIdentifier, privacy: .public); appBundle=\(Bundle.main.bundleURL.path, privacy: .public)"
        )
        AlfieDiagnosticsLog.append(
            "SystemExtension",
            "Refreshing installed state identifier=\(extensionIdentifier) appBundle=\(Bundle.main.bundleURL.path)"
        )
        status = .unknown

        let request = OSSystemExtensionRequest.propertiesRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        requestKinds[ObjectIdentifier(request)] = .properties
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func waitForActivationResolution() async -> Bool {
        if case .installed = status {
            return true
        }

        if case .awaitingUserApproval = status {
            return false
        }

        if case .failed = status {
            return false
        }

        return await withCheckedContinuation { continuation in
            activationWaiters.append(continuation)
        }
    }

    private func resolveWaiters(with value: Bool) {
        let waiters = activationWaiters
        activationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: value)
        }
    }

    private func markInstalled() {
        logger.notice("System-extension status -> installed")
        AlfieDiagnosticsLog.append("SystemExtension", "Status -> installed")
        defaults.set(true, forKey: installDefaultsKey)
        status = .installed
        requestInFlight = false
        resolveWaiters(with: true)
    }

    private func markNotInstalled() {
        logger.notice("System-extension status -> notInstalled")
        AlfieDiagnosticsLog.append("SystemExtension", "Status -> notInstalled")
        defaults.set(false, forKey: installDefaultsKey)
        status = .notInstalled
    }

    private func markAwaitingUserApproval() {
        logger.notice("System-extension status -> awaitingUserApproval")
        AlfieDiagnosticsLog.append("SystemExtension", "Status -> awaitingUserApproval")
        defaults.set(false, forKey: installDefaultsKey)
        status = .awaitingUserApproval
        requestInFlight = false
        resolveWaiters(with: false)
    }

    private func markFailed(_ details: FailureDetails) {
        logger.error(
            "System-extension status -> failed; title=\(details.title, privacy: .public); summary=\(details.summary, privacy: .public); detail=\(details.detail, privacy: .public)"
        )
        AlfieDiagnosticsLog.append(
            "SystemExtension",
            "Status -> failed title=\(details.title) summary=\(details.summary) detail=\(details.detail)"
        )
        defaults.set(false, forKey: installDefaultsKey)
        status = .failed(details)
        requestInFlight = false
        resolveWaiters(with: false)
    }

    private var statusLogValue: String {
        switch status {
        case .unknown:
            return "unknown"
        case .notInstalled:
            return "notInstalled"
        case .activationRequested:
            return "activationRequested"
        case .awaitingUserApproval:
            return "awaitingUserApproval"
        case .installed:
            return "installed"
        case .failed(let details):
            return "failed(\(details.title))"
        }
    }

    private static func diagnosticSummary(for error: Error) -> String {
        let nsError = error as NSError
        var parts: [String] = []
        parts.append("domain=\(nsError.domain)")
        parts.append("code=\(nsError.code)")
        parts.append("description=\(nsError.localizedDescription)")

        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
            parts.append("reason=\(reason)")
        }
        if let suggestion = nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String, !suggestion.isEmpty {
            parts.append("suggestion=\(suggestion)")
        }
        if let debugDescription = nsError.userInfo[NSDebugDescriptionErrorKey] as? String, !debugDescription.isEmpty {
            parts.append("debug=\(debugDescription)")
        }

        var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        var depth = 1
        while let current = underlying, depth <= 3 {
            parts.append("underlying\(depth)=\(current.domain)(\(current.code)): \(current.localizedDescription)")
            underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }

        return parts.joined(separator: " | ")
    }

    private static func resolveBundledExtensionIdentifier() -> String {
        let fallbackIdentifier = "Morris.CinematicCoreMacOS.CinematicCoreExtension"
        let systemExtensionsURL = Self.systemExtensionsDirectoryURL()

        guard let enumerator = FileManager.default.enumerator(
            at: systemExtensionsURL,
            includingPropertiesForKeys: nil
        ) else {
            return fallbackIdentifier
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "systemextension",
                  let bundle = Bundle(url: url),
                  let bundleIdentifier = bundle.bundleIdentifier,
                  !bundleIdentifier.isEmpty else {
                continue
            }
            return bundleIdentifier
        }

        return fallbackIdentifier
    }

    private func preflightFailure() -> PreflightFailure? {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        if Self.isDeveloperBuildLocation(bundleURL) {
            return .developerBuild(bundleURL)
        }

        guard Self.isBundleInstalledInApplicationsDirectory(bundleURL) else {
            return .appNotInApplications(bundleURL)
        }

        let systemExtensionsURL = Self.systemExtensionsDirectoryURL()
        guard let extensionBundleURL = Self.firstEmbeddedSystemExtensionURL(in: systemExtensionsURL) else {
            return .missingEmbeddedExtension(systemExtensionsURL)
        }

        if let actualIdentifier = Bundle(url: extensionBundleURL)?.bundleIdentifier,
           actualIdentifier != extensionIdentifier {
            return .bundleIdentifierMismatch(
                expected: extensionIdentifier,
                actual: actualIdentifier,
                bundleURL: extensionBundleURL
            )
        }

        guard Self.hostAppCanInstallSystemExtensions(bundleURL) else {
            return .missingHostEntitlement(bundleURL)
        }

        return nil
    }

    private static func systemExtensionsDirectoryURL() -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("SystemExtensions", isDirectory: true)
    }

    private static func firstEmbeddedSystemExtensionURL(in directoryURL: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        for case let url as URL in enumerator where url.pathExtension == "systemextension" {
            return url
        }

        return nil
    }

    private static func isDeveloperBuildLocation(_ bundleURL: URL) -> Bool {
        let path = bundleURL.path
        return path.contains("/DerivedData/")
            || path.contains("/Build/Products/")
            || path.contains("/Xcode/Archives/")
    }

    private static func isBundleInstalledInApplicationsDirectory(_ bundleURL: URL) -> Bool {
        let applicationDirectories =
            FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
            + FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)

        return applicationDirectories.contains { applicationURL in
            let standardizedApplicationURL = applicationURL.standardizedFileURL
            let standardizedBundlePath = bundleURL.path
            let applicationPath = standardizedApplicationURL.path
            return standardizedBundlePath == applicationPath
                || standardizedBundlePath.hasPrefix(applicationPath + "/")
        }
    }

    private static func hostAppCanInstallSystemExtensions(_ bundleURL: URL) -> Bool {
        guard let signingInfo = signingInformation(for: bundleURL),
              let entitlements = signingInfo[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else {
            return false
        }

        return (entitlements["com.apple.developer.system-extension.install"] as? Bool) == true
    }

    private static func signingInformation(for bundleURL: URL) -> [String: Any]? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return nil
        }

        var signingInfo: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        )
        guard infoStatus == errSecSuccess,
              let info = signingInfo as? [String: Any] else {
            return nil
        }

        return info
    }

    private static func failureDetails(for preflightFailure: PreflightFailure) -> FailureDetails {
        switch preflightFailure {
        case .developerBuild(let bundleURL):
            return FailureDetails(
                title: "Developer Build",
                summary: "Virtual camera install is disabled for Xcode-run builds.",
                detail: "Current app location: \(bundleURL.path). Copy Alfie into /Applications or ~/Applications, relaunch it outside Xcode, then retry the virtual camera install.",
                recoveryAction: .retryInstall
            )
        case .appNotInApplications(let bundleURL):
            return FailureDetails(
                title: "Move Alfie to Applications",
                summary: "macOS installs system extensions only from an Applications folder.",
                detail: "Current app location: \(bundleURL.path). Move Alfie into /Applications or ~/Applications, then reopen it and retry the virtual camera install.",
                recoveryAction: .retryInstall
            )
        case .missingEmbeddedExtension(let directoryURL):
            return FailureDetails(
                title: "Extension Missing",
                summary: "The bundled virtual camera extension was not found inside the app.",
                detail: "Expected an embedded .systemextension under \(directoryURL.path). Verify the extension target is copied into Contents/Library/SystemExtensions in the built app product.",
                recoveryAction: .retryInstall
            )
        case .bundleIdentifierMismatch(let expected, let actual, let bundleURL):
            return FailureDetails(
                title: "Identifier Mismatch",
                summary: "The embedded virtual camera extension identifier does not match Alfie’s activation target.",
                detail: "Expected \(expected), found \(actual) in \(bundleURL.path). Align the extension bundle identifier with the host app’s activation request.",
                recoveryAction: .retryInstall
            )
        case .missingHostEntitlement(let bundleURL):
            return FailureDetails(
                title: "Missing Host Entitlement",
                summary: "The running Alfie app is not signed with system-extension install permission.",
                detail: "Current app location: \(bundleURL.path). Ensure the host app is signed with `com.apple.developer.system-extension.install`, then rebuild and relaunch Alfie from Applications.",
                recoveryAction: .retryInstall
            )
        }
    }
}

extension SystemExtensionActivationManager: SystemExtensionStatusProviding {
    var outputCheckLevel: OutputCheckLevel {
        switch status {
        case .installed:
            return .ok
        case .activationRequested, .unknown:
            return .info
        case .awaitingUserApproval, .notInstalled:
            return .warning
        case .failed:
            return .error
        }
    }
}

extension SystemExtensionActivationManager: @preconcurrency OSSystemExtensionRequestDelegate {
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.notice(
            "System extension activation requires user approval for \(self.extensionIdentifier, privacy: .public)"
        )
        AlfieDiagnosticsLog.append("SystemExtension", "Request needs user approval identifier=\(extensionIdentifier)")
        requestKinds.removeValue(forKey: ObjectIdentifier(request))
        markAwaitingUserApproval()
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        logger.error(
            "System extension request failed for \(self.extensionIdentifier, privacy: .public): \(Self.diagnosticSummary(for: error), privacy: .public)"
        )
        AlfieDiagnosticsLog.append(
            "SystemExtension",
            "Request failed identifier=\(extensionIdentifier) \(Self.diagnosticSummary(for: error))"
        )
        let kind = requestKinds.removeValue(forKey: ObjectIdentifier(request))
        switch kind {
        case .properties:
            logger.error(
                "System-extension properties request failed: \(Self.diagnosticSummary(for: error), privacy: .public)"
            )
            if defaults.bool(forKey: installDefaultsKey) {
                status = .installed
            } else {
                status = .notInstalled
            }
        case .activation, .none:
            switch Self.failureDisposition(for: error) {
            case .awaitingApproval:
                markAwaitingUserApproval()
            case .failed(let details):
                markFailed(details)
            }
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        logger.notice(
            "System extension request finished for \(self.extensionIdentifier, privacy: .public) with result \(String(describing: result), privacy: .public)"
        )
        AlfieDiagnosticsLog.append(
            "SystemExtension",
            "Request finished identifier=\(extensionIdentifier) result=\(String(describing: result))"
        )
        let kind = requestKinds.removeValue(forKey: ObjectIdentifier(request))
        switch kind {
        case .activation, .none:
            markInstalled()
        case .properties:
            if case .unknown = status {
                markNotInstalled()
            }
        }
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        logger.notice(
            "Replacing existing system extension \(String(describing: existing), privacy: .public) with \(String(describing: ext), privacy: .public)"
        )
        return .replace
    }

    func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        logger.notice("Found \(properties.count) system-extension properties for \(self.extensionIdentifier, privacy: .public)")
        requestKinds.removeValue(forKey: ObjectIdentifier(request))

        if properties.contains(where: { $0.bundleIdentifier == extensionIdentifier }) {
            markInstalled()
        } else if !requestInFlight {
            markNotInstalled()
        }
    }

    private enum FailureDisposition {
        case awaitingApproval
        case failed(FailureDetails)
    }

    private static func failureDisposition(for error: Error) -> FailureDisposition {
        let nsError = error as NSError
        let diagnosticCode = "\(nsError.domain) (\(nsError.code))"
        let underlyingDescription = (nsError.userInfo[NSLocalizedDescriptionKey] as? String)
            ?? nsError.localizedDescription
        let defaultDetail = "Diagnostics: \(diagnosticCode). \(underlyingDescription)"

        guard nsError.domain == OSSystemExtensionErrorDomain,
              let code = SystemExtensionFailureCode(rawValue: nsError.code) else {
            return .failed(
                FailureDetails(
                    title: "Install Failed",
                    summary: "macOS could not install the virtual camera extension.",
                    detail: defaultDetail,
                    recoveryAction: .retryInstall
                )
            )
        }

        switch code {
        case .missingEntitlement:
            return .failed(
                FailureDetails(
                    title: "Missing Entitlement",
                    summary: "Alfie is missing the system-extension entitlement needed to install the virtual camera.",
                    detail: "Diagnostics: \(diagnosticCode). Check the app and extension entitlements plus signing configuration in Xcode.",
                    recoveryAction: .retryInstall
                )
            )
        case .unsupportedParentBundleLocation:
            return .failed(
                FailureDetails(
                    title: "Bundle Layout Problem",
                    summary: "macOS rejected the app bundle layout for the virtual camera extension.",
                    detail: "Diagnostics: \(diagnosticCode). Check how the system extension is embedded inside the app bundle.",
                    recoveryAction: .retryInstall
                )
            )
        case .extensionNotFound:
            return .failed(
                FailureDetails(
                    title: "Extension Missing",
                    summary: "Alfie could not find the bundled virtual camera extension inside the app.",
                    detail: "Diagnostics: \(diagnosticCode). Verify the extension target is embedded in the built app product.",
                    recoveryAction: .retryInstall
                )
            )
        case .extensionMissingIdentifier:
            return .failed(
                FailureDetails(
                    title: "Identifier Missing",
                    summary: "The bundled virtual camera extension does not declare a valid bundle identifier.",
                    detail: "Diagnostics: \(diagnosticCode). Check the extension Info.plist and product bundle identifier settings.",
                    recoveryAction: .retryInstall
                )
            )
        case .duplicateExtensionIdentifier:
            return .failed(
                FailureDetails(
                    title: "Duplicate Identifier",
                    summary: "macOS found more than one bundled extension using the same identifier.",
                    detail: "Diagnostics: \(diagnosticCode). Remove duplicate copies of the extension from the app bundle or build products.",
                    recoveryAction: .retryInstall
                )
            )
        case .unknownExtensionCategory:
            return .failed(
                FailureDetails(
                    title: "Unknown Extension Type",
                    summary: "macOS could not recognize the virtual camera extension category.",
                    detail: "Diagnostics: \(diagnosticCode). Verify the extension point identifier and CMIO system-extension configuration.",
                    recoveryAction: .retryInstall
                )
            )
        case .codeSignatureInvalid:
            return .failed(
                FailureDetails(
                    title: "Signing Invalid",
                    summary: "macOS rejected the virtual camera extension because the code signature is invalid.",
                    detail: "Diagnostics: \(diagnosticCode). Build Alfie with a valid signing identity for both the host app and the system extension.",
                    recoveryAction: .retryInstall
                )
            )
        case .validationFailed:
            return .failed(
                FailureDetails(
                    title: "Validation Failed",
                    summary: "macOS rejected the virtual camera extension during validation.",
                    detail: "Diagnostics: \(diagnosticCode). This usually means signing, entitlements, or bundle metadata do not match macOS system-extension requirements.",
                    recoveryAction: .retryInstall
                )
            )
        case .forbiddenBySystemPolicy, .authorizationRequired:
            return .awaitingApproval
        case .requestCanceled:
            return .failed(
                FailureDetails(
                    title: "Install Canceled",
                    summary: "The virtual camera installation was canceled before it could finish.",
                    detail: "Diagnostics: \(diagnosticCode). You can retry installation from Alfie.",
                    recoveryAction: .retryInstall
                )
            )
        case .requestSuperseded:
            return .failed(
                FailureDetails(
                    title: "Install Replaced",
                    summary: "A newer install request replaced the current virtual camera activation attempt.",
                    detail: "Diagnostics: \(diagnosticCode). Retry once to submit a fresh activation request.",
                    recoveryAction: .retryInstall
                )
            )
        case .unknown:
            return .failed(
                FailureDetails(
                    title: "Install Failed",
                    summary: "macOS could not install the virtual camera extension.",
                    detail: defaultDetail,
                    recoveryAction: .retryInstall
                )
            )
        }
    }

    private static func userFacingErrorMessage(for error: Error) -> String {
        switch failureDisposition(for: error) {
        case .awaitingApproval:
            return "Approve Alfie in System Settings under Login Items & Extensions, then try again."
        case .failed(let details):
            return details.summary
        }
    }
}
