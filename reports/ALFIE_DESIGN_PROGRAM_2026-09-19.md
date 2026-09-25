# Alfie: zoom, independent inputs, speech, and physical yaw

Design memo · 19 September 2026 · Discovery only

Recommendation: make digital zoom an independent movement within the existing modes; prove two isolated camera channels; add speech through the same command dispatcher; then connect hardware before designing its motion controller. Retain the volunteer’s pill, explicit manual override, and one-action Return to Wide throughout.

This memo is based on ALFIE_SPEC.md, README.md, and the current source tree. No implementation, refactoring, build, hardware test, or PR was performed. Numeric proposals below are starting values and acceptance budgets, not measured capabilities. Existing generated build artifacts were already modified and were left alone.

## 1. Current-state brief

The live system has one AVCaptureSession, detector, composer, crop engine, and output manager. `CameraManager.OperationMode` is `wide`, `autoTracking`, `manualCrop`, or `autoPan`; there is no independent zoom state. Detection is operator-initiated, uses a ≤1080p proxy and ROI, and runs asynchronously with a single detection job in flight. The frame path uses a separate single-frame gate. See [CameraManager.swift:195](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:195), [detection scheduling:360](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:360), and [PersonDetector.swift:170](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/PersonDetector.swift:170).

`FramingPreset` is a proposed conceptual name: the actual type is `ShotComposer.Config.ShotPreset`. Tracking derives size from subject geometry and preset tuning; manual and pan instead use fixed heights 1.0 / 0.8 / 0.5. CropEngine interpolates origin and size with a critically damped spring, but Auto Pan calls `jumpToTarget()` every frame. Rendering runs off MainActor on a **static serial queue shared by every CropEngine instance**. The same rendered buffer is published to the right pane and submitted to the selected output sink. See [compose loop:1350](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:1350), [spring:498](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CropEngine.swift:498), and [render queue:344](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CropEngine.swift:344).

Material conflicts with docs or the brief:

| Topic | What the code actually does |
| --- | --- |
| Wide preset and pan | Tracking Wide caps height at 0.85; manual/pan Wide is 1.0 on a 16:9 source, so pan holds center. The pill comment claiming every preset has travel is stale. Tracking Full Body caps at 0.85, not the spec’s 0.95. |
| Quality | Hard minimum height is `min(1, max(floor(sourceHeight/4),240)/sourceHeight)`: approximately 4× linear digital zoom. This is a degeneracy limit, not native-resolution quality. `ZOOM LIMITED` is set when the composer’s desired height falls below that hard floor, not at the older “comfort tier” mentioned in comments. Manual/pan do not compute their own equivalent status. |
| Recovery | Tracking holds for 10 seconds, then requests a smooth pullback to wide and face-based reacquisition. It does not hold indefinitely. Explicit Return to Wide snaps and clears the lock. A render exception can submit the raw input buffer, contrary to the soft-failure principle. |
| Control ownership | Lock-state outcomes can set `activeMode` independently of an operator’s Manual/Auto Pan selection. There is no command arbitration layer. The pill has Detect, presets, Crop, Manual Crop, Auto Pan, Return to Wide, Stop; it has no separate Resume Tracking button. |
| Outputs | Program Display is the default, with virtual-camera fallback; only one route is active. This disagrees with the spec’s virtual-camera-primary description. Preview proves which pixels Alfie submitted, not that a downstream receiver displayed them. An ATEM needs a physical video input; its control software is not a USB-camera-to-SDI bridge. |
| Supported OS | The product says macOS 14+, but the project’s deployment target is 26.2. This memo preserves 14+ as the requested design baseline; shipping support needs a deliberate decision. |

Evidence: [preset tuning](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift:2076), [quality floor](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CropEngine.swift:151), [quality status and composition](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift:1598), [recovery/mode effects](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:1298), [render fallback](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:1515), [pill](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/OperatorPill.swift:19), [routing](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ProgramOutputManager.swift:839), [deployment target](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/project.pbxproj:458).

## 2. Workstream 1 — Zoom

### Model options and recommendation

| Option | Benefit | Cost |
| --- | --- | --- |
| Replace presets with continuous zoom | One size control | Loses familiar shot names and rapid return to a known composition. |
| Add bounded preset trim, e.g. 0.7–1.3× | Keeps subject-relative automatic sizing | Runs out of range arbitrarily; the composer may continue changing size after the volunteer releases. |
| Keep presets as shot choices; allow a continuous size override | Predictable push/pull across all three crop modes | Needs a visible “Adjusted” state and a clear reset rule. |

**Recommend the third option.** Presets remain quick ways to choose a shot. Continuous zoom takes ownership of size until the operator selects a preset again. The composer continues following the locked person and selecting the anchor; it does not counteract the operator’s size choice. Zoom is not a fifth OperationMode.

Use one canonical normalized crop height `h`, with width `w = h × normalizedAspect`. Let `hWide = min(1, 1/normalizedAspect)` and display zoom, if needed, as `z = hWide/h`. Internally, integrate movement in `log(z)` so equal hold time produces equal proportional magnification. Do not add competing stored height, factor, and slider position values.

Presets produce a base shot using today’s subject-relative geometry in tracking and fixed geometry in manual/pan. At first, retain those fixed manual/pan values rather than silently changing established shots. Document that selecting Wide during pan can stop its travel. Explicit zoom may move outside a preset’s stylistic min/max; the hard quality limit and frame fit still win. The pill reads, for example, “Waist Up · Adjusted.” Re-selecting Waist Up clears the override and resumes its automatic size policy; this requires removing the existing same-preset no-op guard.

