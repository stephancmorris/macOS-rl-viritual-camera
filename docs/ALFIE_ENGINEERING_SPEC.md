# Alfie — Engineering specification (current tree)

**Audience:** an engineer onboarding onto Alfie.  
**Authority:** the Swift sources in `CinematicCoreMacOS/`. If this file and `ALFIE_SPEC.md` disagree, **this file and the code win**.  
**Date:** 19 September 2026. Re-verify constants in the cited files before changing behavior.

Related:

- Product story: `ALFIE_SPEC.md`, `README.md`
- Next-program session briefs (paste one into Astra): `docs/astra-sessions/`
- Hardware cheap path: `docs/astra-sessions/HARDWARE-OPTIONS.md`

---

## 1. What Alfie is

Alfie (Autonomous Live Framing Intelligence Engine) is a **macOS church-booth camera operator**. It ingests one wide stage camera, lets a volunteer lock a speaker, digitally crops/pans/zooms that shot, and publishes a 1080p program feed.

It is **not** a switcher, NDI router, PTZ controller, or editor. Perception uses Apple Vision (ML). Framing and motion are **deterministic heuristics**. An RL `CinematicAgent` exists behind a developer flag and is not the shipping controller.

**Primary user:** a volunteer under time pressure. Recovery is always one action: Return to Wide, tap another subject from HOLD, or Stop session.

**Current shipping shape:** one camera, one program, four crop modes, tap-to-rung zoom, command dispatcher, Program Display + virtual camera.

---

## 2. Repository map

| Path | Role |
| --- | --- |
| `CinematicCoreMacOS/CinematicCoreMacOS/` | Host app: capture, detect, compose, crop, UI |
| `CinematicCoreMacOS/CinematicCoreExtension/` | CMIO system extension — virtual camera “Alfie” |
| `CinematicCoreMacOS/Shared/CinematicCoreXPCProtocol.swift` | Host ↔ extension XPC |
| `CinematicCoreMacOS/CinematicCoreMacOSTests/` | Framing, identity, cadence, rates, pipeline |
| `docs/astra-sessions/` | S2–S7 implementation briefs |
| `training/` | RL training (not Sunday-critical) |

**Open:** `CinematicCoreMacOS.xcodeproj`, scheme Alfie. Deployment target in the project is **macOS 26.2**. Product copy still says 14+.

**Entitlements (checked-in plist):** sandbox, camera, IOSurface, app group, system-extension install. Audio-input is a *build setting*, not in the plist. No serial entitlement yet.

### 2.1 Key types (where to start reading)

| Type | File | Owns |
| --- | --- | --- |
| `CameraManager` | `CameraManager.swift` | Capture session, detection plan, compose switch, zoom rungs, Program Output |
| `PersonDetector` | `PersonDetector.swift` | Vision requests, track UUIDs, locked Pass A matcher |
| `DetectionFrame` / `DetectionFrameStore` | `DetectionFrame.swift` | Latest Vision observation + the exact pixels analyzed |
| `FaceSignatureExtractor` / `LandmarkRatios` | `FaceSignatureExtractor.swift` | Feature-print crop + bone-structure veto |
| `ShotComposer` / `LockState` | `ShotComposer.swift` | Lock FSM, gallery, crop math, Steady Follow |
| `CropEngine` | `CropEngine.swift` | Spring motion, quality floor, CI render |
| `OperatorCommand` / `CommandDispatcher` | `OperatorCommand.swift` | Admission, epoch, tracking ownership |
| `OperatorPill` | `OperatorPill.swift` | Volunteer console |
| `ProgramOutputManager` | `ProgramOutputManager.swift` | Display vs virtual-camera route |
| `ShowStandard` | `ShowStandard.swift` | 1080p50 / 59.94 / 60, session-frozen |
| `DeveloperFlags` | `DeveloperFlags.swift` | Detection interval, clip playback, ML agent |
| `CinematicAgent` | `CinematicAgent.swift` | RL controller; `exposeMLAgentControls = false` |
| XPC protocol | `Shared/CinematicCoreXPCProtocol.swift` | Host ↔ CMIO extension |

### 2.2 Stage 3 Director API (open-stack snapshot)

