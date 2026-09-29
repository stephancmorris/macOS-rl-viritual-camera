//
//  ShowSetupModel.swift
//  CinematicCoreMacOS
//
//  Show setup state (SHOW-SETUP): standard, Program output, which camera
//  goes in slots A and B, and the pair-check result shown for that
//  configuration. A plain value: the live adapter (LiveShowSetup.swift) and
//  the gallery (SetupDemo.swift) both drive it. It never opens a camera.
//
//  The engine can only measure a pair while both channels run, so the pair
//  check shows the most relevant STORED admission record for this Mac, show
//  standard, route and pair of camera models. Delivered size and mode are
//  only known after Start, so they are not part of the match.
//

import Foundation

struct ShowSetupModel: Equatable {

    // MARK: Types

    /// A present capture device, by its stable unique ID.
    struct Device: Identifiable, Equatable, Hashable {
        let uniqueID: String
        let name: String
        /// AVCaptureDevice.modelID: what an admission fingerprint records.
        let modelID: String
        var id: String { uniqueID }
    }

    /// The Mac an admission record must have been measured on.
    struct Machine: Equatable {
        var model: String
        var osVersion: String
    }

    /// Why a slot asks for a choice instead of showing its saved camera.
    enum SlotNote: Equatable {
        case none
        /// The saved camera is not connected (never substituted).
        case savedMissing
        /// The saved camera is already assigned to another slot.
        case savedDuplicate(of: ChannelID)
        /// The chosen camera was unplugged during setup.
        case unplugged
    }

    /// One entry in a slot's device picker.
    struct DeviceOption: Identifiable, Equatable {
        let device: Device
        /// "in use by A" when another slot holds it; the entry stays visible.
        let unavailableReason: String?
        var id: String { device.id }
        var isAvailable: Bool { unavailableReason == nil }
    }

    /// The four results the pair check reports.
    enum PairCheckRow: CaseIterable, Identifiable {
        case distinctDevices
        case showRate
        case renderHeadroom
        case memoryAndHeat

        var id: Self { self }

        var title: String {
            switch self {
            case .distinctDevices: return "Two distinct devices"
            case .showRate: return "Both at the show rate"
            case .renderHeadroom: return "Render headroom"
            case .memoryAndHeat: return "Memory and heat"
            }
        }

        /// Which row a measured failure belongs to. Evidence gaps make a
        /// result unknown, never unsupported, so they map to no row.
        static func row(for bottleneck: AdmissionBottleneck) -> PairCheckRow? {
            switch bottleneck {
            case .capture: return .showRate
            case .render, .perception, .cpu: return .renderHeadroom
            case .memory, .heat: return .memoryAndHeat
            case .evidence: return nil
            }
        }
    }

    enum RowState: Equatable {
        case notMeasured
        case checking
        case passed
        case failed(String?)
    }

    enum PairCheckResult: Equatable {
        case notRun
        case checking
        /// A stored provisional (trial) or certified record for this pair.
        case pass(certified: Bool, measuredAt: Date?)
        /// A stored measurement failed; the reasons say which.
        case unsupported([AdmissionReason])
    }

    // MARK: State

    private(set) var standard: ShowStandard
    private(set) var output: ProgramOutputManager.Route
    /// Routes the show's output can use (Program Display, Virtual Camera).
    var outputs: [ProgramOutputManager.Route]
    /// Starting or running: every picker is locked.
    var isRunning = false
    private(set) var devices: [Device]
    /// Chosen device unique IDs for A and B.
    private(set) var selection: [ChannelID: String] = [:]
    private(set) var notes: [ChannelID: SlotNote] = [:]
    /// The engine has one capture profile for every channel, set in Settings;
    /// setup shows it per slot, read-only (no per-slot picker yet).
    var captureProfile: String
    var machine: Machine
    /// Stored admission records, parsed (see StoredPairRecord).
    var records: [StoredPairRecord]
    /// A pair measurement is in progress for this exact configuration. Any
    /// configuration change clears it.
    private(set) var isChecking = false