On zoom start, seed size from the **currently visible** crop, not a distant pending target. Return to Wide cancels movement, clears the adjustment and lock, and retains its shipping immediate recovery behavior. Pulling out to full width does not silently unlock or change mode: tracking can stay locked at maximum width. From `.wide`, Push in enters Manual using the current visible center; it does not invent a subject. Pull out is already at its limit. A newly selected subject resets the size adjustment; changing between Manual, Pan, and Track preserves adjusted size and starts from the visible shot.

### Operator control: three viable options

| UI | Under-pressure behavior | Decision |
| --- | --- | --- |
| Two large hold buttons, “− Pull out” and “+ Push in” | Press while watching the program; release where it looks right. Short taps make small eased nudges. | **Primary recommendation.** |
| Discrete steps | Easy repeatability and accessibility | Useful tap behavior on the same two buttons, but steps alone are too coarse for landing a shot. |
| Slider/wheel or program-pane pinch | Direct continuous adjustment | A slider requires aiming and steals pill width; pinch is hardware-dependent and poorly discoverable. Optional later shortcut, not the live primary path. |

UX sketch: keep the two video panes. The pill retains lock status, Detect, presets, the three mode choices, the new push/pull pair, Return to Wide, and isolated Stop. Shorten the permanent lock text to “Locked,” “Recovering,” or “Pick subject”; place instructional sentences in the existing transient feedback area. “Manual Crop” can read “Manual.” Give push/pull stable, generous hit areas rather than squeezing every control. At the current 1280-point minimum width, verify the complete pill with long source names and accessibility text; do not solve overflow with a hidden menu or scrolling pill. Channel selection later occupies a compact A/B/C segment, not another toolbar.

Use the existing status area above the pill for “Zoom limit” and “Adjusted”; no numeric wheel is required to operate. Pointer release, cancellation, window deactivation, channel change, session stop, or a superseding command ends the hold. A gesture token ensures a late release cannot stop a newer gesture on another channel. Manual remains one tap away, with the current center and size adopted immediately before any repositioning tap.

### Composition by mode

**Manual:** zoom around the visible crop center. A tap on the wide pane moves that center using the existing coordinate conversion. At edges, preserve size and minimally shift the center to fit; never reveal black margins. Do not zoom around the pointer unless the operator explicitly repositions the shot.

**Auto Pan:** retain normalized phase, direction, and the existing 1.5-second endpoint dwell. With the **smoothed, legal current width**, compute `travel = max(0, 1-w)` and `centerX = w/2 + phase × travel`. Zoom therefore changes the sweep envelope continuously, rather than snapping between envelopes. Pause phase when travel is approximately zero; retain phase/direction and ease back into movement when room returns. Do not reset phase to center. During a dwell, a zoom changes the endpoint envelope smoothly while the remaining dwell time is preserved.

Do not simply add spring-based zoom before today’s `jumpToTarget()`: that call erases size interpolation. Separate deterministic pan-position evolution from spring-smoothed size, then assemble and constrain the final rectangle. Bound the combined horizontal movement caused by pan plus changing width; temporarily reduce phase advance during a fast pull-out if necessary. This preserves the shipping constant-speed sweep when zoom is idle. It avoids imposing tracking spring lag and altering dwell timing on ordinary pans.

**Tracking:** explicitly separate subject identity/ROI, follow position, and shot size. Apply zoom downstream of the composer’s size-noise hysteresis and independently of its “no new target” deadzone result. A stationary subject must still be zoomable when `compose()` returns nil. Cache the last stable anchor. For Waist Up, preserve headroom/top anchoring as size changes; for wider contextual shots, use the stable subject center. Recalculate containment and the Steady Follow band from the resulting crop, without repeatedly treating every zoom increment as a new subject or resetting identity.

During tracking HOLD, push/pull remains available around the last stable anchor. The existing 10-second recovery transition cancels an active zoom and pulls back smoothly; communicate “Subject lost · widening.” Automatic reacquisition may restore tracking only while tracking still owns control. Selecting Manual or Auto Pan cancels that authority, so a later lock event cannot seize the mode back.

Relevant integration points: [manual tap routing](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ContentView.swift:153), [auto-pan loop](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:1428), [composer hysteresis and gates](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift:1787).

### Motion quality and limits

Starting feel: hold speed `d(log z)/dt = ±0.12/s`, about 5.8 seconds for 2× magnification before easing; a short tap requests roughly 3%. Prototype a maximum size speed of 0.18 log-units/s and acceleration of 0.36 log-units/s². These are rehearsal defaults, not operator-facing settings. Start with a combined horizontal center-speed ceiling around 0.06 source-width/s and tune against current Slow/Normal/Fast sweeps.

Use CropEngine’s critically damped motion language, but give size its own state and limits so tracking’s temporary catch-up stiffness boost cannot turn a gentle zoom into a snap. Release brakes to rest with a short visible settling tail, rather than continuing toward a far-ahead integrated target. Keep the requested target close to current motion and stop accumulating at limits. Integrate safely through frame gaps using bounded substeps or an analytic spring; a critical-damping coefficient alone does not guarantee a numerically stable discrete update.

