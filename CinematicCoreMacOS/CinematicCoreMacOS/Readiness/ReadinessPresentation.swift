import Foundation

/// Operator copy for the existing three-state readiness model. This does not
/// change readiness or perform a recovery; transient prompt state stays in UI.
nonisolated struct ReadinessRowPresentation: Equatable {
    let key: String
    let title: String
    let status: String
    let explanation: String
    let actionTitle: String?
    let blockingInstruction: String
    let symbol: String

    init(row: ReadinessModel.Row, inputs: ReadinessModel.Inputs, requestingPermission: Bool = false) {
        key = String(describing: row.id)
        title = row.id == .virtualCamera ? "Alfie camera" : row.id.title
        let waiting = row.state == .waiting || (row.id == .cameraAccess && requestingPermission)
        status = waiting ? "Waiting" : row.state == .ready ? "Ready" : "Action needed"
        symbol = waiting ? "hourglass" : row.state == .ready ? "checkmark.circle.fill" : "exclamationmark.circle"
        switch row.action {
        case .requestCameraAccess: actionTitle = requestingPermission ? nil : "Allow camera access"
        case .openCameraPrivacySettings: actionTitle = "Open camera settings"
        case .installVirtualCamera: actionTitle = "Install Alfie camera"
        case .openExtensionSettings: actionTitle = "Open extension settings"
        case .chooseOutput: actionTitle = "Choose output…"
        case nil: actionTitle = nil
        }
        switch row.id {
        case .cameraAccess:
            if requestingPermission {
                explanation = "Answer the camera access prompt to continue."
                blockingInstruction = "Answer the camera access prompt."
            } else {
                switch inputs.cameraAccess {
                case .authorized: explanation = "Alfie can use your cameras."
                case .notDetermined: explanation = "Alfie needs camera access to frame your shot and send Program video."
                case .denied: explanation = "Allow Alfie to use cameras in System Settings."
                case .restricted: explanation = "Camera access is restricted on this Mac. Check System Settings; you may need your administrator."
                case .unknown: explanation = "Alfie cannot check camera access. Check System Settings."
                }
                blockingInstruction = inputs.cameraAccess == .notDetermined
                    ? "Allow camera access above." : "Check camera access in System Settings."
            }
        case .virtualCamera:
            switch inputs.extensionStatus {
            case .notInstalled: explanation = "Install Alfie camera to use Program video in another app."
            case .unknown: explanation = "Alfie camera has not been confirmed installed."
            case .activationRequested: explanation = "Installing Alfie camera…"
            case .awaitingUserApproval: explanation = "Approve Alfie camera in System Settings."
            case .installed: explanation = "Alfie camera is installed."
            case .failed(.retryInstall): explanation = "Alfie camera could not be installed. Try again."
            case .failed(.openSystemSettings): explanation = "Check Alfie camera approval in System Settings."
            }
            if row.action == .openExtensionSettings { blockingInstruction = "Check Alfie camera in System Settings." }
            else if row.state == .waiting { blockingInstruction = "Wait for Alfie camera to finish installing." }
            else { blockingInstruction = "Install Alfie camera above." }
        case .programOutput:
            let output = Self.outputName(inputs.effectiveRoute)
            switch row.state {
            case .missing: explanation = "Choose an available Program output."
            case .waiting: explanation = "Preparing \(output)…"
            case .ready: explanation = "Program will go to \(output)."
            }
            blockingInstruction = row.state == .waiting
                ? "Wait for Program output to finish preparing." : "Choose a Program output above."
        }
    }

    var accessibilityLabel: String { "\(title). \(status). \(explanation)" }

    static func outputName(_ route: ProgramOutputManager.Route) -> String {
        switch route {
        case .virtualCamera: return "Alfie camera"
        case .display: return "Direct output"
        case .rehearsal: return "Rehearsal"
        }
    }
}

nonisolated enum StoppedSessionCopy {
    static func line(endedAt: Date?, duration: TimeInterval?, route: ProgramOutputManager.Route,
                     locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let off: String
        switch route {
        case .virtualCamera: off = "Alfie camera is off."
        case .display: off = "Program output is off."
        case .rehearsal: off = "Rehearsal cameras are off."
        }
        guard let endedAt else { return off }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let elapsed = duration.map { " after \(Self.duration($0))" } ?? ""
        return "Session ended \(formatter.string(from: endedAt))\(elapsed). \(off)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes == 0 { return "less than a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let remainder = minutes % 60
        return remainder == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(remainder) min"
    }
}
