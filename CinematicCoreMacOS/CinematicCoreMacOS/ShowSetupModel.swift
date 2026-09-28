import Foundation

/// Gallery state. Device discovery, admission and persistence are supplied by
/// DEVICES/ADMISSION at integration; this type never opens a camera.
struct ShowSetupModel {
    enum Output: String, CaseIterable, Identifiable {
        case programDisplay = "Program Display"
        case virtualCamera = "Virtual Camera"
        var id: String { rawValue }
    }

    struct Slot: Identifiable {
        let letter: String
        var device: String?
        var captureProfile: String
        var delivery: String
        var id: String { letter }
    }

    enum PairCheckResult: Equatable {
        case notRun
        case checking
        case pass
        case unsupported

        var isStartEnabled: Bool { self == .pass }
    }

    var standard: ShowStandard = .p50
    var output: Output = .programDisplay
    var isRunning = false
    var slots: [Slot] = [
        .init(letter: "A", device: "Stage wide", captureProfile: "Stage", delivery: "Delivering 1920×1080 at 50.00 fps"),
        .init(letter: "B", device: "Band side", captureProfile: "Stage", delivery: "Delivering 1920×1080 at 50.00 fps"),
        .init(letter: "C", device: nil, captureProfile: "", delivery: ""),
        .init(letter: "D", device: nil, captureProfile: "", delivery: "")
    ]
    var pairCheck: PairCheckResult = .notRun

    var pairCheckTitle: String {
        switch pairCheck {
        case .notRun: "A + B at \(standard.title): unknown on this Mac"
        case .checking: "Checking A + B at \(standard.title) on this Mac"
        case .pass: "A + B hold \(standard.title) on this Mac · trial"
        case .unsupported: "Camera B unsupported at \(standard.title) with Camera A"
        }
    }

    var deliveryTitle: String {
        String(format: "Delivering 1920×1080 at %.2f fps", standard.frameRate)
    }
}