Apply constraints to the rendered rectangle as well as the target. Current target flooring does not by itself prove that velocity cannot overshoot a boundary. Preserve aspect ratio, fit, and size floor throughout; cancel outward velocity at a hard boundary and allow immediate movement away from it. Distinguish frame-fit limit from resolution limit on unusual aspect ratios.

Retain the current hard floor for this slice, but describe it honestly. A 2160-high source at `h=0.25` contains 540 source pixels vertically, enlarged 2× to 1080; a 1080-high source permits a 270-pixel crop, enlarged 4×. “ZOOM LIMITED” should consistently mean the requested size hit the hard bound in any mode. A separate subdued “Soft image” indicator can use `outputHeight/(sourceHeight×h)>1`; do not call that hard-limit status. Never accumulate hidden zoom beyond the floor, which would make the opposite button seem unresponsive.

### First implementation slice and risks

One session implements a minimal channel-addressed command dispatcher over the existing manager, continuous size state, push/pull gestures, and the three mode integrations. It also makes render failure hold the last successfully rendered program buffer rather than publishing raw source, and guards recovery events against manual ownership. No multi-input extraction or hardware abstraction is needed yet.

Files: CameraManager.swift for intent/mode arbitration and pan; ShotComposer.swift for stable anchors and size/follow separation; CropEngine.swift for size dynamics and constraints; OperatorPill.swift for controls; ContentView.swift/CropPreviewView.swift for truthful limit and adjustment state. Extend [FramingRegressionTests.swift](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOSTests/FramingRegressionTests.swift) with behavioral cases rather than UI snapshots.

Acceptance: stationary locked subject zooms while Steady Follow holds; pan zoom works mid-sweep, at both dwells, and through zero travel; no edge spill or quality overshoot; release/focus loss stops; reversing at a limit responds immediately; Manual cannot be stolen by reacquisition; injected render failure holds the actual prior program. Rehearse one-handed while watching only the program pane, including quick recovery. Measure step/breathing artifacts and frame-path latency separately from intentional slow zoom duration.

## 3. Workstream 2 — Two or three independent inputs

### Capture architecture