    /// The two slots R2 assigns; C and D stay "not assigned".
    static let assignableSlots: [ChannelID] = [.a, .b]

    // MARK: Init

    /// - Parameters:
    ///   - saved: persisted device choices. Proposals only: a missing or
    ///     duplicate ID asks for a choice and is never substituted.
    ///   - fallbackA: channel A's first-run choice, used only when nothing was
    ///     saved for A (so "Start with Camera A only" works on first launch).
    init(standard: ShowStandard,
         output: ProgramOutputManager.Route,
         outputs: [ProgramOutputManager.Route] = ProgramOutputManager.Route.allCases,
         devices: [Device],
         saved: [ChannelID: String] = [:],
         fallbackA: String? = nil,
         captureProfile: String = "Stage",
         machine: Machine,
         records: [StoredPairRecord] = []) {
        self.standard = standard
        self.output = output
        self.outputs = outputs
        self.devices = devices
        self.captureProfile = captureProfile
        self.machine = machine
        self.records = records

        let present = Set(devices.map(\.uniqueID))
        if let savedA = saved[.a] {
            if present.contains(savedA) { selection[.a] = savedA } else { notes[.a] = .savedMissing }
        } else if let fallbackA, present.contains(fallbackA) {
            selection[.a] = fallbackA
        }
        if let savedB = saved[.b] {
            if !present.contains(savedB) {
                notes[.b] = .savedMissing
            } else if savedB == selection[.a] || savedB == saved[.a] {
                notes[.b] = .savedDuplicate(of: .a)
            } else {
                selection[.b] = savedB
            }
        }
    }

    // MARK: Changes (each one invalidates a result in progress)

    /// Assign a device to a slot. Refused (false) when another slot holds it
    /// or it is not present, or while the show runs.
    @discardableResult
    mutating func select(_ uniqueID: String, for slot: ChannelID) -> Bool {
        guard !isRunning, Self.assignableSlots.contains(slot),
              devices.contains(where: { $0.uniqueID == uniqueID }),
              owner(of: uniqueID).map({ $0 == slot }) ?? true else { return false }
        selection[slot] = uniqueID
        notes[slot] = SlotNote.none
        isChecking = false
        return true
    }

    mutating func setStandard(_ value: ShowStandard) {
        guard !isRunning, value != standard else { return }
        standard = value
        isChecking = false
    }

    mutating func setOutput(_ value: ProgramOutputManager.Route) {
        guard !isRunning, value != output else { return }
        output = value
        isChecking = false
    }

    /// Hot-plug: a chosen device that disappears is cleared, never replaced.
    mutating func updateDevices(_ value: [Device]) {
        guard value != devices else { return }
        devices = value
        let present = Set(value.map(\.uniqueID))
        for slot in Self.assignableSlots {
            if let chosen = selection[slot], !present.contains(chosen) {
                selection[slot] = nil
                notes[slot] = .unplugged
                isChecking = false
            }
        }
    }

    /// Mark a pair measurement as running for the current configuration.
    mutating func beginCheck() {
        guard hasDistinctPair else { return }
        isChecking = true
    }

    mutating func endCheck() { isChecking = false }

    // MARK: Slots

    func device(for slot: ChannelID) -> Device? {
        selection[slot].flatMap { id in devices.first { $0.uniqueID == id } }
    }

    func note(for slot: ChannelID) -> SlotNote { notes[slot] ?? .none }

    /// The slot currently holding a device, if any.
    func owner(of uniqueID: String) -> ChannelID? {
        Self.assignableSlots.first { selection[$0] == uniqueID }
    }

    /// Every present device; one held by another slot stays listed, disabled.
    func options(for slot: ChannelID) -> [DeviceOption] {
        devices.map { device in
            let holder = owner(of: device.uniqueID)
            let reason = holder.flatMap { $0 == slot ? nil : "in use by \($0.letter)" }
            return DeviceOption(device: device, unavailableReason: reason)
        }
    }

    /// Picker label: the device name, or a request to choose.
    func deviceTitle(for slot: ChannelID) -> String {
        device(for: slot)?.name ?? "Choose a device"
    }

