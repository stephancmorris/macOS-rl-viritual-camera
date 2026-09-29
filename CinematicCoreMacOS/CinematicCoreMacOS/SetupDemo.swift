//
//  SetupDemo.swift
//  CinematicCoreMacOS
//
//  Gallery for SHOW-SETUP. Fake devices and admission records run through
//  the real ShowSetupModel (record matching, duplicate / missing handling,
//  copy); no discovery, capture or admission code runs here.
//

import SwiftUI

extension ShowSetupModel {
    enum GalleryScenario: String, CaseIterable, Identifiable {
        case notRun, checking, pass, certified, unsupported, missingSaved
        var id: String { rawValue }

        var title: String {
            switch self {
            case .notRun: return "Not run"
            case .checking: return "Checking"
            case .pass: return "Pass · trial"
            case .certified: return "Certified"
            case .unsupported: return "Unsupported"
            case .missingSaved: return "Saved B missing"
            }
        }
    }

    static let galleryMachine = Machine(model: "Mac15,9", osVersion: "Version 26.0 (Build 25A354)")
    static let galleryDevices: [Device] = [
        .init(uniqueID: "gallery-wide", name: "Stage wide · FX3", modelID: "Sony FX3"),
        .init(uniqueID: "gallery-side", name: "Band side · UltraStudio", modelID: "UltraStudio 4K"),
        .init(uniqueID: "gallery-desk", name: "FaceTime HD Camera", modelID: "FaceTime HD")
    ]

    /// A stored record for the gallery pair, keyed exactly as the engine keys it.
    static func galleryRecord(_ status: AdmissionStatus, standard: ShowStandard = .p50,
                              route: ProgramOutputManager.Route = .display,
                              measuredAt: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> StoredPairRecord {
        let fingerprint = AdmissionFingerprint(
            machineModel: galleryMachine.model, osVersion: galleryMachine.osVersion,
            showStandard: standard.title, route: route.title,
            inputs: [
                .init(channel: "A", deviceModelID: "Sony FX3", deliveredWidth: 3840, deliveredHeight: 2160,
                      captureFPS: standard.frameRate, captureProfile: "stage", mode: "track"),
                .init(channel: "B", deviceModelID: "UltraStudio 4K", deliveredWidth: 1920, deliveredHeight: 1080,
                      captureFPS: standard.frameRate, captureProfile: "stage", mode: "track")
            ])
        return StoredPairRecord.parse(key: fingerprint.key, status: status, measuredAt: measuredAt)!
    }

    static let galleryRenderFailure = AdmissionReason(
        code: "preview.render", bottleneck: .render,
        message: "The second input rendered 41.2 fps; it needs about 50 fps to stay ready for Take.")

    static func gallery(_ scenario: GalleryScenario) -> ShowSetupModel {
        var records: [StoredPairRecord] = []
        switch scenario {
        case .pass: records = [galleryRecord(.provisional)]
        case .certified: records = [galleryRecord(.certified)]
        case .unsupported: records = [galleryRecord(.unsupported([galleryRenderFailure]))]
        default: break
        }
        var model = ShowSetupModel(
            standard: .p50, output: .display, devices: galleryDevices,
            saved: [.a: "gallery-wide", .b: scenario == .missingSaved ? "gallery-unplugged" : "gallery-side"],
            machine: galleryMachine, records: records)
        if scenario == .checking { model.beginCheck() }
        return model
    }
}

/// Gallery-only setup screen: the scenario picker loads a model; device and
/// picker changes act on it so invalidation and "in use by A" can be tried.
struct SetupDemo: View {
    @State private var scenario = ShowSetupModel.GalleryScenario.notRun
    @State private var model = ShowSetupModel.gallery(.notRun)
    @State private var startMessage = ""

    var body: some View {
        VStack(spacing: 10) {
            Picker("Pair-check scenario", selection: $scenario) {
                ForEach(ShowSetupModel.GalleryScenario.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 720)
            .onChange(of: scenario) { _, value in model = .gallery(value) }

            ShowSetupView(model: model, actions: ShowSetupActions(
                selectDevice: { slot, id in model.select(id, for: slot) },
                selectStandard: { model.setStandard($0) },
                selectOutput: { model.setOutput($0) },
                startAOnly: { startMessage = "Gallery: Camera A only" },
                startPair: { startMessage = "Gallery: A Program, B Preview" },
                checkPair: { model.beginCheck() }))
            .frame(width: 1280, height: 800)
            Text(startMessage)
                .font(.caption)
        }
    }
}

#Preview("Show setup") {
    SetupDemo()
}

#Preview("Show setup · unsupported") {
    ShowSetupView(model: .gallery(.unsupported), actions: ShowSetupActions(
        selectDevice: { _, _ in }, selectStandard: { _ in }, selectOutput: { _ in },
        startAOnly: {}, startPair: {}, checkPair: nil))
    .frame(width: 1280, height: 800)
}