The premise that macOS requires one camera per capture session is too strong: Apple explicitly describes Mac multi-camera support predating the iOS MultiCam API. A single session with explicit per-device connections is an option. Separate sessions are also a viable architecture to test against the actual capture devices. **Recommend a Channel owning one session**, so N channels means N sessions; these are complementary concepts, not competing options. [Apple’s multi-camera explanation](https://developer.apple.com/videos/play/wwdc2019/249/).

One shared session centralizes graph configuration but couples start/stop and reconfiguration failures. Per-channel sessions give Alfie independent source replacement, format verification, and failure recovery. They do not create USB bandwidth, synchronize cameras, or guarantee any particular UVC driver combination. The proof must use two real devices simultaneously and inspect delivered dimensions and cadence, not merely advertised formats.

| Per channel | Shared show/app state |
| --- | --- |
| Stable ID and display name; source device identity | Device discovery, permission prompts, exclusive device allocation |
| Session, configuration queue, capture delegate/gate and generation | Show standard and session coordinator |
| PersonDetector, observation store, identity gallery, ShotComposer | Fair perception/render resource scheduling |
| CropEngine motion state, mode, preset, zoom, pan phase, manual point | Command dispatcher and operator focus |
| Latest input and last-good rendered output, timestamps and health | Output router, display allocation, one CMIO connection initially |
| Channel diagnostics and future HardwareLink binding | Session diagnostics aggregation and extension activation |

A channel produces a **channel program frame**; it does not own all external output infrastructure. Move routing outside CameraManager before instantiating it twice. Otherwise each instance would create its own virtual-camera sink and fight over the same extension and persisted Program Display selection.

Give capture start/stop and configuration their own serial executors instead of multiplying blocking work on MainActor. Keep short deterministic state transitions on MainActor initially. Use latest-frame mailboxes, per-channel generations, one render in flight per channel, and bounded fair admission to GPU work. Address CropEngine’s static queue explicitly: naïve duplication serializes every lane through it. Begin with a measured bounded scheduler, not unlimited per-camera GPU work. A camera’s unplug, failed start, or restarted detector must not reset its siblings.

### Operator UI and outputs

**Default church workflow: fixed independent feeds to the ATEM.** Show only the selected channel’s wide pane and its actual rendered output pane, with small A/B/C selectors in the pill showing mode and health. Clicking B changes the control target and previews; A continues tracking and its cable output remains A. Label both panes and the pill with B. The right badge reads “B · to ATEM input 2,” not “On Air”: without ATEM tally Alfie does not know what is being broadcast. Return to Wide always acts on the visibly selected channel; Manual is beside the other modes. Voice commands name a channel explicitly once multiple channels are running.

Do not turn selection into a cut. The preferred output mapping is A → dedicated external display/HDMI path → ATEM input 1, B → another display/HDMI path → ATEM input 2; add C only when the Mac, adapters, cables, and switcher support it. The operator window stays on its own screen. Extend DisplayOutputSink to take an explicit endpoint configuration and replace the one global display preference. Never remap a disconnected output onto another channel’s display. A missing physical route remains missing; a virtual-camera fallback is not an ATEM failover. Current display behavior is documented in [DisplayOutputSink.swift](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/DisplayOutputSink.swift:8).

| Alternative | Appropriate use | Recommendation |
| --- | --- | --- |
| One selected program, one HDMI/virtual camera | Proof and installations with only one available output | Build first, but keep selection and explicit Take separate. |
| Multiple Program Displays | Independent ATEM inputs with physical cables | First operator-usable multi-input target. Qualify exact display topology. |
| “Alfie A/B/C” virtual devices | OBS-centered installations | Later; does not create HDMI/SDI paths. Requires device IDs, channel-aware XPC, per-device queues and lifecycle. |
| Direct SDI via Desktop Video | More physical outputs when display topology is insufficient | Separate future output project, not part of this first architecture slice. |

For the one-output proof, keep the right pane pinned to the routed program, label the left pane “Control B,” and use an explicit pill Take action to route B. Permit Take only after a fresh B render exists; retain A until the atomic switch. This proof UI is intentionally limited: inspect B’s crop overlay on the left. Do not mislabel a B preview as the current downstream feed. The operator-usable fixed-feed layout removes this mismatch without building a video wall.

### Performance budget

No M3/M4 throughput claim is established by the repo. Qualify two channels first; treat three as conditional, with Pro/Max-class machines candidates rather than requirements or guarantees. Device delivery, USB controller topology, external-display support, thermals, and memory matter as much as chip name. Retain the show’s 50/59.94/60 cadence; do not silently reduce a live output to compensate.

| Item | Initial engineering budget / gate |
| --- | --- |
| Frame period | 20 ms at 50 fps; 16.7 ms at 60 fps. |
| Compose plus state work | Aim below 1 ms/channel/frame; inspect aggregate MainActor occupancy. |
| Render | Aim at ≤4–5 ms/channel at the target resolution; with a serialized scheduler, all channel renders plus overhead must fit the frame period. Existing <8 ms single-channel aspiration is insufficient for three at 60 fps. |
| Perception | Start at 10–12 Hz per tracking channel, ROI/≤1080p, one job per channel at most; none for unneeded manual/pan perception. |
| Detection scheduling | At the spec’s historical 16.4 ms/job, 2×12 Hz consumes about 394 ms of serialized work/s; 3×10 Hz about 492 ms/s. This excludes added contention and is not an ANE utilization measurement. |
| End-to-end | Measure each route against the 100–150 ms aspiration. Bound queue age; never trade smoothness for a growing backlog. Detection age and composition response lag need separate measurements. |
| Soak | 60 minutes at exact show rate with two moving subjects, route health, dropped frames, memory, p95/p99 stage times, observation age, thermal behavior, and unplug/reconnect exercises. |

For scale: one 3840×2160 BGRA frame is 33.2 MB; at 50 fps that is 1.66 GB/s of pixel payload. Three channels total 4.98 GB/s before render reads, output writes, or previews. This is a memory-traffic illustration, **not USB wire bandwidth**; device transport formats differ. Six retained 4K frames already cost about 199 MB per channel. Inventory all capture/proxy/render/preview/extension buffers and enforce bounded retention.

Shed in this order: redundant UI updates and nonessential diagnostics; pose/face-refresh frequency while preserving acquisition identity requirements; detection cadence down toward 8 Hz; proxy height toward 720 only if subject size remains sufficient; then the declared lower-priority channel’s tracking service. Manual/pan should remain smooth. Signal “Tracking reduced” and hold when observations become stale. Do not weaken identity matching just to keep green status. If capture/render itself still misses budget, mark the configuration unsupported and reduce inputs or resolution during setup; perception shedding cannot fix saturated ingest.

### First two slices

**Architecture proof:** extract a channel boundary, run A tracking while B pans with zoom, and route one chosen output through the existing sink. Verify independent lock, mode, crop, cancellation, start failure, and hot-unplug. Keep one extension device and no automatic switching.

**Operator slice:** A/B selection in the pill, labeled dual panes, two fixed Program Display endpoints, per-route health, and one-click selected-channel recovery. Qualify physical delivery at the ATEM before enabling C. [ProgramOutputManager.swift](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ProgramOutputManager.swift), [DisplayOutputSink.swift](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/DisplayOutputSink.swift), ContentView.swift and OperatorPill.swift change; [CinematicCoreXPCProtocol.swift](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/Shared/CinematicCoreXPCProtocol.swift) and the extension remain single-output until multiple virtual devices are explicitly scheduled.

## 4. Workstream 3 — Speech to action

### Vocabulary and trust

Start with eight command forms. Each includes “Alfie”; after multi-input, require a camera number as well. Parse a complete short utterance using a finite grammar, not substring matching inside ordinary booth conversation.

| Spoken form | Same action as the pill |
| --- | --- |
| “Alfie, detect” | Arm Detect; operator still taps the intended person. |
| “Alfie, track” | Enter Crop/Track only with a valid acquired lock. Otherwise show “Pick a subject.” |
| “Alfie, manual” | Adopt current shot into Manual. |
| “Alfie, pan” | Enter Auto Pan from the current shot. |
| “Alfie, back to wide” | Explicit Return to Wide. |
| “Alfie, waist up” | Select/reset Waist Up. |
| “Alfie, push in” | One eased, bounded zoom increment, initially about 10%. |
| “Alfie, pull out” | One equal proportional zoom-out increment. |

The channel form is “Alfie, camera two, pan.” Later add “full body,” “wide framing,” “unlock,” “cancel detect,” and “start session.” Reserve “back to wide” for the safety action; do not ambiguously map bare “wide” to both a preset and uncropped recovery. “Alfie has the pastor” is useful status language, but should not be an executable phrase: neither role recognition nor subject selection by name exists. Spoken lock can only confirm an already selected candidate, never guess which person is the pastor.

Always-listening commands require the wake prefix on a dedicated operator microphone. Recognizing the word in a transcript is a **wake gate**, not proof of who spoke. Use a close-talk/headset mic, voice activity detection, strict phrase matching, deduplication, and final/stable recognition results. Partial hypotheses may update “Hearing…” but cannot move a shot. Reject ambiguous utterances; do not infer the nearest command. A small wake-word model is a later option only if measured false activations justify it; its sole authority is opening a short command window.

Show “B · Push in” briefly above the pill when accepted, or “B · No locked subject” when rejected. No spoken reply over booth audio. Mic mute is one small pill toggle, with a persistent listening/muted state. Hold-to-talk is a useful alternative for noisy booths, but the first requested slice still proves the wake-prefix path. Manual interaction cancels pending voice motion and invalidates in-flight transcripts captured before that interaction. A voice command cannot arrive late and undo Return to Wide.

Keep spoken Stop session out of the first eight. If added, require a short-lived **inline** confirmation: “Stop all feeds? Say ‘Alfie, confirm stop’,” expiring after five seconds and cancelled by other input. No modal. The existing isolated physical Stop button remains immediate. Hardware emergency stop is immediate and never uses this confirmation rule. Voice Start remains optional while stopped; default microphone capture stops with the session, so enabling voice Start would explicitly require a separate “listen while stopped” choice.

### Recognition options

| Stack | Tradeoff | Decision |
| --- | --- | --- |
| SFSpeechRecognizer, requiring on-device recognition | Small integration, system language assets; offline support is recognizer/locale-dependent and must be checked. Recognition lifecycle/restarts need a full-service test. | Useful comparison implementation; never silently fall back to cloud. |
| Bundled whisper.cpp model | Versioned offline assets and support across the requested macOS 14 baseline; adds model packaging, compute, and short-utterance false-transcription testing. | **Default for the requested 14+ product.** Begin by evaluating `base.en`; increase model size only for measured command accuracy gains. |
| SpeechAnalyzer / SpeechTranscriber | Newer Apple on-device stack with managed model assets; does not satisfy a macOS 14 baseline. | Preferred Apple-native candidate if the actual 26.2 deployment target is intentional. |

Apple requires checking `supportsOnDeviceRecognition` before relying on `requiresOnDeviceRecognition`; unavailable support must disable voice, not enable network recognition. [Apple support property](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition), [on-device request requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition).

whisper.cpp supports Apple Silicon, Metal and Core ML encoder acceleration. Bundle and warm the selected assets before service; avoid assuming first-run compilation is instantaneous. Those platform capabilities do not establish booth accuracy. Compare recorded commands, silence, HVAC, music and PA bleed, then measure interference with Vision and rendering. [whisper.cpp upstream documentation](https://github.com/ggml-org/whisper.cpp).

SpeechAnalyzer is worth evaluating if the minimum OS changes: Apple documents on-device transcription and pre-installable language assets. Assets must be ready before Sunday. [Apple’s SpeechAnalyzer introduction](https://developer.apple.com/videos/play/wwdc2025/277/).

### First slice

Add an off-frame-path microphone/recognizer service, utterance IDs, wake-prefix grammar and eight mappings into the command dispatcher. No LLM is needed: the only speech ML task is acoustic recognition; deterministic code validates vocabulary, channel, state and expiry. Keep audio in a bounded in-memory buffer and discard it after recognition; recording examples for evaluation should be an explicit diagnostic choice.

Acceptance: airplane/offline operation after setup; no actions on sermon/music/silence corpus; one action per utterance; channel cannot change while a phrase is being resolved; UI recovery invalidates old voice work; model failure leaves video running. Aim for command acknowledgment within about one second after the phrase ends, then measure on the show rig. A corpus with zero false actions is a release gate, not a guarantee against future false activation.

New speech files should depend on Command, not CameraManager. OperatorPill/ContentView add only mic state and feedback. There is no speech stack to extend today. Permissions and the OS decision are covered below.

## 5. Workstream 4 — Hardware, after zoom and channels

### Step A: connection protocol, before mechanics

| Transport | Church-booth tradeoff |
| --- | --- |
| USB CDC serial | Plug-in, inspectable traffic, no radio/network dependency; cable length and device identity must be managed. **First bench connection.** |
| USB HID | Potentially driverless, structured reports; less convenient human debugging and a different firmware contract. |
| Wired Ethernet | Better candidate for a long booth-to-tripod run; adds addressing, pairing and network permissions. Good later transport behind the same link abstraction. |
| USB-to-RS-485 | Another long-run option; adds transceivers and electrical design but preserves a serial-style protocol. |
| BLE/Wi-Fi | Cable convenience at the cost of pairing, RF contention and reconnection variability. Defer for motion control. |
| GPIO hat | Requires an external controller/computer; the Mac has no appropriate direct motor interface. Keep electrical control on the MCU. |

Do not assume a long passive USB cable will serve the stage. Pick the installation transport after measuring the actual run. The first connection win can still use short USB on the bench.

Define a `HardwareLink` boundary for discovery, capability negotiation, connect/disconnect, arm/disarm, priority stop, command submission, acknowledgments and telemetry events. Its users see typed operations and health, not a serial port name or MCU vendor. A simulator and a USB implementation share the contract. Firmware owns motor deadlines and limits; a Mac timer is insufficient when the app crashes.

Lifecycle: disconnected → discovered → negotiating → connected/disarmed → explicitly armed → stopped/faulted. Discover by stable device identity and confirm Alfie protocol identity after opening; never enable arbitrary serial equipment. Negotiate major protocol version, capabilities and device boot ID. Reconnect, device reboot, app wake, version mismatch and heartbeat loss always return disarmed. No replay of the last velocity and no automatic homing on reconnect.

Use bounded newline-delimited JSON for v1: human-readable records, maximum record size, validated numeric ranges and explicit error replies. Each record carries protocol version, connection/session ID, sequence number and type. Motion records also include a device-clock expiry associated with the current boot/lease; do not compare unsynchronized Mac timestamps. Reject expired, duplicate and old-session commands. Duplicate acknowledgments must not renew motion. Use recent telemetry/lease exchange to establish device-clock validity, and retain at most the newest unsent motion command so serial backlog cannot execute an old move later.

Example wire shapes, not implementation:

```json
{"v":1,"session":"s7","seq":18,"type":"ping"}
{"v":1,"session":"s7","seq":19,"type":"enable","motion":false}
{"v":1,"session":"s7","seq":20,"type":"estop"}
{"v":1,"session":"s7","type":"ack","ack_seq":20,"accepted":true,"state":"estopped"}
{"v":1,"session":"s7","type":"telemetry","boot":"b3","device_ms":41200,"armed":false,"position_valid":false,"position":null,"velocity":0,"limits":[],"fault":null}
```

Step B adds `velocity`/`goto` records with bounded values and expiry. Acknowledgment means accepted, not arrived. Telemetry reports requested target separately from measured position/velocity, plus limit switches, motor current, position validity, fault, boot ID and last accepted sequence. Unsupported measurements stay null rather than echoing the command as if measured.

Starting protocol timing: 10 Hz link heartbeat, 20–50 Hz telemetry/motion updates, ≤200 ms motion lease, ≤300 ms link-loss threshold. These are **test proposals**. Every move, including goto, requires lease renewal; a heartbeat alone must not perpetuate stale movement intent. The MCU stops within its local deadline even if USB remains attached and the Mac stalls. “Stop” means a verified stop/hold behavior appropriate to the mechanics, not blindly disabling power and allowing the arm to coast. A local physical emergency stop and end-limit enforcement remain independent of the app. Existing motor-controller protocols illustrate the watchdog pattern; this is not a recommendation to adopt that controller. [ODrive watchdog documentation](https://docs.odriverobotics.com/v/latest/manual/can-protocol.html).

**First hardware slice:** app discovers one device, pings, negotiates, enables communication with motor motion disabled, receives truthful telemetry and latches an emergency stop. Firmware/simulator tests cover unplug, app termination, sleep, malformed records, duplicate/late commands, MCU reset and reconnect. Verify signed sandbox access on the deployment Mac. No actuator geometry, image servo, or motor motion belongs in this slice.

### Step B: one linear actuator mapping to yaw

Use the specified sign convention: extension turns the tripod left; retraction turns it right. Verify polarity at low speed during setup and persist it per device/channel. Commands are Extend, Retract, Stop and Go to normalized position, where normalized position describes calibrated actuator stroke, not image position.

For an ideal planar linkage, a fixed anchor distance `d` from the yaw axis and an attachment radius `r` give `L(θ)² = d² + r² − 2dr cos(θ−θ₀)`. This is a design model, not a calibration from dimensions we do not have. Its derivative changes across travel, so uniform actuator speed does not imply uniform angular speed. Start with measured stroke-to-yaw calibration over a restricted monotonic range; avoid dead-center geometries and poor mechanical advantage. Do not extrapolate across reversals or singularities.

For tracking, use the subject’s position in the **wide source image** relative to a desired sensor anchor as visual error. Do not use only post-crop error: digital recentering could conceal that the subject is reaching the sensor edge. A low-gain, bounded proportional yaw-velocity controller with deadband is the v1 baseline; start without integral action to avoid windup at travel limits. Translate requested yaw velocity through the local calibrated linkage mapping. The MCU runs its faster encoder/current/limit loop. Image error is the truth for framing; encoder and limits remain authoritative for physical travel safety. Neither can replace the other.

For Auto Pan, use a separately calibrated physical yaw range and endpoint dwell. Do not send the digital crop’s normalized phase directly as actuator extension: crop travel is not mechanical stroke. Preserve the operator’s Pan action but dispatch it to the channel’s configured digital or hybrid controller. Avoid simultaneous independent physical and digital sweeps.

Calibrate minimum/maximum stroke, neutral yaw, permitted yaw range, braking distance, current/force thresholds and position validity before enabling motion. Home slowly only during setup, or use verified absolute position sensing; never home blindly during a service. Hard end switches and firmware soft limits complement, rather than replace, mechanical stops. A pull-only cable needs a return/tension mechanism: retracting a slack cable cannot push the pan arm. Reversal must take up slack at bounded force/speed, or reject motion if position is uncertain. These mechanics are unresolved until actuator and mount details exist.

### Hybrid recommendation and recovery

**Use slow physical yaw plus digital zoom and fine pan.** Digital motion handles short changes immediately. Physical yaw recenters sustained sensor-space error and restores digital travel margin. Coordinate both through one channel controller with a larger/slower physical deadband than the digital follow band; do not run two independent controllers trying to center the same displayed image. During physical movement, update the digital crop from the current source image so it can absorb small residual errors without fighting yaw.

On stale/lost vision, stop physical tracking promptly using observation age and the motion lease; do not continue moving for the composer’s 10-second HOLD interval. Preserve the digital last shot when possible. On link loss, hardware halts locally, Alfie shows “Arm stopped · digital only,” and digital tracking can continue within the remaining field of view. Do not automatically widen or return the tripod to home because a cable dropped. At a physical limit, stop outward motion, retain digital margin if available, and show a limit status.

Return to Wide must now stop/disarm physical movement **and** invoke the digital wide recovery in one action. It reveals the full current camera view; after yaw it cannot promise the original whole-stage shot. Returning the head to a saved home is a separate deliberate action, not emergency recovery. Manual likewise stops physical autonomy before handing over the digital crop. Add a persistent “Arm STOP” pill control when hardware is connected; it preserves the current digital shot. Stop session stops/disarms hardware before shutting video down.

**First motion slice after Step A:** one calibrated actuator, low-speed bounded manual jog/goto, local watchdog/limits and observed stop distance. Then closed-loop visual recentering with digital zoom; then physical auto-pan. Rehearse target loss, camera freeze, crop limit, slack, jam and link dropout. No robotic-arm IK, multi-axis head, autonomous home search, optical-zoom protocol, or tripod replacement in v1.

New hardware transport/firmware and calibration modules sit behind Channel/Command; CameraManager’s existing pan loop supplies behavior to separate, not a reusable actuator coordinate system. CropEngine remains a pixel renderer. ProgramOutputManager does not control motors.

## 6. Shared architecture before deep speech or hardware work

Introduce the smallest useful Command boundary in zoom; extract channels in multi-input. Do not build a general broadcast framework in advance.

```text
Pill / validated speech / hardware operator events
                       ↓
      Command(target, origin, id, epoch, expiry)
                       ↓
            deterministic dispatcher
          ↙                         ↘
  channel control state        show/session actions
     ↓          ↓                    ↓
 crop intent   hardware intent    output router
     ↓          ↓                    ↑
 CropEngine  HardwareLink    channel program frames
```

Use typed actions: Detect/CancelDetect, SelectSubject(point), Unlock, SetMode, SelectPreset, BeginZoom/EndZoom, ZoomBy, ReturnToWide, Start/StopSession, and eventually Take, Arm/Disarm and EmergencyStop. A dispatcher result is accepted, rejected with reason, or completed; receipt is not proof that movement or delivery completed. Continuous ticks are channel state evolution, not a flood of bus messages.

Commands carry an explicit channel ID, including single-channel A today; global commands use an explicit show target. Capture the target and control epoch when a gesture or utterance begins, never resolve against whatever channel happens to be selected later. Coalesce pending zoom intentions. Return to Wide, manual override, Stop and faults cancel pending motion. Reject stale recognition and old hardware epochs. Safety stop outranks all motion; direct operator input outranks stale speech and automatic recovery. Tracking events cannot override a subsequent manual-mode change.

Hardware telemetry enters the same dispatcher as **typed observations**, not arbitrary executable strings. A remote physical stop event may map to EmergencyStop; reported position updates health/state. The deterministic controller decides any resulting action. Neither speech nor firmware telemetry gets privileged direct access to CropEngine.

A Channel needs stable identity, source configuration, control state/epoch, observation timestamps, motion state, last-good program buffer, health and optional hardware capabilities. Output endpoint identity is separate from Channel identity and operator focus. A show coordinator freezes show standard at start, starts channels independently, reports partial failure, and stops all outputs only for an explicit global Stop.

Preserve the current generation guards, but scope cancellation to the operation/channel. Tag program frames with channel, sequence, capture time, render time and freshness. A held frame stays the actual output; the operator overlay reports staleness without burning diagnostics into the clean feed. No automatic raw-source fallback, cross-camera cut, output reassignment or motor resumption on fault.

### Permissions and packaging

Current [app entitlements](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOS.entitlements) explicitly include camera, sandbox, IOSurface, app group and extension installation. The [project build settings](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/project.pbxproj:538) also enable audio-input and USB resource access, despite no speech feature. Inspect the signed app’s effective entitlements during implementation; do not infer them solely from the checked-in plist.

| Feature | Required/conditional additions |
| --- | --- |
| Zoom / more cameras | Reuse existing camera permission; no extra permission per channel. |
| Microphone | Ensure `com.apple.security.device.audio-input`; add `NSMicrophoneUsageDescription` and request microphone permission during setup. |
| Apple SFSpeechRecognizer option | Follow its authorization flow and include the appropriate speech usage description; qualify offline support before accepting commands. A bundled local recognizer does not need Apple Speech authorization. |
| USB serial | Add `com.apple.security.device.serial`; ensure USB entitlement if the chosen discovery/access API needs it. Prove CDC open/read/write inside the signed sandbox. |
| HID alternative | USB device access as appropriate to the implementation; no pretend keyboard injection or Accessibility permission. |
| BLE alternative | `com.apple.security.device.bluetooth` and Bluetooth usage description/permission when adopted; leave absent for serial v1. |
| Network alternative | `com.apple.security.network.client`; server entitlement only if accepting inbound connections. Declare discovery/local-network requirements applicable to the eventual API/OS. |

The CMIO extension remains video-only; microphone and actuator permissions belong in the host. No broad filesystem exception, unsandboxed motor helper, or new driver entitlement is justified by the proposed CDC path. [Apple sandbox entitlement reference](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html), [microphone protected-resource guidance](https://developer.apple.com/documentation/bundleresources/protected-resources), [speech usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsspeechrecognitionusagedescription).

### Decisions that would create expensive coupling

Making zoom another mode would prevent simultaneous Track/Pan plus zoom. Encoding zoom only inside presets would entangle operator motion with detection hysteresis. Letting both composer and UI own final size would produce breathing. Global zoom state would break channel independence. Using requested rather than rendered width for pan limits would make zoom transitions illegal. Treating a digital phase or crop center as actuator position would confuse sensor geometry with physical geometry. Binding output selection to operator focus would turn routine control into unintended cuts. Avoid all seven now; none requires implementing hardware early.

## 7. Recommended program sequence

| Session | Concrete deliverable | Dependency / completion gate |
| --- | --- | --- |
| Design now | This memo; settle output topology, OS baseline and size semantics. Capture baseline latency and current recovery behavior before changing it. | No implementation in this session. |
| 1 — Zoom | Minimal command boundary, hold/tap zoom in Manual/Pan/Track, consistent limits, mode ownership and last-good render behavior. | Pass motion/recovery cases and one-handed volunteer rehearsal. |
| 2 — Two-channel proof | Extract Channel; A tracking while B pans/zooms; one routed output. | Zoom semantics stable; real dual capture and failure isolation demonstrated. |
| 3 — Usable multi-input | A/B pill selection, truthful labeled panes, fixed physical feeds and route health. | Exact ATEM/display/capture topology plus full-service soak. Add C only after budget passes. |
| 4 — Speech | Offline wake-prefix recognition, eight deterministic commands, bounded zoom, feedback and stale-command rejection. | Command layer stable. Speech discovery may follow Zoom while multi-input proceeds; it must not delay sessions 2–3. |
| 5 — Hardware Step A | Simulator + USB device, versioned protocol, telemetry, enable-without-motion, emergency stop and watchdog failure tests. | Zoom and channel ownership established. Speech is not a technical prerequisite, though hardware remains last in the product sequence. |
| 6 — Hardware Step B, bench | Calibrated single-axis jog/goto, limit/current enforcement and measured safe stopping behavior. | Step A passes; actual mechanism and return/slack behavior known. |
| 7 — Hybrid rehearsal | Visual recentering plus digital framing, then physical pan; recovery on link/vision failure. | Bench mechanics safe and predictable; full video/actuator soak on the rig. |

Design now: model semantics, command authority, channel/output separation, protocol contract and acceptance gates. Build next: zoom only. Wait: third-channel promises, multiple virtual devices, direct SDI, speech-driven physical motion, and any multi-axis robotics. Update conflicting product documentation alongside the implementation sessions that settle those behaviors.

## 8. Questions for you — only decisions that change the design

Defaults below let later sessions start without reopening every choice. These are design decisions, not requests to implement now.

1. **Output topology:** A — independent HDMI/SDI feeds into separate ATEM inputs (**recommended**), or B — one Alfie-selected feed into one input? This determines whether the usable UI needs Take and separate control/program identities.
2. **Deployment baseline:** A — retain the requested macOS 14+ product and resolve the 26.2 project mismatch (**assumed here**), or B — formally require 26.2+? This changes compatibility work and the preferred native speech stack.
3. **Zoom ownership:** A — an operator-adjusted size stays fixed until a preset is selected (**recommended**), or B — preserve automatic subject-relative sizing with a persistent relative trim? This changes how approach/retreat behaves after a push-in.
4. **Image quality policy:** A — retain the current roughly 4× digital range with truthful softness/limit status (**recommended for continuity**), or B — stop at native output resolution unless explicitly overridden? This materially changes whether distant waist-up shots are possible.
5. **Voice use:** A — wake-prefixed commands on a dedicated close-talk microphone (**assumed for the requested first slice**), or B — hold-to-talk as the normal Sunday workflow? Also identify any required language beyond English; it changes model selection.
6. **Rig capacity:** A — qualify two inputs first (**recommended**), or B — make three simultaneous 4K inputs a first-release requirement? Provide the exact Mac/chip/memory, capture-device models, delivered rates and available display connections; these determine feasible outputs and budgets.
7. **Hardware location:** A — controller near the Mac with a short USB link, or B — controller at the tripod over a long booth-to-stage run? Give the approximate distance; the deployment transport depends on it.
8. **Mechanism:** A — a rigid bidirectional actuator with position sensing (**preferred baseline**), or B — a pull-only cable/pole arrangement with a separate return/tension mechanism? Stroke, mount geometry, limit switches, force/current sensing and whether power-off holds position determine calibration and safe stopping.
9. **Wide recovery after yaw:** A — stop the arm and show the current camera’s full view (**recommended**), or B — require an always-available original whole-stage safety view? B requires a fixed safety source/output strategy; a panned camera cannot guarantee that view with digital zoom-out alone.