Added 10 Oct 2026 for D-01. This section describes actual types on the open A-07 stack at [`ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42`](https://github.com/stephancmorris/macOS-rl-viritual-camera/tree/ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42/CinematicCoreMacOS/CinematicCoreMacOS/Director), not the older single-camera snapshot elsewhere in this file, merged main code, completed integration or qualified live behavior. The [recorded decisions](handoff/stage3-4/DECISIONS.md) govern product authority; code documents implementation status and does not override them. See the [product contract](auto-director/product-contract.md) and [event contract](auto-director/event-authority-contract.md).

Alfie is a live-event backup producer with static cameras and a present operator. Each input has one shot; preparation targets Preview, and any future qualified automatic cut uses the existing `ShowCoordinator.take` / `ProgramRouter` path. No parallel output, audio input or show-time network is added by the Director API.

Files below are under `CinematicCoreMacOS/CinematicCoreMacOS/Director/` on that stack:

| API / file | Concrete contract at A-07 |
|---|---|
| `DirectorAuthority` / `DirectorAuthority.swift` | Levels `off`, `suggest`, `assist`, `auto`, `backup`; actions `propose`, `prepare`, `take`; epoch-bound authority and typed cancellation events. Enable/handback checks current prerequisites and level qualification. `mayTake` and `autoTakeQualified` are false: no automatic Take is implemented by this API yet. |
| `DirectorShot` / `DirectorProposal.swift` | Wraps `OperatorCommand.Preset`: Stage `wide`, `fullBody`, `waistUp`; Webcam `wide`, `tight`. `isWide` and `title` derive from it; `order` is deterministic, Stage before Webcam. No independent mode/zoom-rung representation. |
| `DirectorProposal`, `DirectorLiveState`, `DirectorWorld` / `DirectorProposal.swift` | Proposal binds ID, policy/nomination revisions, target/shot/reason, authority epoch, channel revisions, route generation and host-clock creation time. Constructor refuses a target other than Preview. `ShowDirectorWorld` reads R2 state; authority is injected and this is not the later engine integration. |
| `DirectorProposalValidator` / `DirectorProposal.swift` | Typed stale reasons: `authorityRevoked`, `routeChanged`, `sourceRestarted`, `shotChangedByOperator`, `targetBecameProgram`, `sourceMissing`, `expired`, `requestReplaced`, `policyChanged`, `nominationChanged`, `evidenceUnavailable`. Validation is required again at the effect boundary, not only when choosing. |
| `DirectorPreparation` / `DirectorProposal.swift` | Intent/request/receipt/composition lifecycle. A bounded dispatch request is distinct from persistent composition/readiness; acknowledgement checks the matching result and current state. It neither cuts nor grants Program control. |
| `IdentityEvidence`, `ChannelEvidenceSample` / `DirectorProposal.swift` | Six identity cases: `confirmed`, `acquiring`, `holding`, `lost`, `ambiguous`, `unavailable`. Samples carry channel/time, lock phase, tracking/gallery state, optional target UUID/observation age, speed, settlement/crop/gesture flags and observed person count. Times/ages are host-clock seconds; speed is normalized frame units/s. No numeric identity confidence or `faceVisible` field. |
| `DirectorReadiness` / `DirectorProposal.swift` | Separate `prepare` and `cut` bars over R2 Take availability, identity, settled seconds, motion and crop landing. Explicit parameters make cut settlement at least as long and motion no greater than preparation. Cut requires landed framing regardless of the prepare motion flag. Neither bar blocks manual Take. |
| `DirectorEvidenceAdapter` / `DirectorEvidenceAdapter.swift` | Pure sample-driven adapter with explicit `maximumObservationAge`, `debounce` (seconds) and `stillSpeed` (normalized frame units/s). Emits availability, declared-loss and nomination-change events; exposes readiness inputs. No new detector, autonomous nomination or camera access. |
| `DirectorStyle`, `DirectorPreferences`, `SegmentType` / `DirectorPreferences.swift` | Preferences schema **2**, `version` plus styles keyed by `presenter`, `panel`, `performance`, `videoBreak`, `liveEvent`; required Live-event fallback. Style supplies durations, wide cadence, repetition, settle time, movement, on-air move rate and motion flag with no numeric study defaults. No saved authority level. See [exact fields/units](auto-director/shot-style.md). |
| `DirectorShotPolicy` / `DirectorShotPolicy.swift` | Ranks rule-eligible Preview candidates using injected parameters. `Candidate` has channel/shot, `subjectConfidence`, movement and an independent `isWide` field. `Abstention`: `invalidInput`, `minimumDuration`, `noEligibleCandidate`, `repetition`, `movement`, `noPreview`. Recommendation timing is advisory, not cut permission. |
| `DirectorJudge`, `DirectorJudgement`, `DirectorJudgeGate` / `DirectorJudge.swift` | Judgement carries `evidenceRevision`, host-clock `computedAt`, ranked candidates with optional probability, or abstention (`policy(...)`, `lowConfidence`, `notRecorded`, `nothingAllowed`, `invalidJudgement`). Gate checks revision/age and rule membership. `RuleJudge` has nil probability; a supplied probability is finite in [0,1] and distinct from candidate confidence. A probability threshold is an explicit study input. |
| `NextShotStatus.DirectorSection`, `DirectorConsoleControlling` / `DirectorConsoleAPI.swift` | Public levels Manual/Assist/Auto/Backup; activity/reasons in plain words; prepared input/shot, next input/optional countdown, per-level qualification, shot badges and optional run-sheet display. Launch is Manual with no handback or prepared/next-cut state. MainActor commands: set level, hand to Alfie, take over, cancel next cut, advance segment, override subject. Views do not call the router. |

Sitting 1 does not make missing implementation complete. Auto/Backup operator-Take nudges still need integration at this snapshot. Suggest's no-pause operator Take extends the recorded N1 wording; `.confirmed` as a face-visible proxy leaves a P1 evidence gap. Both are [AWAITING OWNER questions](auto-director/event-authority-contract.md#owner-questions), not decisions made by this spec. Source reviews also flag stale-evidence debounce, original-time loss in `RecordedJudge`, effective-fallback preference merging, negative person counts and oversized countdown formatting; qualification cannot assume those paths are already corrected.

Evidence must be labelled synthetic, recorded or live. Test success does not confer any level's rig sign-off. Numeric timing/motion/probability settings are study parameters, not production defaults. C3/AI-4 allow bounded metadata only, with 30-day expiry unless explicitly exported; no audio, frames, crops, embeddings or transcripts in Director logs, and no separate media collection without E3. AI-2 forbids network during a show. Names are operator-entered metadata, never inferred identities or children as inferred targets.

---

## 3. Process architecture

```
Camera / UVC capture card
        │
        ▼
┌──────────────────────────────────────────┐
│ Host app (@MainActor orchestration)      │
│  AVCaptureSession                        │
│  PersonDetector (Vision, off frame path) │
│  ShotComposer (lock FSM + crop math)     │
│  CropEngine (spring + CI render queue)   │
│  CommandDispatcher                       │
│  ProgramOutputManager                    │
└───────────────┬──────────────────────────┘
                │ XPC (IOSurface ID, zero-copy)
                ▼
┌──────────────────────────────────────────┐
│ CMIO system extension                    │
│  FrameQueue (max 5, drain newest)        │
│  Advertises “Alfie” camera               │
└──────────────────────────────────────────┘
                │
                ▼
     OBS / Zoom  │  and/or  │  Program Display
                 │          │  (fullscreen HDMI → converter → ATEM)
```

Mach service (app-group prefixed): `EPZDEPSV69.Morris.CinematicCoreMacOS.extension`. Extension checks caller signing ID `Morris.CinematicCoreMacOS`.

Install: app must live in `/Applications` or `~/Applications`. Xcode/DerivedData builds are refused (`SystemExtensionActivationManager`).

`CameraManager` currently **owns** capture, detection, composition, crop, **and** `ProgramOutputManager`. That is the main reason S2 exists.

---

## 4. Capture

**File:** `CameraManager.swift`

- `AVCaptureSession` with **no session preset** (macOS `.high` would clobber 4K).
- Prefer **3840×2160** BGRA at the show standard. Fallback: best 16:9 at that rate.
- After `startRunning()`, re-assert format — Elgato-class devices have been seen advertising 4K then delivering 1080p.
- **Frame rate is pinned:** `activeVideoMinFrameDuration` and `activeVideoMaxFrameDuration` both set to `ShowStandard.captureDuration` (50, 59.94 = 1001/60000, or 60). Not a range’s endpoints.
- `ShowStandard` is persisted (default **1080p50**) and **frozen** for the session at output start.
- Quality floor, zoom clamp, and HUD height use the **delivered** buffer size, not the advertised format.
- `CaptureFrameProcessingGate`: one frame in flight; surplus frames drop. Drops show up as `gate_drops_*` in soak CSV.
- Discovery: built-in wide + external; names containing `"Test"` filtered. Auto-picks first 4K-capable device.
- Alternate input: validation clip playback (`DeveloperFlags.exposeClipPlaybackControls = true`).

**Do not** treat advertised 4K as proof of 4K. Log line: `First frame delivered: WxH`.

---

## 5. Detection algorithm

**Files:** `PersonDetector.swift`, `FaceSignatureExtractor.swift`, `DetectionFrame.swift`, `CameraManager.swift` (plan + schedule), `DeveloperFlags.swift`

### 5.1 Design intent

Detection is **passive**. Vision does **not** run a full-frame crowd scan on every Sunday. The operator picks a person; then Vision tracks that person in an ROI. Re-acquisition after loss is the only full-frame scan.

ROI **does not** make each Vision request cheaper. The locked-mode win is **dropping the face request**, not the ROI itself.

### 5.2 Vision requests

| Request | When |
| --- | --- |
| `VNDetectHumanRectanglesRequest` (`upperBodyOnly = false`) | acquiring, lockedROI, reacquiring |
| `VNDetectHumanBodyPoseRequest` | same |
| `VNDetectFaceLandmarksRequest` | acquiring + reacquiring + periodic gallery refresh — **not** in lockedROI |

Default rect revision is Revision1; high-accuracy mode uses Revision2. Confidence threshold **0.5**. Max **5** persons.

If source height **> 1440**, a GPU proxy at **1080** height is built for Vision. The full-res buffer is kept for crop and face prints. Handler orientation: `.up`.

Measured cost in comments: ~**16.4 ms** wall per Vision run at ≤1080p proxy. Face landmarks ~**1 ms** when run.

### 5.3 Detection modes

```
off            passive; no Vision
awaitingTap    Detect armed; still no Vision (no boxes on screen yet)
acquiring      rect + pose + face, ROI (tap column or locked pad)
lockedROI      rect + pose only, padded ROI around the subject
reacquiring    rect + pose + face, full frame (HOLD / WAITING)
```

Plan: `CameraManager.currentDetectionPlan()`.

| Lock state | Mode | ROI | Face |
| --- | --- | --- | --- |
| inactive, Detect off | off | — | — |
| Detect on, no tap | awaitingTap | — | — |
| Pending tap | acquiring | tap column | yes |
| acquiring | acquiring | locked ROI | yes |
| tracking | lockedROI | locked ROI | no |
| tracking + gallery refresh | acquiring | locked ROI | yes, ~every 0.4 s |
| hold / wideWaiting | reacquiring | full frame | yes |

**Tap ROI:** full-height strip, half-width **0.28** (~56% of frame) centered on the tap.  
**Locked ROI:** last subject box × **1.8**, clamped to the unit square.

### 5.4 Scheduling (off the frame path)

- `DeveloperFlags.detectionFrameInterval = 2` — Vision at most every **2nd** eligible frame if no job is in flight.
- Eligible-frame counter always advances (`eligibleFrameCount % interval == 0`).
- At 50 fps the newest box is typically **20–40 ms** stale — inside the crop spring.
- Normal path: `Task { await personDetector.processFrame }` — the compose loop does **not** wait.
- **Exception:** a pending tap is **awaited inline** so lock feedback is immediate.
- One detection at a time (`detectionInFlight`).
- `DetectionFrameStore.maximumAge = 0.5 s`. `isFresh` means the observation ID changed. Stale work is dropped via generation tokens.
- Overlay / stats UI mirrors at **15 Hz**.
- `DetectionFrameStore` keeps one latest observation. `maximumAge = 0.5 s`. `isFresh` means the observation ID changed. Identity extraction **must** use `DetectionFrame.pixelBuffer` (the pixels Vision saw), not the newer render frame. Stale work is dropped via generation tokens.

### 5.5 Track UUIDs (two-pass matcher)

Each Vision result:

1. Drop tracks unseen for **1.0 s**.
2. **Pass A (locked):** `lockedTargetID` binds first via `resolveLockedAssignment`. Reference box is the **last known box**, not a velocity projection (avoids jumping onto an occluder).
3. **Pass B:** remaining detections ↔ tracks, greedy best score.
4. Unmatched detections get new UUIDs.

**Unlocked matching:** IoU > **0.2** OR centroid distance < **0.15**. Velocity clamp ±**2.0** frame-widths/s.

**Locked jump gate:** allowed distance = `min(0.35, 0.12 + |v| × timeSinceSeen)`.

**Instant accept** (no probation) if:

- IoU vs reference ≥ **0.30**
- That IoU ≥ best IoU to other established tracks (>0.5 s old)
- Best identity score ≥ runner-up × **1.15**

**Probation** otherwise: **3** consecutive frames, or **8** if an occluder is contesting. Candidate must IoU > **0.5** with the previous probation box.

**Identity score** (`PersonDetector.lockedMatchScore`):

1. Hard reject if centroid is outside the jump radius.
2. Hard reject if area ratio (min/max of the two boxes) ≤ **0.33** (child-vs-adult guard).
3. Score = `0.6 × areaRatio + 0.25 × aspectRatio + 0.15 × (1 − distance/allowed)`. Size dominates because a speaker cannot change area suddenly; position is last because they *can* move.

If Vision returns **zero** rects but a track is < **0.3 s** old, a box is synthesized at 0.5× confidence **without a face**. Pose can also carry forward < 0.3 s.

Pose-to-body: IoU > 0.2; keypoints need ear/nose and root/hips confidence > **0.3**. Face-to-body: face centroid inside the body box.

### 5.6 Face gallery and re-acquisition

`VNGenerateImageFeaturePrintRequest` on a **full-res** face crop padded **15%** per side.

| Gallery | Value |
| --- | --- |
| Max entries | 8 (FIFO) |
| Capture spacing | 0.4 s |
| Ready | **3** prints before lock promotes / re-acq is allowed |

Landmark ratios (eye spacing, eye–nose, eye–mouth, mouth width). Typical same-person L2 < **0.05**, different > **0.10**.

Re-acquisition (HOLD / WAITING) uses best-of-gallery print + landmark veto (**0.10**). Thresholds: **0.62** if ≥2 faces, **0.55** if solo; winner must beat runner-up by **1.25×** and persist **3 consecutive fresh** observations. Scoring is async; bind happens next tick via `pendingReacquisition`.

If acquisition dies with fewer than 3 prints, automatic re-acq is **disabled**. The operator must tap.

`stagePriorityScore` exists in `ShotComposer` and is **not** used for lock/select. Selection is tap + UUID stickiness only.

---

## 6. Lock state machine

**File:** `ShotComposer.swift` (`LockState`)

```
inactive
   │ Detect + tap
   ▼
acquiring  ── gallery ≥3 ──► tracking
   │ 1.5 s no subject (grace)
   │ or 8 s wall timeout
   ▼
inactive

tracking ── subject UUID missing ──► hold (10 s, last shot)
   ▲                                    │
   └── UUID returns ────────────────────┤
                                        │ 10 s expires
                                        ▼
                                   wideWaiting
                                        │ face re-acq × 3 frames
                                        ▼
                                     tracking
```

Unlock (pill tap or Return to Wide) returns to inactive and clears the lock.

| Constant | Value |
| --- | --- |
| Acquire grace | 1.5 s |
| Acquisition timeout | 8 s |
| Discovery timeout (Detect, no tap) | 12 s |
| HOLD | **10 s** then pull back to wide |
| `targetHoldDuration` (0.75 s) | CropEngine warm-target — **not** the lock HOLD |

During hold / wideWaiting, `primaryPerson()` is nil. CameraManager applies `pullBackToWide` on hold expiry.

**Direct re-acquire without Detect** is allowed from HOLD and WAITING (`canDirectlyReacquire`). From idle, Detect must be armed first — the preview has no boxes until then.

**Retarget:** press-and-hold on the wide pane while locked. A miss leaves the current subject on air.

### Recovery controls and retained identity (R1)

The pill reflects the composer state: inactive says **Pick subject**; acquiring says **Acquiring…**; tracking says **Locked**; the 10-second HOLD says **Recovering**; and wideWaiting says **Searching**. HOLD keeps the last program crop for its full 10 seconds, then the composer pulls back to wide while preserving its face gallery. This timer and the face matcher are unchanged.

**Resume** is an explicit operator command. It may grant tracking authority only while the current composer state retains usable subject evidence: a ready gallery bound to the tracked subject in tracking/HOLD, or a ready retained gallery in wideWaiting. A track UUID without a ready gallery can continue its current lock, but it is not sufficient to restart recovery after ownership was revoked. Resume does not select a new person or bypass acquisition; wideWaiting stays wide until the existing matcher confirms the returning subject. If ownership was revoked and that evidence is absent, the control reads **Pick subject** and the operator must select someone through Detect/tap. A healthy, still-owned lock continues to read **Locked** even while its gallery is filling. Resume never changes Pan or Manual mode implicitly; the operator must explicitly request it.

**Return to Wide** is an explicit release. It clears the composer lock and retained gallery, revokes tracking ownership, and leaves no Resume candidate. A later attempt to resume a command created before Wide is rejected by the command epoch; a newly created Resume without retained evidence is also rejected. Asynchronous recovery results are admitted only for the current composer lock generation and visibility revision, with fresh observations, and only while tracking owns control. Pan, Manual and explicit Wide retire that work. Automatic HOLD expiry to wideWaiting retains ownership so recovery may continue under the same lock.

---

## 7. Composition (how the crop is chosen)

**File:** `ShotComposer.compose`

Crop is built from a tighter **tracked-subject box**, then expanded to the smallest valid output rectangle for the preset.

### 7.1 Stage shot sizes

Subject-relative height = `subjectBounds.height × subjectHeightFraction`, then clamped.

| Preset | Height fraction | Livestream min / max | Portrait min / max |
| --- | --- | --- | --- |
| Wide | 4.0 (~70% of frame) | 0.70 / **0.85** | 0.65 / 0.85 |
| Full Body | 3.0 (~55%) | 0.55 / **0.85** | 0.45 / 0.85 |
| Waist Up | 1.15 (~35%) | 0.35 / **0.80** | 0.30 / 0.85 |

`ALFIE_SPEC.md` still says Full Body ≤95%. **Code is 85%.** The Wide *preset* is a visible crop (≤85%). **Return to Wide** is the uncropped picture (`OperationMode.wide`).

Webcam (subject-height fractions): Wide **1.30** (min crop 0.40), Tight **0.95** (min crop 0.30).

Do not confuse `ShotPreset` (Wide / Full Body / Waist Up on the pill) with `ShotFraming` (`chestUp` / `waistUp`). Framing is a leftover top-anchor axis (`0.62` / `0.82` of subject height). Operator shot choice is `ShotPreset`.

**Anchoring:** Wide / Full Body center on subject midY. Waist Up / tight / webcam top-anchor from subject top + headroom. Tight vertical anchor smoothing **0.35**.

**Inner tracked box:** pose head/waist band when available; otherwise 97% of detection height from the top.

### 7.2 Stability

- **Size hysteresis 5%:** small height chatter reuses last size, recenters on a fresh position.
- **Deadzone** default **5%** of frame; shrinks to **0.5%** when smoothed velocity > **2%/s**. Framing change bypasses once.
- **Steady Follow** (default tuning): hold-band = `deadzone × 2` = **10%** of program width; vertical half-band 0.75× horizontal. Settle **240 ms** (12/50 s) to start holding; **40 ms** to exit. While holding, **no new crop target**. Observation gap **150 ms**.
- Default tuning bundle: smoothing **0.10**, autoPan **0.02**, deadzone **0.05**, targetHold **0.75 s**.

### 7.3 Quality floor

`CropEngine.QualityFloor.forSource(height)`:

```
minCropHeightPx = max(height / 4, 240)
minCropHeightFraction = minCropHeightPx / height
```

≈ **4×** linear digital zoom. A 2160 source floors at 540 px (~0.25); a 1080 source floors at 270 px. This is a degeneracy limit, not “native 1080 looks good.”

`ZOOM LIMITED` is set when the **composer’s desired** height is below that floor. Manual/pan historically did not compute an equivalent status the same way; zoom-limited UI also reads `CropEngine.isZoomLimited`.

Crop is **not** fenced by stage margins. Margins affect selection scoring only (and that score is unused). The crop can ride to the sensor edge.

---

## 8. Crop motion, modes, and zoom

**Files:** `CropEngine.swift`, `CameraManager.swift` compose switch

### 8.1 OperationMode

| Mode | What drives the rectangle |
| --- | --- |
| `wide` | `widestSafeCrop()` — true full frame on 16:9; else largest undistorted output-aspect region. **Not** the Wide *preset*. |
| `autoTracking` | `ShotComposer.compose`. If no person, hold `lastTrackingCrop`. |
| `manualCrop` | Operator center (`manualCropPoint`) + preset/zoom size |
| `autoPan` | Deterministic left/right sweep of current width. Phase += `autoPanSpeed × 3 × dt`. Slow 0.01 ≈ 33 s crossing, Normal 0.02 ≈ 17 s, Fast 0.03 ≈ 11 s. **1.5 s** dwell at each visible edge (`autoPanPauseDuration`). `placePan` + `jumpToTarget` — no spring lag on the sweep. Vertical center = `autoPanHeight` (default 0.5) |

Entering `.autoTracking` requires a locked subject. Entering Auto Pan still assigns mode through the dispatcher; T5b (`enterAutoPan` lifecycle, stop Vision) is **not** done.

### 8.2 Zoom (current: one rung per tap)

**Not** hold-to-zoom. Pill `ZoomShotButton` dispatches `beginZoom(direction)` on tap. Release does nothing. `endZoom` is cancel (focus loss / stop / faults).

**Stage ladder:** Wide → Full Body → Waist Up  
**Webcam ladder:** Wide → Tight

- Wide: Push in only.  
- Waist Up / Tight: Pull out only.  
- Mid-ladder: both.  
- Opposite tap while a move is in flight **reverses** (swaps origin/destination).
- From uncropped `wide` mode, Push in enters **manualCrop** then moves toward the next legal rung.
- **Tracking** destination height comes from `shotComposer.destinationHeight(for:)` (needs a known subject height). **Manual/pan** use fixed heights: Wide **1.0**, Full Body **0.8**, Waist Up/Tight **0.5**.
- Size interpolates in log-space in `CropEngine`. On land, the destination preset is applied.

Selecting a preset on the segmented control clears an in-flight zoom and re-applies framing.

### 8.3 Render

- Snapshot crop on MainActor (`tickInterpolation`).
- Core Image crop-scale on a **process-wide static serial queue** `com.cinematiccore.cropRender`. Lanczos if scale < **0.7**, else bilinear.
- Default output **1920×1080**.
- Displayed crop overlay at 15 Hz.

**S2 implication:** a second `CropEngine` would share that queue unless it is replaced by a fair scheduler.

### 8.4 Last-good program

On render failure or stale generation, publish `lastGoodProgramBuffer` and set `isProgramHolding`. Pill: “Holding last good program.” **Never** fall back to raw source.

This is **not** the 10 s subject-loss HOLD.

---

## 9. Command dispatcher

**File:** `OperatorCommand.swift`

```
OperatorCommand
  target:  cameraA | session
  origin:  operatorUI | safety | automaticRecovery
  id, epoch, expiry (~2 s)
  action:  detect, cancelDetect, selectSubject, unlock,
           setMode, selectPreset, beginZoom, endZoom,
           moveManualCenter, returnToWide, startSession, stopSession
```

Rules:

- Epoch must match; `accept()` increments it.
- Duplicate IDs rejected (last 64).
- `automaticRecovery` origin is rejected at admission; recovery uses `admitRecovery` only while `trackingOwnsControl`.
- Manual / Pan / Return to Wide revoke tracking ownership so a late re-acquire cannot steal the mode.
- Session start/stop must target `.session`.

**There is no `cameraB`, voice origin, Take, Arm, or EmergencyStop yet.** Those are S2 / S4 / S7.

---

## 10. Operator console

**Files:** `ContentView.swift`, `OperatorPill.swift`, `CropPreviewView.swift`, `InspectorDrawer.swift`

- Full-bleed dual pane: left = wide IOSurface, right = **actual program buffer**.
- Pill (bottom): lock state, Detect, presets, Crop / Manual / Auto Pan, Push in / Pull out, Return to Wide, Stop session.
- Lock copy: idle / awaiting tap / acquiring / locked / recovering (HOLD) / searching (WAITING).
- Inspector (right drawer): camera, format, composition, output route, modules, diagnostics + Reveal Logs.
- Tap on wide: Detect pick, manual reposition, or HOLD/WAITING re-acquire.
- Press-and-hold: retarget while locked.
- Program Display badge is **On Air** for the pixels Alfie submitted — not ATEM tally.

Developer-only (flags off for church): ML agent, training recorder. Clip playback flag is currently **on**.

---

## 11. Output

**Files:** `ProgramOutputManager.swift`, `DisplayOutputSink.swift`, extension provider

| Route | Role |
| --- | --- |
| **Program Display (default)** | Borderless fullscreen on a chosen display. Free-runs at compositor refresh. HDMI → converter → ATEM. No genlock. |
| **Virtual camera (fallback)** | XPC IOSurface IDs. Extension queue max **5**, drain newest. Host retains last **10** sent buffers. Playout clock matches `ShowStandard`. |

One route is active. One persisted Program Display ID (`ProgramDisplaySelection`).

Latency stages recorded: detection, compose, cropRender, xpcSend, total, mainActor. Rolling 5 s window, published every 0.5 s.

**End-to-end 100–150 ms** and **60 min soak** are still **unvalidated on the show rig** (T1). Do not claim them as measured.

---

## 12. Diagnostics and tests

Diagnostics (sandbox `Documents/CinematicCore/Diagnostics/`, METRICS schema 2): per capture, a manifest `alfie_session_<stamp>.json` (build and source fingerprint, OS, machine, source device/profile/requested and delivered size, configured capture rate and selection reason, route, show standard, what each route's handoff means, the column definitions and what is not observable), a soak CSV with one row per ~5 s window, and a memory CSV for the same windows. Every CSV column is defined in `DiagnosticsLog.columns` with its stage (capture upstream → delivered → admitted → detection → render → routed → handoff → repeated → presented), unit, window and provenance. Losses are counted per stage (AVCapture drop, gate skip, render failure, route refusal, no route) and HOLD repeats separately from new frames. `presented_fps` is always `unknown`: neither the Program Display compositor nor the virtual-camera client reports presentation. Recording starts on the capture's first processed frame (a `detection start` note marks Vision load), windows close on time even during a stall, and Stop flushes the last window as `partial`. `CinematicCoreMacOS/scripts/diagnostics_report.py` summarises a session as Markdown; release evidence runbooks live in `reports/release-1/`.

`imageCacheFlushInterval = 0` (off). Autorelease is drained per work item.

| Suite | Covers |
| --- | --- |
| `FramingRegressionTests` | Commands, zoom rungs, pan, last-good, pill width, clip timing |
| `CinematicCoreMacOSTests` | Cadence gate, crop hysteresis, hold, gallery throttle |
| `OutputRateRegressionTests` | ShowStandard exact times, handshake |
| `PipelineLifecycleTests` | Gate + CSV schema |
| `LockedTrackMatcherTests` | Locked geometry/policy |
| `IdentityRegressionTests` | Re-acq evidence, freshness |
| UI tests | Boilerplate only |

**Not covered:** live camera, real XPC, extension install, DisplayOutputSink on a real second monitor.

---

## 13. Where `ALFIE_SPEC.md` is stale

| Spec | Code |
| --- | --- |
| Full Body ≤95% | Livestream Full Body max **85%** |
| Tap a detected person | Detect first; no boxes until then (except HOLD/WAITING) |
| Soft failure holds indefinitely | HOLD is **10 s** then wide |
| Virtual camera primary | Program Display is the default route |
| Resume Tracking on the pill | Not shipped (T2) |
| macOS 14+ | Project **26.2** |
| Six-control pill | Detect + zoom rungs + Manual / Auto Pan also exist |

---

## 14. Roadmap gaps — what must be built

Session briefs (implementation prompts) live in `docs/astra-sessions/`. This section is the **engineering gap analysis**: current vs desired, and the concrete work.

### 14.1 Already in the tree (do not rebuild)

- Single-camera capture, Vision perception, ShotComposer, CropEngine
- Command dispatcher + epoch/ownership
- One-rung Push in / Pull out
- Last-good program hold
- Program Display + virtual camera
- Soak CSV / latency stages
- Locked matcher + face re-acq

### 14.2 Still church-MVP (P1 / P2) — not S2–S7

| Gap | Why it matters | Implement |
| --- | --- | --- |
| T1 / T1a / T1b show-rig proof | 60 min soak, 1080p50 display, pan hitch, e2e latency unmeasured | Human + write numbers into the spec |
| T2 Resume Tracking on the pill | HOLD/WAITING are labeled; `resumeTracking()` is unused | Wire a Resume control; keep Return to Wide |
| T3 volunteer install README | Extension refuses non-Applications | Document Applications + approval path |
| T5a eased auto-pan | Sweep is still constant-velocity `jumpToTarget` | Ease without turning pan into tracking |
| T5b `enterAutoPan()` | Pill still SetMode; Vision can keep running | Lifecycle enter/leave; dispatcher SetMode |

### 14.3 S2 — Channel extraction (two cameras, one output)

**25 September 2026 design authority:** [ALFIE_MULTICAMERA_SPEC.md](ALFIE_MULTICAMERA_SPEC.md) defines the current work-unit sequence, frame contracts and gates. The historical S2 scope below is an architectural overview, not a single implementation assignment.

**Missing today:** second session, second detector/composer/engine, channel-addressed commands, output moved out of `CameraManager`, fair render scheduler.

**Must implement:**

1. `Channel` / `ChannelID` owning one `AVCaptureSession`, detector, composer, crop, mode, zoom, pan, last-good, health.
2. `ShowCoordinator` owning discovery, exclusive device claim, `ShowStandard` freeze, `CommandDispatcher`, `OutputRouter`.
3. Move `ProgramOutputManager` **out** of `CameraManager`. Channels only emit program frames + metadata.
4. Replace `CropEngine` static `renderQueue` with a **bounded fair** scheduler (one render in flight per channel).
5. Capture start/config off MainActor (serial executors).
6. `OperatorCommand.Target` gains `cameraB` (or `channel(id)`). Target captured when the command is created.
7. Proof UI: right pane = **routed** program; left = **control** channel wide; explicit Take; no silent cut.
8. Isolation tests: B unplug / fail-start does not reset A.

**Do not implement in S2:** A/B pill, two HDMI outputs, second CMIO device, SDI.

**Done when:** two real devices; A tracks while B pans/zooms; one routed output; A survives B’s death.

### 14.4 S3 — Program / Preview (supersedes dual-output design)

**Design authority:** [ALFIE_MULTICAMERA_SPEC.md](ALFIE_MULTICAMERA_SPEC.md). The single-camera application has not yet implemented these R2 contracts.

**Must implement:**

1. Two independent camera channels; Preview controls never implicitly change Program.
2. Right pane shows routed Program; left shows the prepared rendered Preview, with an explicit wide-source selection view.
3. Exactly one output route: one Program Display or one CMIO feed to the downstream receiver.
4. Explicit atomic Take exchanges Program/Preview only with an eligible current frame.
5. Program labels describe Alfie's submitted feed, not downstream ATEM tally.
6. Return to Wide / presets / zoom capture the visibly controlled channel; live edits require explicit selection.

**Resolved:** one feed with Take. Hardware combinations and sustainable limits require the measured R2 matrix; unknown hardware is not certified.

**Do not implement:** Alfie A/B virtual devices, Desktop Video SDI, video wall.

### 14.5 S4 — Speech to action

**Missing today:** no mic pipeline, no recognizer, no `.voice` origin, no grammar, no `NSMicrophoneUsageDescription` in the shipping story.

**Must implement:**

1. Off-frame-path mic + VAD + offline recognizer (default: bundled whisper.cpp `base.en`; SFSpeech only if on-device is proven; no cloud fallback).
2. Finite grammar, wake prefix `Alfie`, eight commands mapping 1:1 to pill actions (see `docs/astra-sessions/S4-speech-to-action.md`).
3. `OperatorCommand.Origin.voice`. Same dispatcher. Capture channel at utterance start.
4. Pill: mute + Hearing / accepted / rejected. No spoken booth reply.
5. Audio-input entitlement in the **signed** plist. Bounded in-memory audio, discard after recognize.
6. Tests: accept/reject phrases, stale utterance cannot undo Return to Wide.

**Do not implement:** LLM crop policy, “Alfie has the pastor,” spoken Stop, speech → motors.

**Must not delay S2/S3.**

### 14.6 S5 — HardwareLink (no motion)

**Missing today:** no serial stack, no `HardwareLink`, no simulator, no e-stop command.

**Must implement:**

1. `HardwareLink` on a channel (or `cameraA` stub if S2 is not merged yet).
2. USB CDC transport + in-process simulator sharing newline JSON (`v`, `session`, `seq`, `type`).
3. Lifecycle: disconnected → discovered → negotiating → connected/**disarmed**.
4. Hello, ping, telemetry, `enable` with `motion: false`, latched `estop`.
5. `com.apple.security.device.serial`; prove sandbox CDC on the deployment Mac.
6. Firmware or documented Pico sketch that **keeps PWM low**.
7. Tests: unplug, app kill, malformed/duplicate/late records, reboot → new boot id, stays disarmed.

**Do not implement:** velocity/goto that moves a motor, BLE, image servo.

**Buy for this slice:** Pico + USB + e-stop + LED. Not the actuator yet. See `HARDWARE-OPTIONS.md`.

### 14.7 S6 — Actuator bench

**Missing today:** no arm/disarm, no jog, no calibration store, no measured stop.

**Must implement:**

1. Records: `arm`, `velocity` + lease, `goto` (only if `position_valid`), `stop`, `clear_estop`.
2. Heartbeat must not perpetuate motion. MCU watchdog ≤200 ms.
3. Honor end-of-stroke switches; persist polarity.
4. Inspector-only jog (not the Sunday pill).
5. Calibration blob per device: sign, u min/max, neutral, max PWM.
6. Human: measure stop distance; USB-yank-while-moving must halt.

**Hardware:** ~$30 12 V 100 mm actuator, H-bridge, 12 V 2 A PSU, printed clevis + pan-arm clamp. Bidirectional. Pull-only is DECIDE Q8-B and needs a return mechanism.

**Do not implement:** visual P-controller, physical auto-pan, pill jog.

### 14.8 S7 — Hybrid yaw + digital framing

**Missing today:** no combined controller; digital pan phase must never become actuator stroke.

**Must implement:**

1. One channel controller: digital zoom/fine pan + slow physical yaw from **wide-image** error (not post-crop only).
2. P-only yaw, physical deadband **wider** than Steady Follow. No integral in v1.
3. Stale vision → stop physical immediately (do not ride the 10 s digital HOLD).
4. Link loss → local halt + `Arm stopped · digital only`.
5. Return to Wide and Stop session: **stop+disarm hardware and** digital wide in one action. No auto-home.
6. Pill: **Arm STOP** when a link is connected.
7. Auto Pan stays digital unless a hybrid-pan flag is on — never dual independent sweeps.

**Do not implement:** IK, second axis, optical zoom, voice → yaw, safety-wide second camera (Q9-B).

### 14.9 Docs after each landing

Update `ALFIE_SPEC.md` / `README.md` when a session is operator-accepted. Brief: `docs/astra-sessions/DOCS-align-spec.md`. Do not rewrite historical Phase 1 files.

### 14.10 Shared work that must exist before S4/S5 go deep

| Building block | Introduced | Used by |
| --- | --- | --- |
| `CommandDispatcher` | S1 (done) | S3 targeting, S4 voice, S5/S7 estop |
| `Channel` + show coordinator | S2 | S3 outputs, S5 link binding |
| `ProgramRouter` + one output route | R2 routing / Take work | Sunday ATEM |
| `HardwareLink` | S5 | S6/S7 |
| Hybrid controller | S7 | — |

### 14.11 Explicitly out of the current roadmap

Third input, multiple CMIO devices, direct Blackmagic SDK SDI, NDI, cloud speech, multi-axis robotics and RL as default controller. Mac App Store preparation is in R2 with separate distribution/privacy/compatibility gates; an iOS port is not included.

---

## 15. How to run a change without breaking Sunday

1. Prefer `CommandDispatcher` over writing `activeMode` from a new path.
2. Keep compose deterministic. Do not put ML in the crop controller.
3. Do not publish raw source on render failure.
4. Do not bind “what the operator is looking at” to “what the ATEM is receiving.”
5. Add behavioral tests next to `FramingRegressionTests` / `LockedTrackMatcherTests` rather than UI snapshots.
6. After a user-visible change, run the one-handed pill rehearsal: Detect → lock → Crop → Push in → Auto Pan → Return to Wide.
7. If the change is a next-program session, use the matching file in `docs/astra-sessions/` as the agent prompt — one session at a time.

---

## 16. First-week reading order

1. This file, §3–8 (pipeline + detection).
2. `CameraManager.processFrame` compose switch.
3. `ShotComposer.tick` + `LockState`.
4. `PersonDetector` Pass A locked matcher.
5. `OperatorCommand` + `OperatorPill`.
6. `docs/astra-sessions/README.md` before touching S2+.
