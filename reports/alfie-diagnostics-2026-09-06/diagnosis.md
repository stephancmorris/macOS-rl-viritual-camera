**Alfie diagnostic review — 6 September 2026**

Alfie still detects the speaker and moves the program crop in both supplied recordings. The evidence points to a combination of deliberate hold-and-follow behavior, weaker recorded motion cadence, and defects in identity tracking and recovery. It does **not** establish that the 23 August commit alone caused every reported problem. Several serious defects predate it; that commit also introduced framing and output inconsistencies.

No application source, settings, installed extension, or release package was changed. This review produced only this report and its evidence files. Repository documents and code comments were treated as claims and design context, not instructions to implement changes.

**Evidence and scope**

Reviewed source: `22d7524ca998d70ba709b27a217abacdfc0223d3`, committed 23 August 2026 at 12:41 Sydney time, compared with its parent `cfb699f` and relevant earlier history. You confirmed 23 August is the latest source commit. The working tree contains modified release binaries, but no application source changes. The exported executable was modified on 6 September at 08:00 and identifies itself as version 1.0, build 2. Those values do not establish which source/settings produced each recording.

The review covered capture and scheduling, Vision detection and matching, face signatures, lock state transitions, crop composition/interpolation, preview overlays, program display, XPC/CMIO output, and the existing tests. The experimental RL controller is disabled in the shipping configuration and is not a leading suspect.

Both movies were decoded with AVFoundation and inspected through timestamped frames across their full durations, with half-second extraction and closer inspection around lateral movement. Exact-time extraction was used for the delivered evidence. Neither movie contains an audio track.

| Recording | Duration | Encoded dimensions | Video track nominal rate |
| --- | ---: | --- | ---: |
| Before | 68.41 s | 1896 × 856 | 52.16 fps |
| After | 59.10 s | 1896 × 856 | 23.28 fps |

These are **screen-recording rates**, not verified camera input or program-output rates. The clips show different passages of the service and do not constitute a controlled replay of identical input. They cannot establish end-to-end latency, HDMI/ATEM behavior, or a memory leak.

**What the recordings show**

| Interval | Observation | Interpretation |
| --- | --- | --- |
| Before, approximately 10–20 s | The green subject rectangle follows the speaker moving left and returning; the white program crop changes position. | Detection, association and composition are operating. The baseline also allows off-center movement. |
| After, approximately 27.5–29.5 s | The green subject rectangle moves right with the speaker while the white crop and yellow holding guides stay substantially parked. | The subject is still detected. Much of this apparent tracking delay is consistent with Steady Follow deliberately withholding crop updates inside its band. |
| After, approximately 30–37 s | The crop moves right and framing catches up; green tracking continues. | This interval is not a permanent detector/cadence freeze. It does not prove an identity switch. |
| Both clips | “Waist Up” is selected while the crop labels say “WIDE.” Cyan person boxes sometimes appear on the projected background figures. | There is a confirmed labeling mismatch and background-person ambiguity in the baseline as well as the after clip. |

See [before at 16 s](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/reports/alfie-diagnostics-2026-09-06/evidence/before-00m16s.jpg), [before at 20 s](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/reports/alfie-diagnostics-2026-09-06/evidence/before-00m20s.jpg), [after at 27.5 s](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/reports/alfie-diagnostics-2026-09-06/evidence/after-00m27.5s.jpg), [after at 29.5 s](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/reports/alfie-diagnostics-2026-09-06/evidence/after-00m29.5s.jpg), and [after at 35 s](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/reports/alfie-diagnostics-2026-09-06/evidence/after-00m35s.jpg).

The lower encoded cadence in the after recording can itself make movement look substantially less smooth. Without capture/output telemetry from that recording, attributing this entirely to Alfie's processing would overstate the evidence.

**Confirmed defects and material behavior changes**

**1. High priority: the ordinary matcher bypasses locked-subject rejection.**

[PersonDetector.swift:806](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/PersonDetector.swift:806) records the locked UUID as used only when Pass A accepts a candidate. [Pass B at line 839](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/PersonDetector.swift:839) then considers every unused track, including that rejected locked UUID, with weaker IoU/centroid rules. The intended coast/probation decision is therefore not authoritative.