    /// Why the slot is asking for a choice, when it is.
    func noteText(for slot: ChannelID) -> String? {
        switch note(for: slot) {
        case .none: return nil
        case .savedMissing: return "The camera saved for \(slot.letter) is not connected."
        case .savedDuplicate(let other): return "The camera saved for \(slot.letter) is already Camera \(other.letter)."
        case .unplugged: return "The chosen camera was disconnected."
        }
    }

    /// What the channel renders for the output (not the camera's native format).
    var deliveryTitle: String {
        String(format: "Delivering 1920×1080 at %.2f fps", standard.frameRate)
    }

    // MARK: Pair check

    var hasDistinctPair: Bool {
        guard let a = device(for: .a), let b = device(for: .b) else { return false }
        return a.uniqueID != b.uniqueID
    }

    /// Stored records for this Mac, standard, route and A/B camera models.
    var matchingRecords: [StoredPairRecord] {
        guard let a = device(for: .a), let b = device(for: .b), hasDistinctPair else { return [] }
        return records.filter {
            $0.matches(machine: machine, standard: standard, route: output, modelA: a.modelID, modelB: b.modelID)
        }
    }

    /// The most relevant stored result. Modes are unknown before Start and a
    /// Track + Track pair costs more than Track + Pan, so an unsupported
    /// record for this pair wins; then certified; then the newest trial.
    var pairCheck: PairCheckResult {
        if isChecking { return .checking }
        let matches = matchingRecords.sorted { $0.measuredAt > $1.measuredAt }
        if let failed = matches.first(where: { if case .unsupported = $0.status { return true } else { return false } }),
           case .unsupported(let reasons) = failed.status {
            return .unsupported(reasons)
        }
        if let certified = matches.first(where: { $0.status == .certified }) {
            return .pass(certified: true, measuredAt: certified.measuredAt)
        }
        if let trial = matches.first(where: { $0.status == .provisional }) {
            return .pass(certified: false, measuredAt: trial.measuredAt)
        }
        return .notRun
    }

    func rowState(_ row: PairCheckRow) -> RowState {
        if row == .distinctDevices {
            if device(for: .a) == nil || device(for: .b) == nil { return .notMeasured }
            return hasDistinctPair ? .passed : .failed("A and B are the same camera.")
        }
        switch pairCheck {
        case .notRun: return .notMeasured
        case .checking: return .checking
        case .pass: return .passed
        case .unsupported(let reasons):
            let failing = reasons.filter { PairCheckRow.row(for: $0.bottleneck) == row }
            return failing.isEmpty ? .passed : .failed(failing.first?.message)
        }
    }

    /// Rows a stored unsupported result names, in display order.
    var failingRows: [PairCheckRow] {
        PairCheckRow.allCases.filter { if case .failed = rowState($0) { return true } else { return false } }
    }

    // MARK: Copy

    var pairCheckTitle: String {
        switch pairCheck {
        case .notRun: return "A + B at \(standard.title): unknown on this Mac"
        case .checking: return "Checking A + B at \(standard.title) on this Mac"
        case .pass(let certified, _):
            return "A + B hold \(standard.title) on this Mac · \(certified ? "certified" : "trial")"
        case .unsupported: return "Camera B unsupported at \(standard.title) with Camera A"
        }
    }

    var pairCheckDetail: String {
        switch pairCheck {
        case .notRun:
            return "Alfie measures A + B together right after Start and shows the result in the console header. It will not lower the output rate to make them fit."
        case .checking:
            return "Measuring both cameras together on this Mac. It will not lower the output rate to make them fit."
        case .pass(true, _):
            return "Certified by the 60-minute two-input soak on this exact setup."
        case .pass(false, let measuredAt):
            // The card's copy says "Measured now"; a stored record says when.
            let when = measuredAt.map { "Measured \(Self.dateFormatter.string(from: $0))" } ?? "Measured now"
            return "\(when), not certified. Certification needs the 60-minute two-input soak on this exact setup."
        case .unsupported:
            let failed = failingRows.map(\.title).joined(separator: ", ")
            return "Failed: \(failed). \(suggestion)"
        }
    }

