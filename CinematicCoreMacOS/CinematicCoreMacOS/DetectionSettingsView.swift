//
//  DetectionSettingsView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/4/2026.
//

import SwiftUI

/// Settings panel for person detection configuration
struct DetectionSettingsView: View {
    @ObservedObject var personDetector: PersonDetector
    
    var body: some View {
        Form {
            Section("Detection") {
                Toggle("Enable Detection", isOn: $personDetector.isEnabled)
                
                Toggle("High Accuracy Mode", isOn: $personDetector.config.useHighAccuracy)
                    .help("More accurate but slower (reduces frame rate)")
                
                HStack {
                    Text("Confidence Threshold")
                    Spacer()
                    Text(String(format: "%.0f%%", personDetector.config.confidenceThreshold * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                Slider(
                    value: Binding(
                        get: { Double(personDetector.config.confidenceThreshold) },
                        set: { personDetector.config.confidenceThreshold = Float($0) }
                    ),
                    in: 0.1...1.0,
                    step: 0.05
                )
                
                Stepper(
                    "Max Persons: \(personDetector.config.maxPersons)",
                    value: $personDetector.config.maxPersons,
                    in: 1...10
                )
            }
            
            Section("Statistics") {
                LabeledContent("Persons Detected", value: "\(personDetector.stats.personsDetectedCount)")
                
                LabeledContent(
                    "Detection Time",
                    value: String(format: "%.1fms", personDetector.stats.lastDetectionTime * 1000)
                )
                
                LabeledContent(
                    "Average Time",
                    value: String(format: "%.1fms", personDetector.stats.averageDetectionTime * 1000)
                )
                
                LabeledContent("Frames Processed", value: "\(personDetector.stats.totalFramesProcessed)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 450)
    }
}

#Preview {
    DetectionSettingsView(personDetector: PersonDetector())
}