I compiled temporary copies of the production detector and ran its actual full `assignTracks` method. Three separate probes confirmed immediate reassignment after Pass A rejected a candidate: probation required, distance outside the locked radius, and incompatible body size. This can move the lock to a nearby person or projected person without satisfying the intended safeguards. Existing tests exercise the pure Pass A resolver, so they miss the bypass.

History: the general second pass dates to May; July's stricter locked policy still allows this escape route. **Pre-existing, not introduced on 23 August.** Not demonstrated as an identity switch in the supplied clips.

**2. High priority: face coordinates and face pixels can come from different frames.**

The asynchronous detector stores only `[DetectedPerson]` in [CameraManager.swift:357](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:357). Later frames reuse those detections, but [the call to `tick` at line 1252](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:1252) passes the current camera buffer. Gallery capture at [ShotComposer.swift:1128](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift:1128) crops that current buffer using the earlier detection's face box and landmark vector. Reacquisition follows the same pattern.

For a moving head, the extracted image can be offset, include background, or contain another overlapping face. This undermines the very gallery intended to stabilize identity. Acquisition/gallery filling also does not require `isFresh`, permitting repeated observations to initiate captures when the time throttle allows them.

History: the frame/pixel mismatch follows the 26 July asynchronous detection change. The 23 August gallery refresh makes it relevant throughout an established lock. **Confirmed data-flow defect; the size of its accuracy impact needs synchronized source-frame replay.** A result should carry its source buffer or a face crop from that buffer, timestamp, and session identity.

**3. High priority: reacquisition counts callbacks as consecutive sightings.**

[ShotComposer.swift:1380](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift:1380) chooses the winner among cached recent scores; [line 1426](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift:1426) increments that winner's confirmation counter whenever *any* candidate finishes scoring.

A production-logic probe supplied one score each for A, B, and C. A received three confirmations and became pending for reacquisition despite having only one observation. A crowd can therefore defeat the intended three-frame evidence requirement. Separately, [line 1250](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift:1250) returns before clearing counters when no faces are visible, so “consecutive” evidence can survive an empty frame.

History: May. **Reproduced pre-existing defect.** Confirmations must belong to distinct observations of the candidate being confirmed, with explicit handling of missing observations and stale async work.

**4. High operational impact: recovery now waits 10 seconds while the body track expires after 1 second.**

[ShotComposer.swift:760](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift:760) changed HOLD from 2.5 s to 10 s on 23 August. [PersonDetector.swift:602](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/PersonDetector.swift:602) still removes tracks unseen for 1 s. During HOLD, [CameraManager.swift:845](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:845) continues scanning the old padded ROI without face reacquisition. A returning speaker whose old UUID has expired cannot satisfy HOLD's same-UUID recovery check, even if another detection sees them.

The program can remain parked on the old location until the 10-second timer expires, at which point wide face reacquisition becomes available. A probe confirmed HOLD at 9.9 s and WIDE-WAITING after 10 s.

**New intentional policy change with an adverse interaction**, not an unexplained Vision failure. It increases the existing recovery dead period by 7.5 s. The supplied clips do not show a full loss/return cycle, so this is a code-confirmed operational issue rather than a video-confirmed event.

**5. Medium priority: acquisition can remain amber indefinitely, then abandon on one missing frame.**

In [ShotComposer.swift:1011](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift:1011), a visible body causes acquisition to return without checking an overall deadline. If its face is unavailable, the gallery never becomes ready. The missing-body branch instead compares against the original acquisition start, not the last successful sighting.

The probe remained acquiring after 120 s of a visible body with no face, then became inactive on the first missing frame at 120.02 s. This can look like detection that never locks or unexpectedly gives up. **Pre-existing and reproduced.** Acquisition needs distinct total-time and last-seen timers, plus a clear incomplete-face-gallery state.

**6. Medium priority: the new crop caps reverse the preset ordering.**

The new [framing caps at ShotComposer.swift:2026](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift:2026) allow Full Body to reach 95% of source height, but cap Wide at 85%. For the same large synthetic subject, production composition returned:

