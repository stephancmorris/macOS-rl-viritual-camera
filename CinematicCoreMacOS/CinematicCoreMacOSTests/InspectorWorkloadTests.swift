#if DEBUG
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct InspectorWorkloadTests {
    private func show(enabled: Bool) -> ShowCoordinator {
        let defaults = UserDefaults(suiteName: "alfie-inspector-workload-\(UUID().uuidString)")!
        return TestHardware.makeShow(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: defaults),
            operatorModes: OperatorModeStore(defaults: defaults, multiviewEnabled: true),
            workloadPolicyEnabled: enabled)
    }

    private var overloaded: DegradePolicy.Window {
        var window = DegradePolicy.Window()
        window.cpuFraction = 0.95
        window.programDeadlineMissFraction = 0.05
        window.candidateAgeSeconds = 0.05
        return window
    }

    @Test func mapsEveryLevelToOperatorWords() {
        let expected = [
            "Normal", "Reducing optional UI", "Reduce optional pose and face refresh",
            "Reduce Preview analysis", "Reduce Preview picture refresh", "Camera pair unsupported",
        ]
        #expect(DegradePolicy.Level.allCases.map(InspectorWorkloadDetail.levelText) == expected)
    }

    @Test func mapsEveryReasonToOperatorWords() {
        let reasons: [DegradePolicy.Reason] = [
            .thermalPressure, .cpuPressure, .previewStale, .programDeadlineMiss,
            .sourceIngestFailed, .programBudgetFailed, .candidateStale, .invalidMeasurement, .recovering,
        ]
        #expect(reasons.map(InspectorWorkloadDetail.reasonText) == [
            "Heat pressure", "CPU pressure", "Preview picture delayed", "Program deadline misses",
            "Camera input cannot keep up", "Program work exceeds budget", "Next shot is not fresh",
            "Workload measurement not usable", "Recovering after pressure",
        ])
    }

    @Test func disabledPolicyHasNoWorkloadDetail() {
        let show = show(enabled: false)
        for _ in 0..<3 { show.applyWorkloadWindow(overloaded) }
        #expect(InspectorWorkloadDetail(policy: show.workloadPolicy) == nil)
    }

    @Test func enabledPolicyStartsNormalWithoutInventingAReason() throws {
        let detail = try #require(InspectorWorkloadDetail(policy: show(enabled: true).workloadPolicy))
        #expect(detail.levelText == "Normal")
        #expect(detail.reasonsText == nil)
        #expect(detail.accessibilityValue == "Normal")
    }

    @Test func lastTransitionReasonsPersistAcrossUnchangedWindowsAndRecover() throws {
        let show = show(enabled: true)
        for _ in 0..<3 { show.applyWorkloadWindow(overloaded) }
        let changed = try #require(InspectorWorkloadDetail(policy: show.workloadPolicy))
        #expect(show.workloadLevel == .optionalUI)
        #expect(changed.levelText == "Reducing optional UI")
        #expect(changed.reasonsText == "CPU pressure, Program deadline misses")
        #expect(changed.accessibilityValue == "Reducing optional UI. Last change: CPU pressure, Program deadline misses")

        var healthy = DegradePolicy.Window()
        healthy.candidateAgeSeconds = 0.05
        show.applyWorkloadWindow(healthy)
        #expect(InspectorWorkloadDetail(policy: show.workloadPolicy) == changed)
        for _ in 0..<5 { show.applyWorkloadWindow(healthy) }
        let recovered = try #require(InspectorWorkloadDetail(policy: show.workloadPolicy))
        #expect(recovered.levelText == "Normal")
        #expect(recovered.reasonsText == "Recovering after pressure")
    }

    @Test func enabledWorkloadIsVisibleWithOneInput() {
        let show = show(enabled: true)
        let host = NSHostingView(rootView: InspectorShowSection(show: show).frame(width: 356))
        #expect(host.fittingSize.height > 30)
        #expect(InspectorShowDetail.make(show: show, now: 0) == nil)
    }

    /// Render the actual drawer over a 1280×800 console. The disabled render
    /// is reviewed alongside the enabled positive control with the snapshot
    /// opt-in, matching the existing gallery's export convention.
    @Test(arguments: [false, true])
    func rendersAt1280WithPolicyDisabledAndEnabled(enabled: Bool) throws {
        let show = show(enabled: enabled)
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b).setRunningForTesting(true)
        for _ in 0..<3 { show.applyWorkloadWindow(overloaded) }
        #expect((InspectorWorkloadDetail(policy: show.workloadPolicy) != nil) == enabled)

        let view = ZStack(alignment: .trailing) {
            LiveMultiviewConsole(show: show)
            InspectorDrawer(
                cameraManager: show.channelA,
                systemExtensionManager: SystemExtensionActivationManager(),
                settingsWindowController: SettingsWindowController(),
                isOpen: .constant(true), show: show)
        }
        .frame(width: 1280, height: 800)
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        #expect(host.bounds.size == CGSize(width: 1280, height: 800))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= 1280 && rep.pixelsHigh >= 800)

        if ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: dir.appendingPathComponent("inspector-workload-\(enabled ? "enabled" : "disabled")-1280.png"))
        }
    }
}
#endif
