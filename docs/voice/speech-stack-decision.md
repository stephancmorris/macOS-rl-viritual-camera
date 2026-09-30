# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| V1 Recognizer first? | whisper.cpp; on-device SFSpeechRecognizer; SpeechAnalyzer | SpeechAnalyzer/SpeechTranscriber spike first on current 26.2 baseline; benchmark whisper.cpp as explicit alternative | S4 recognizer | Yes, adapter boundary |
| V2 Command understanding? | Eight-command grammar; local LLM direct execution; grammar then LLM proposals | Grammar execution first, local LLM later proposes structured director instructions for review | S4 redesign/AD-PREFS | Yes; broader authority requalifies |
| V3 Listening gesture? | Continuous wake prefix; push-to-talk; both | Close-talk wake-prefix trial as card proposes, visible mute; offer push-to-talk if false-action gate fails | S4 UI/corpus | Yes |
| V4 Channel binding? | Unqualified current channel; explicit channel; allow Program by name | Require A/B with two inputs, bound at utterance start; Preview only initially | S4/CHANNEL-CMD | Yes |
| V5 Audio retention/privacy? | Disabled; local ephemeral; retained diagnostics | Explicit opt-in, local ephemeral only; no ordinary audio/transcript recording | S4/privacy | Stored/disclosed data irreversible |

Status: proposed redesign, not stack selection approval or audio collection. Sources accessed **2026-09-30**. The supplied `~/Downloads/stephan-mle-master-plan.md` was not present; July 2026 voice-directed/local-LLM direction is taken from Stephan's task, not an invented reading of that document.

## Baseline and stack comparison

`origin/r2/sol:docs/decisions/platform-baseline.md` records Xcode deployment target 26.2, while 14+ product text is inconsistent and lower-OS qualification absent. Keep 26.2 as engineering baseline for comparison; product sign-off and exact-floor launch remain separate. `ShowCoordinator.swift` / `makeCommand`, `ShowCommand`, `dispatch` and `OperatorCommand.swift` / `CommandDispatcher` provide command routing/epochs. There is no wired recognizer or voice origin at the R2 base.