| Preset | Crop height |
| --- | ---: |
| Wide | 85% |
| Full Body | 95% |
| Waist Up | 80% |

Thus “Full Body” can be wider than “Wide.” **Introduced on 23 August and reproduced.** The ordering should hold across subject scales and both output aspects. This does not explain the selected Waist Up shot's lateral pause, but it is an additional regression outside detection.

**7. Medium priority: show-standard support is internally inconsistent.**

There are three distinct issues:

- [CameraManager.swift:1765](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:1765) selects a supported rate *range* and assigns its endpoint durations. For a range spanning 30–60 fps, selecting 50 does not set both durations to 1/50. This pre-existing approach does not enforce the selected standard. Apple's [frame-duration documentation](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideominframeduration) describes the duration as a rate limit.
- [CinematicCoreExtensionProvider.swift:199](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreExtension/CinematicCoreExtensionProvider.swift:199) creates every advertised format with min/max duration fixed at the initial 50 fps. The new live rate setter changes the timer/property to 59.94 or 60 without rebuilding those advertised capabilities. Reopening a client does not rebuild the existing extension's format array. Apple's [stream-format contract](https://developer.apple.com/documentation/coremediaio/cmioextensionstreamformat) defines these as supported durations. **New inconsistency in the 23 August implementation.**
- [CameraManager.swift:2020](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:2020) sets `hasPushedPlayoutRate` after sending an unacknowledged message. Explicit sink disconnect resets it, but direct/automatic XPC reconnect does not. After an extension restart, a 59.94/60 session can keep sending without restoring its rate; the extension defaults to 50. **New reconnect-state defect.**

These are code-confirmed inconsistencies; downstream rejection/judder depends on device and consumer behavior. They are not proven causes of the local program-preview behavior in either movie. The virtual-camera timer changes also cannot fix the separate Program Display/HDMI route.

**8. Medium priority: operator overlays misdescribe the active framing and recovery.**

[ContentView.swift:58](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ContentView.swift:58) uses the legacy `shotFraming.title`, whose waist-up enum is named “Wide,” rather than the selected stage `shotPreset`. This directly explains the contradictory labels visible in both recordings. The green rectangle is also derived from the composer's tracked region, not necessarily the raw Vision body rectangle; its percent is detection confidence, not identity confidence.

[ContentView.swift:55](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ContentView.swift:55) hardcodes `isRecovering: false`. The overlay iterates current detections rather than drawing an independent last-known recovery box, so the intended amber recovery treatment cannot reliably explain a missing lock. **Pre-existing UI defects**, made more confusing by the longer HOLD.

**9. Medium priority: performance diagnostics measure something different from their description.**

[CameraManager.swift:1500](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:1500) records elapsed time across the whole async frame method, including the off-main render wait. [ProgramOutputManager.swift:330](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/ProgramOutputManager.swift:330) describes that number as main-thread occupancy. The new off-main rendering makes that interpretation invalid: elapsed time is not time spent executing on the main thread.

Similarly, [CameraManager.swift:1236](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:1236) records a short scheduling/consumption interval as detection latency while real Vision work ran earlier. `vision_mean_ms` is a better measure of that work, but still does not establish observation age or motion-to-output latency. `frames_total` counts accepted handoffs; it does not acknowledge downstream display of each frame.

**Confirmed measurement limitations, especially relevant after the async changes.** They can make a latency improvement appear proven when it is not. The capture gate remains closed across `await renderCrop`, so moving rendering off-main does not by itself guarantee delivery of every incoming frame.

**Why the framing can feel late even with a green box**

Steady Follow intentionally permits ±5% of the *whole source frame* horizontally at its default 10% band width. A 35%-width crop turns that into roughly ±14% of the visible program width. It then waits for two fresh out-of-band detections before following. Detection runs at every second eligible frame, and eligibility excludes frames with detection already in flight.

After release, the crop follows a critically damped spring. [CropEngine.swift:537](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/CinematicCoreMacOS/CinematicCoreMacOS/CropEngine.swift:537) now uses stiffness `0.10 × 600 = 60` at the default setting. The continuous model's steady ramp delay is approximately `2 / sqrt(60) = 0.258 s`, before observation age and band waiting; discrete frame updates modify the exact result. This contradicts treating the spring alone as inside a 100–150 ms motion-lag budget. Doubling stiffness reduces this model's lag by about 29%, not half.

The 23 August boost on band exit should speed catch-up, while its 5% size hysteresis and vertical low-pass make the shot less reactive. These are multiple interacting control changes, not a simple detection accuracy fix. The recorded pauses are consistent with the band policy; the clips do not isolate whether the new spring/filter changes are the cause of the perceived deterioration. A same-source replay with identical settings is needed to rank their contribution.

**What the saved performance logs establish**

The app's existing diagnostics directory contains July and 23 August sessions, with no 6 September session there. These logs have no commit fingerprint; even the latest starts shortly before the reviewed commit was created.

- Early 23 August sessions, including `alfie_soak_2026-08-23_034717.csv`, show only isolated detections and many zero-detection windows while frames continue. That is consistent with the intermediate cadence starvation described in source history. The current cadence gate is corrected and its four existing tests pass; it should not be presented as a still-present deadlock.
- In `alfie_soak_2026-08-23_123927.csv`, successive steady windows report about 130 handoffs per 5.3 s: approximately 24.5 fps. Several windows contain 65 detections: approximately 12.3 detections/s. There are roughly 30–31 capture-gate drops per window. This does not demonstrate a 50-fps show pipeline, but the log does not identify input mode/rate well enough to diagnose the exact cause.
- That final session lasts only 33.9 s, with sampled footprint roughly 374–380 MB and nominal thermal state. It does not validate long-session memory stability. Earlier July logs show substantial growth and drops; those observations cannot be reassigned to today's build without matching telemetry.

No evidence here establishes that autorelease/cache changes are intrinsically wrong or that a memory leak caused the supplied after clip.

**Validation performed**

The normal unsigned `build-for-testing` succeeded with the unchanged project and the Metal source included. All **24 existing tests in five suites passed**. Initial sandbox-restricted attempts could not access required compiler/tool services; the normal build succeeded outside that restriction without installing tools. Those initial errors are not application build defects.

Independent probes compiled production detector/composer implementations with diagnostic methods injected into temporary copies. They reproduced the three locked-ID bypass cases, reacquisition overcount, indefinite acquisition/first-miss cancellation, the 10-second recovery boundary, and inverted preset ordering. These probes establish deterministic logic defects; they do not simulate Apple's live detector or downstream hardware.

See [probe results](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/reports/alfie-diagnostics-2026-09-06/evidence/logic-results.txt), [unit test log](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/reports/alfie-diagnostics-2026-09-06/evidence/unit-tests.log), [successful normal build log](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/reports/alfie-diagnostics-2026-09-06/evidence/build-unrestricted.log), [video manifest](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/reports/alfie-diagnostics-2026-09-06/evidence/manifest.json), and [reproduction script](/Users/stephanmorris/Documents/macOS-rl-viritual-camera/reports/alfie-diagnostics-2026-09-06/diagnostic-reproduction.py). The script writes only temporary source copies and runs no camera session.

**Recommended repair order — no fixes applied**

1. Make locked matching authoritative and bind identity extraction to the exact observation frame. Correct reacquisition evidence counting and invalidate work across session/target changes.
2. Align track lifetime, expanding search, and HOLD recovery; give acquisition meaningful deadlines and operator feedback.
3. Replay the same original camera clip on both revisions with identical settings. Measure observation age, detector rate, crop-center error, gate drops and program output cadence while varying one framing control at a time.
4. Correct preset ordering and overlays, then rate negotiation/reconnect behavior and diagnostics. Keep the memory changes separately measurable.
5. Validate on the actual capture card, Program Display/HDMI/ATEM route and virtual-camera consumers; include loss/return, projected people, occlusion, reconnect and a 60-minute soak.

A blanket rollback would remove some intentional recovery/UI/performance improvements while restoring other known issues. The stronger course is to correct the confirmed state/identity defects, then use matched replay to decide which framing and performance changes should be retained.

This is a completed offline diagnostic review of the supplied recordings, source and available logs—not a claim that live hardware, long-session behavior, signing/notarization, or every runtime path has been certified.
