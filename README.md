# Cinematic Core (Broadcast Helper)

An autonomous virtual camera operator for live broadcast environments. This macOS application ingests a static 4K wide shot, uses computer vision to detect subjects, and outputs a digitally panned and zoomed 1080p signal to ATEM switchers via dedicated hardware.

## System Architecture

**Input**
4K video feed (3840x2160) from a stationary camera via a capture card.

**Processing (macOS)**
1. **Perception:** Apple's Vision framework detects subject position and body keypoints.
2. **Control:** A Reinforcement Learning (RL) agent calculates cinematic camera moves (Digital PTZ).
3. **Rendering:** Metal-based engine performs high-quality cropping and scaling.

**Output**
1080p broadcast signal via Blackmagic UltraStudio Monitor 3G to an ATEM switcher.

## Hardware Requirements

- **Host:** Apple Silicon Mac (M1/M2/M3/M4...)
- **Camera:** 4K capable camera
- **Input Device:** Elgato Cam Link 4K or Blackmagic UltraStudio Recorder
- **Output Device:** Blackmagic UltraStudio Monitor 3G

## Development Setup

1. Install Xcode 15.0 or later.
2. Install Blackmagic Desktop Video 12.0+ drivers and SDK.
3. Clone the repository.
4. Open `CinematicCore.xcodeproj`.
5. Select the `CinematicCore` target and build.

## Roadmap Status

**Phase 1: Infrastructure (Current)**
- [x] 4K Video Capture Pipeline
- [ ] Blackmagic SDK Output Integration
- [ ] Metal Rendering Engine

**Phase 2: Perception**
- [ ] Apple's Vision framework Integration
- [ ] Subject Tracking Logic

**Phase 3: Automation**
- [ ] RL Agent Integration
- [ ] Smooth Motion Control

## License

Proprietary / Internal Use Only