| Stack | Verified capability | Tradeoff / qualification required |
|---|---|---|
| **SpeechAnalyzer + SpeechTranscriber** | Apple describes an on-device model with asynchronous analysis and final/volatile results; system-managed assets installed through AssetInventory ([WWDC25](https://developer.apple.com/videos/play/wwdc2025/277/), [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)) | Fits 26.2 direction; check hardware availability, locale and installed assets before enabling. System assets update, reducing exact model reproducibility; log OS/asset status and re-run corpus. No Alfie accuracy/latency result exists |
| SFSpeechRecognizer on-device | `requiresOnDeviceRecognition` is honored only where `supportsOnDeviceRecognition` is true ([Apple](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)) | Fail closed if unavailable; never default/cloud fallback. Runtime locale, authorization and session lifecycle need test on target Mac. Useful comparator, not justified as default simply because older |
| whisper.cpp / base.en candidate | Upstream supports macOS, local model files, Apple Silicon Metal/Core ML and VAD; first Core ML run may compile assets ([upstream README](https://github.com/ggml-org/whisper.cpp)) | Pin library/model hashes, review license/packaging, warm assets; measure CPU/GPU/memory alongside video. Bundled repeatability costs distribution and model upkeep. No vendor benchmark imported as Alfie performance |

`SpeechTranscriber.isAvailable` reports hardware/capability availability ([Apple](https://developer.apple.com/documentation/speech/speechtranscriber/isavailable)); OS version alone cannot guarantee it. Assets may require network installation during setup; “offline operation” means after verified installation, not offline first-run download. No silent recognizer substitution mid-service: model failure mutes voice and leaves video running. If SpeechAnalyzer fails corpus/workload gates, Stephan can choose the measured whisper alternative.

## Grammar versus voice-directed director

| Stage | Proposed capability | Gate |
|---|---|---|
| Text-only foundation | Complete utterance parser, no microphone, eight mappings | Deterministic accepts/rejects, duplicates/expired text and target-binding tests |
| Recognized grammar | Close-talk mic → final utterance → exact parser → same Preview command path | Privacy approval, false-action corpus, offline and compute tests |
| Local language model shadow | Parse “keep the sermon calm” into a proposed structured preference diff; no executable effect | Fixed schema, adversarial/ambiguous speech study, resource budget; no chosen model or size yet |
| Reviewed voice-directed director | Show interpreted scope, cue or style change; operator confirms; apply with pause/explicit resume | New AD-PREFS/UI qualification; no direct LLM router/crop/hardware access |
| Broader execution | Optional future bounded intent vocabulary after evidence | New decision, not an implication of July direction |

This staged path preserves the July ambition while rejecting direct freeform execution as the first speech slice. Speech recognition converts audio to text; a language model interprets intent; deterministic authority/readiness decides permission. Never merge those trust boundaries. Sermon content or a model-generated instruction is data until accepted through the operator interface.

## First executable vocabulary

All require wake prefix `Alfie`, final complete utterance and explicit camera A/B (or one/two) with two inputs. Case/punctuation normalization may be specified; no fuzzy substring or nearest-command match.

| Phrase suffix | Existing intent / precondition |
|---|---|
| detect | `.detect`; nomination still requires operator tap |
| track | `.setMode(.autoTracking)` only with valid lock; otherwise “Pick a subject” |
| manual | `.setMode(.manualCrop)` |
| pan | `.setMode(.autoPan)` under existing mode restrictions |
| back to wide | `.returnToWide`; bare “wide” rejects |
| waist up | `.selectPreset(.stage(.waistUp))` |
| push in | `.beginZoom(.pushIn)` one rung |
| pull out | `.beginZoom(.pullOut)` one rung |

Example: “Alfie, camera two, push in.” Unqualified phrase with two inputs rejects. Naming current Program rejects in initial voice scope even if Edit Live is active; changing that is a later live-edit voice decision. No spoken reply over PA; show channel + accepted/rejected reason near pill.

## Binding and race requirements

At utterance start, capture proposed `utteranceID`, mic-session generation, manual-intervention epoch, controlTargetRevision, current channel/role/sourceGeneration and channel epoch. At final parse, resolve explicit channel against that captured snapshot, not today's selected channel. Require same current Preview/control target and source generation; reject if Take/Edit Live/manual input/mute/Stop intervened.

`ShowCoordinator.makeCommand` currently binds **when called**, not at audio start, so calling it only after recognition is insufficient. Proposed adapter verifies the start token, creates/binds the existing command in the same serialized admission turn and dispatches without await; per-channel epoch and target revision are rechecked at effect. New `.voice` origin is proposed, with ordinary voice below physical UI and safety. Accepted voice revokes conflicting director authority just like a manual action. One action per utterance ID, expiry measured on host monotonic clock, late finals after Wide cannot undo it. Never hold a command for future readiness.

## Latency and false-action study

All numbers are **proposed starting targets**, frozen before testing: final-phrase-end→visible accept/reject p95 ≤1 s, p99 ≤2 s; utterance validity expires 2 s after end; maximum utterance buffer 10 s, then reject/erase. Rationale: short booth commands must not arrive after the operator has changed intent. Instrument capture onset/end, recognition final, parse, admission, visible feedback and actual effect; word error rate alone is insufficient.

Proposed initial corpus: 10 h sermon, 10 h worship/music, 10 h booth noise/silence; add exact command quotes in sermons, “Alfie” names, similar sounds, television/PA playback, incomplete/negated/multiple commands, wrong camera, cough and clipped mic. Freeze consented train/test sessions and keep study recordings private under separate consent. Target 0 unintended actions / 30 negative hours and 0 duplicate/stale/wrong-channel actions; report count/hour by stratum and recognized false wakes as well as false actions. Zero observed in 30 h is not proof of zero risk; idealized independent Poisson upper 95% rate is roughly 0.1/h.

Positive study: proposed 6 volunteer voices × 8 phrases × 10 repetitions = 480 utterances across quiet/PA/HVAC conditions; proposed ≥95% correct-action rate, 0 wrong actions, rejects counted separately. Include Take and manual intervention midway through every phrase, permissions revoked, mute, model unavailable, sleep/wake and sustained two-camera thermal load. Expand corpus if any relevant condition lacks evidence. Text-only grammar tests cannot certify acoustic false-action rate.

## Permissions, retention and forbidden actions

Use microphone permission with `NSMicrophoneUsageDescription` ([Apple key reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html)) and inspect signed `com.apple.security.device.audio-input` ([sandbox entitlement reference](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)). Build setting alone is not export proof. Ask during setup; persistent mic indicator/mute, no capture while disabled; CMIO extension remains video-only.

SFSpeech authorization behavior must follow its API ([requestAuthorization](https://developer.apple.com/documentation/speech/sfspeechrecognizer/requestauthorization(_:))). Apple describes `NSSpeechRecognitionUsageDescription` as required for APIs sending data to recognition servers ([usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsspeechrecognitionusagedescription)); do not copy cloud-purpose wording into an on-device privacy claim. Exact permission prompts required by the chosen on-device path on 26.2 are **UNVERIFIED** until signed-app denial/revocation tests; do not infer that every SpeechAnalyzer use needs SFSpeech authorization.

Default audio/transcripts exist only in bounded memory and are discarded after recognition, reject, mute, Stop or timeout. No audio retained without an approved privacy decision; study recording has separate consent. Inspect filesystem, logs, crash attachments and offline network behavior. Measure system speech-service memory/CPU too; work outside app RSS still consumes machine resources.

Voice may never bypass authority/readiness, automatically Take in this slice, enable Auto Direct, arm/move hardware, clear e-stop, change output/source, identify a person by guessed name, start/stop show, unmute itself, execute partial hypotheses, or fall back to cloud. Spoken Stop remains excluded by the September eight-command contract; physical Stop/Wide always available. “Alfie has the pastor” is not an executable until explicit nomination and reviewed structured semantics exist.