    /// A concrete next step for the first failing measurement.
    var suggestion: String {
        switch failingRows.first(where: { $0 != .distinctDevices }) {
        case .showRate?:
            return "Choose a Camera B that delivers \(standard.title) natively, or start with Camera A only."
        case .renderHeadroom?:
            return "Run one camera in Wide or Pan instead of tracking both, close other apps, or start with Camera A only."
        case .memoryAndHeat?:
            return "Let this Mac cool down and close other apps, or start with Camera A only."
        default:
            return "Start with Camera A only."
        }
    }

    func rowStatusText(_ row: PairCheckRow) -> String {
        switch rowState(row) {
        case .notMeasured:
            return row == .distinctDevices ? "Choose A and B" : "Not measured yet"
        case .checking: return "Checking…"
        case .passed:
            return row == .distinctDevices ? "Different cameras" : "Passed"
        case .failed(let message): return message ?? "Failed"
        }
    }

    /// What VoiceOver reads for a result row.
    func accessibilityLabel(for row: PairCheckRow) -> String {
        switch rowState(row) {
        case .notMeasured: return "\(row.title): \(rowStatusText(row))"
        case .checking: return "\(row.title): checking"
        case .passed: return "\(row.title): passed"
        case .failed(let message): return "\(row.title): failed. \(message ?? "")".trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: Start

    var canStartAOnly: Bool {
        !isRunning && device(for: .a) != nil
    }

    /// Both chosen, distinct and present, and no stored result says the pair
    /// fails here. An unmeasured pair may start; the console measures it.
    var canStartPair: Bool {
        guard !isRunning, !isChecking, hasDistinctPair else { return false }
        if case .unsupported = pairCheck { return false }
        return true
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

// MARK: - Stored records

/// An admission record with the parts of its fingerprint setup can match.
/// The store keys records by `AdmissionFingerprint.key`, so the fields are
/// parsed back from that key.
struct StoredPairRecord: Equatable {
    var policyVersion: Int
    var machineModel: String
    var osVersion: String
    /// ShowStandard.title, e.g. "1080p50".
    var showStandard: String
    /// Route title, e.g. "Program Display"; nil when none was active.
    var route: String?
    /// Camera model per channel letter ("?" when the channel had no device).
    var inputs: [String: String]
    var status: AdmissionStatus
    var measuredAt: Date

    func matches(machine: ShowSetupModel.Machine, standard: ShowStandard,
                 route selectedRoute: ProgramOutputManager.Route, modelA: String, modelB: String) -> Bool {
        policyVersion == AdmissionPolicy.version
            && machineModel == machine.model && osVersion == machine.osVersion
            && showStandard == standard.title && route == selectedRoute.title
            && inputs.count == 2
            && inputs["A"] == modelA && inputs["B"] == modelB
    }

    /// Parse `AdmissionFingerprint.key`:
    /// `version|machine|os|standard|route|A:model:WxH@fps:profile:mode|B:…`.
    /// The model ID may itself contain ":", so each input is read from both
    /// ends. Returns nil for a key it cannot read.
    static func parse(key: String, status: AdmissionStatus, measuredAt: Date) -> StoredPairRecord? {
        let parts = key.components(separatedBy: "|")
        guard parts.count >= 5, let version = Int(parts[0]) else { return nil }
        var inputs: [String: String] = [:]
        for segment in parts.dropFirst(5) {
            let fields = segment.components(separatedBy: ":")
            guard fields.count >= 5 else { return nil }
            let model = fields[1..<(fields.count - 3)].joined(separator: ":")
            inputs[fields[0]] = model
        }
        return StoredPairRecord(policyVersion: version, machineModel: parts[1], osVersion: parts[2],
                                showStandard: parts[3], route: parts[4] == "none" ? nil : parts[4],
                                inputs: inputs, status: status, measuredAt: measuredAt)
    }
}
