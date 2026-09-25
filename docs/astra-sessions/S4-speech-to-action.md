# [S4] Offline speech-to-action — eight wake-prefix commands

**Astra role:** coding agent.  
**Trello:** https://trello.com/c/h5D0Mj0x  
**Depends on:** S1 `CommandDispatcher`. Must **not** delay S2/S3.  
**Unblocks:** Hands-busy booth control. Does not unblock hardware.

## Prompt (paste this file as the whole prompt)

You are implementing Alfie Session 4: offline speech to the existing command dispatcher.

This is IMPLEMENTATION of a **command interface**, not a cinematographer brain. No LLM. No speech-driven crop policy. No spoken Stop session in the first eight. No hardware arm commands.

If `CommandDispatcher` / `OperatorCommand` are missing, stop. If Channels exist, commands that omit a camera name apply to the **selected** control channel; once two channels are running, require `camera one/two` (or `A`/`B`) in the utterance.

## Why this session exists

A volunteer watching the program pane should be able to say a short booth phrase and have Alfie do the same thing the pill already does.

## Vocabulary (finite grammar, complete utterance)

Wake prefix is required: **Alfie**.

| Spoken form | Same action as |
| --- | --- |
| “Alfie, detect” | Arm Detect. Operator still taps the person. |
| “Alfie, track” | Crop/Track only if a valid lock exists. Else show `Pick a subject.` |
| “Alfie, manual” | Adopt current shot into Manual. |
| “Alfie, pan” | Enter Auto Pan from the current shot. |
| “Alfie, back to wide” | Return to Wide (safety). |
| “Alfie, waist up” | Select/reset Waist Up. |
| “Alfie, push in” | One rung push-in (same as the pill). |
| “Alfie, pull out” | One rung pull-out (same as the pill). |

After multi-input: `Alfie, camera two, pan.`

Reserve for later (do not implement unless already trivial): full body, wide *framing* (not Return to Wide), unlock, cancel detect, start session.

**Do not map bare “wide”** to both the Wide preset and Return to Wide. Safety recovery is only `back to wide`.

**Do not implement** “Alfie has the pastor” as an executable. There is no role recognition.

## Trust

- Dedicated close-talk / headset mic (DECIDE Q5 default).
- Wake prefix is a **gate**, not speaker ID.
- Voice activity + strict phrase match + dedupe + **final/stable** results only.
- Partial hypotheses may show `Hearing…` and must not move a shot.
- Reject ambiguous utterances. Do not guess the nearest command.
- Feedback above the pill: `B · Push in` or `B · No locked subject`. No spoken reply over booth PA.
- Mic mute is one small pill toggle with a persistent listening/muted state.
- Hold-to-talk is a later alternative, not this slice’s required path.
- Manual interaction cancels pending voice motion and invalidates in-flight transcripts captured *before* that interaction.
- A late voice command cannot undo Return to Wide.
- Spoken Stop is out of the first eight. If added later: inline `Stop all feeds? Say ‘Alfie, confirm stop’` for 5 seconds, no modal. Hardware e-stop never uses that rule.

## Recognition stack

| Option | Use |
| --- | --- |
| Bundled **whisper.cpp** `base.en` | Default for a macOS 14+ *product* story. Offline, versioned assets. |
| `SFSpeechRecognizer` + `requiresOnDeviceRecognition` | Comparison implementation only. Check `supportsOnDeviceRecognition`. **Never** silent-fall-back to cloud. |
| SpeechAnalyzer / SpeechTranscriber | Only if we formally require the current **26.2** deployment target. Do not take a 26-only API while the product still claims 14+. |

Start with whisper.cpp `base.en`. Warm assets before service. Do not assume first-run Core ML compile is instant. Measure booth accuracy (HVAC, music, PA bleed) before calling it Sunday-ready. Increasing model size is allowed only for a measured command-error drop.

Audio stays in a bounded in-memory buffer and is discarded after recognition. Recording examples is an explicit diagnostic flag, off by default.

## Architecture

```
Mic → VAD → recognizer (off frame path) → utterance id
        → wake + grammar parse → OperatorCommand (origin: .voice)
        → CommandDispatcher
```

New speech types depend on `OperatorCommand`, **not** on `CameraManager` internals. Pill/ContentView add mic state and feedback only.

Add `OperatorCommand.Origin.voice`. Dispatcher already prefers operator over stale recovery; treat voice like operator UI but **below** a later physical input if both happen in the same epoch. Manual pill input invalidates in-flight voice.

## Permissions

- `com.apple.security.device.audio-input` in the **signed** entitlements (today it is a build setting, not the checked-in plist — inspect the exported app).
- `NSMicrophoneUsageDescription` — booth language, not engineer language.
- Request mic permission during setup, not mid-sermon.
- Bundled local recognizer does not need Apple Speech authorization. SFSpeech option does.
- Extension stays video-only.

## Acceptance

- Airplane / offline after setup: commands still work.
- Zero actions on a sermon / music / silence corpus you check in or document how to run.
- One action per utterance.
- Selected channel cannot change while a phrase is being resolved (target captured at start).
- UI recovery / Return to Wide invalidates old voice work.
- Model failure leaves video running.
- Aim ~1 s acknowledgment after the phrase ends; measure on the show rig later.
- No cloud traffic in a packet capture during a local session (if you add SFSpeech, assert on-device or disable).

## Out of scope

- LLM, freeform conversation, subject-by-name
- Spoken Stop, spoken Start-while-stopped (would need “listen while stopped”)
- Wake-word neural model (only if measured false activations demand it)
- Speech moving the hardware arm

## Files

- New: `SpeechCommandService.swift`, grammar, whisper (or SFSpeech) wrapper
- `OperatorCommand.swift` — `.voice` origin
- `OperatorPill.swift` — mute + hearing/accepted/rejected
- Entitlements + Info.plist usage string
- Tests: grammar unit tests (accept / reject), stale-utterance rejection, mute
