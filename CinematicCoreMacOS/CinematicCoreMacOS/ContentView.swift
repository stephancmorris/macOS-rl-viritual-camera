//
//  ContentView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/2/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showError = false
    @State private var showCameraList = false
    @State private var showDetections = true // Task 2.1: Toggle for detection overlay
    @State private var showDetectionSettings = false // Task 2.1: Detection settings panel
    @State private var showCropSettings = false // Task 2.2: Crop settings panel
    @State private var showCropIndicator = true // Task 2.2: Show crop rectangle on preview
    @State private var showComposerSettings = false // Task 2.3: Shot composer settings
    @State private var showRecorderSettings = false // Task 3.1: Training data recorder
    
    var body: some View {
        VStack(spacing: 0) {
            // Camera Preview (Main Area)
            CameraPreviewView(
                image: cameraManager.currentFrame,
                detectedPersons: cameraManager.personDetector.detectedPersons,
                showDetections: showDetections,
                cropIndicator: (showCropIndicator && cameraManager.cropEnabled) ? cameraManager.cropEngine?.currentCrop : nil
            )
            .background(Color.black)
            
            // Control Bar
            HStack(spacing: 16) {
                // Status Indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(cameraManager.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(cameraManager.isRunning ? "Live" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Detection Stats (Task 2.1)
                if cameraManager.isRunning {
                    VStack(alignment: .center, spacing: 2) {
                        Text("Persons: \(cameraManager.personDetector.detectedPersons.count)")
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Text(String(format: "%.1fms", cameraManager.personDetector.stats.lastDetectionTime * 1000))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Detection Toggle
                Toggle(isOn: $showDetections) {
                    Label("Detections", systemImage: "person.crop.rectangle")
                }
                .toggleStyle(.button)
                
                // Detection Settings
                Button(action: { showDetectionSettings.toggle() }) {
                    Label("Detection", systemImage: "slider.horizontal.3")
                }
                .popover(isPresented: $showDetectionSettings) {
                    DetectionSettingsView(personDetector: cameraManager.personDetector)
                }
                
                Spacer()
                
                // Task 2.2: Crop Controls
                if let cropEngine = cameraManager.cropEngine {
                    // Crop Stats
                    if cameraManager.isRunning && cameraManager.cropEnabled {
                        VStack(alignment: .center, spacing: 2) {
                            Text("Crop: \(Int(cropEngine.config.outputSize.width))×\(Int(cropEngine.config.outputSize.height))")
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Text(String(format: "%.1fms", cropEngine.stats.lastRenderTime * 1000))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Crop Toggle
                    Toggle(isOn: $cameraManager.cropEnabled) {
                        Label("Crop", systemImage: "crop.rotate")
                    }
                    .toggleStyle(.button)
                    
                    // Crop Indicator Toggle
                    Toggle(isOn: $showCropIndicator) {
                        Label("Indicator", systemImage: "viewfinder")
                    }
                    .toggleStyle(.button)
                    .disabled(!cameraManager.cropEnabled)
                    
                    // Crop Settings
                    Button(action: { showCropSettings.toggle() }) {
                        Label("Crop Settings", systemImage: "gearshape")
                    }
                    .popover(isPresented: $showCropSettings) {
                        CropSettingsView(
                            cropEngine: cropEngine,
                            cameraManager: cameraManager
                        )
                    }
                }

                // Task 2.3: Shot Composer Settings
                Button(action: { showComposerSettings.toggle() }) {
                    Label("Composer", systemImage: "film")
                }
                .popover(isPresented: $showComposerSettings) {
                    ShotComposerSettingsView(
                        shotComposer: cameraManager.shotComposer
                    )
                }

                // Task 3.1: Training Data Recorder
                Button(action: { showRecorderSettings.toggle() }) {
                    Label(
                        cameraManager.trainingDataRecorder.isRecording ? "REC" : "Recorder",
                        systemImage: cameraManager.trainingDataRecorder.isRecording
                            ? "record.circle.fill" : "record.circle"
                    )
                    .foregroundStyle(
                        cameraManager.trainingDataRecorder.isRecording ? .red : .primary
                    )
                }
                .popover(isPresented: $showRecorderSettings) {
                    RecorderSettingsView(
                        recorder: cameraManager.trainingDataRecorder,
                        cameraManager: cameraManager
                    )
                }

                Spacer()

                // Camera Info/Selector
                VStack(alignment: .center, spacing: 2) {
                    if let selected = cameraManager.selectedCamera {
                        Text(selected.name)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Text(selected.maxResolution)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No Camera")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Camera List Button
                Button(action: { showCameraList.toggle() }) {
                    Label("Cameras (\(cameraManager.availableCameras.count))", 
                          systemImage: "camera.circle")
                }
                .popover(isPresented: $showCameraList) {
                    CameraListView(cameraManager: cameraManager)
                }
                
                // Refresh Button
                Button(action: { cameraManager.discoverCameras() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                Spacer()
                
                // Start/Stop Button
                Button(action: toggleCamera) {
                    Label(
                        cameraManager.isRunning ? "Stop" : "Start",
                        systemImage: cameraManager.isRunning ? "stop.circle.fill" : "play.circle.fill"
                    )
                }
                .disabled(cameraManager.error != nil || cameraManager.availableCameras.isEmpty)
            }
            .padding()
            .background(.regularMaterial)
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert("Camera Error", isPresented: $showError, presenting: cameraManager.error) { _ in
            Button("OK") { showError = false }
        } message: { error in
            Text(error.localizedDescription)
        }
        .task {
            await startCamera()
        }
    }
    
    private func startCamera() async {
        do {
            try await cameraManager.startCapture()
        } catch {
            showError = true
        }
    }
    
    private func toggleCamera() {
        if cameraManager.isRunning {
            cameraManager.stopCapture()
        } else {
            Task {
                await startCamera()
            }
        }
    }
}

// MARK: - Camera List View

struct CameraListView: View {
    @ObservedObject var cameraManager: CameraManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Available Cameras")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    cameraManager.discoverCameras()
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            // Camera List
            if cameraManager.availableCameras.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Cameras Found")
                        .font(.headline)
                    Text("Check Xcode Console for diagnostics")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cameraManager.availableCameras) { camera in
                            CameraRowView(
                                camera: camera,
                                isSelected: cameraManager.selectedCamera?.id == camera.id,
                                action: {
                                    Task {
                                        do {
                                            try await cameraManager.restartWithCamera(camera)
                                            dismiss()
                                        } catch {
                                            print("❌ Failed to switch camera: \(error)")
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 450, height: 350)
    }
}

// MARK: - Camera Row View

struct CameraRowView: View {
    let camera: CameraManager.CameraDevice
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(camera.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 12) {
                        Label(camera.maxResolution, systemImage: "rectangle.resize")
                            .font(.caption)
                        
                        if camera.supports4K {
                            Label("4K", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        
                        Text("\(camera.formatCount) formats")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
