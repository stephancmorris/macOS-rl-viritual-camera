# Integration requests after Stage 2 and decisions

These are proposed edits to existing files for a later integration round. None was applied on `s34/sol`.

## `CinematicCoreMacOS/CinematicCoreMacOS/ShowCoordinator.swift`

Own one `DirectorAuthority` per show and revoke it in the same MainActor turn **before** manual dispatch, operator Take, Edit Live, and Stop. A proposed shape is:

```swift
private(set) var directorAuthority = DirectorAuthority()

func dispatchManual(_ show: ShowCommand) -> CommandResult {
    directorAuthority.apply(.manualCommand)
    return dispatch(show)
}

func operatorTake(_ request: TakeRequest? = nil) -> TakeResult {
    directorAuthority.apply(.operatorTake)
    return take(request)
}

func stopShowWithDirectorRevocation() {
    directorAuthority.apply(.stopShow)
    stopShow()
}
```

The actual call sites must route **every** UI/manual command and Take through these wrappers; wrappers alone do not provide safety if old call sites still use `dispatch` or `take`. On Edit Live, call `apply(.editLive(enabled))` before `setEditLive`; on source loss call `apply(.sourceLoss(id))`. Decide A1's pause behavior before exposing Resume. The current `ShowCoordinator.controlTargetRevision` changes on retarget, not every manual action; it cannot replace the director epoch.

For a future qualified Auto Direct, add one synchronous MainActor method that validates the director permit against fresh state then invokes the existing `take(request)` with no suspension between them. Reject a consumed permit and never queue a Take from an old frame. This is required because `TakeRequest` currently binds roles and route generation but no director authority or shot revision.

## `CinematicCoreMacOS/CinematicCoreMacOS/OperatorCommand.swift`

Add origins only when integration is authorized:

```swift
enum Origin: Equatable { case operatorUI, safety, automaticRecovery, director, voice }
```

The origin is an audit label, not an authorization grant. `CommandDispatcher.rejection` or the `ShowCoordinator` boundary must check a current director epoch and Preview role for `.director`, and a current manual-command cancellation generation for `.voice`. Voice currently uses the existing `operatorUI` origin because no voice origin exists. Keep Return to Wide and Stop priority above both.

## `CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift`

Expose an acknowledgement of an accepted director Preview preparation with the resulting `ChannelRevisions`, and a cancellation path for director-owned *future* effects after manual override. Proposed signature:

```swift
func applyDirectorPreview(_ action: OperatorCommand.Action,
                          expected: ChannelRevisions,
                          authorityEpoch: UInt64) -> Result<ChannelRevisions, CommandResult>
func cancelDirectorContinuations(before authorityEpoch: UInt64)
```

Validate the epoch and Preview ownership in `ShowCoordinator` immediately before this call. Record the accepted post-command epoch and shot revision; otherwise the proposal validator would mistake its own preparation for operator interference. Do not stop already admitted R2 tracking or jump the current crop on cancellation.

## `CinematicCoreMacOS/CinematicCoreMacOS/Console/NextShotStatus.swift` and `ConsoleSnapshot.swift`

The R2 seam currently has only `.off`, `.suggest`, `.auto` and `NextShotStatus.make` always sets `director: nil`. After AD-UI decisions, split `.auto` into `.autoPrepare` and `.autoDirect`, add requested level, pause/pin reason, proposal identity/shot, and authority epoch to a single snapshot, then publish it atomically with route state. Keep R2 `TakeAvailability` as the manual Take reason; director editorial readiness is separate.

## UI command sites (`OperatorPill.swift`, `ContentView.swift`, and console controls)

Call the manual-revoking coordinator boundary before camera actions, Return to Wide, and Take. Add explicit enable/pause/resume/pin controls only after A1/A2 and AD-UI decisions. Never let a stored preference automatically restore Auto Direct. Show the actual current authority and Preview proposal, not a speculative next cut.

## Voice dispatch and transcript integration

`ShowCoordinator.swift` needs one **synchronous MainActor** voice boundary. The current public `makeCommand`/`dispatch` pair cannot safely accept voice: `makeCommand` binds at final text rather than utterance start, and `dispatch` has no voice origin, manual generation, session/mute generation, or start-token check. `VoiceCommandAdapter` now returns a `BoundVoiceCommand` but intentionally does not dispatch it.

```swift
// Proposed ShowCoordinator.swift additions, after the privacy and authority
// decisions. Keep all reads, token validation, command creation and dispatch
// in one MainActor turn with no await or queued closure between them.
private(set) var voiceAdapter: VoiceCommandAdapter
private(set) var voiceSessionGeneration: UInt64
private(set) var voiceMuteGeneration: UInt64
private(set) var voiceMuted: Bool

func voiceSnapshot(now: TimeInterval) -> VoiceWorldSnapshot {
    VoiceWorldSnapshot(now: now, sessionGeneration: voiceSessionGeneration,
        muteGeneration: voiceMuteGeneration, running: showIsRunning,
        muted: voiceMuted, controlTargetRevision: controlTargetRevision,
        program: programChannel, preview: previewChannel, controlTarget: controlTarget,
        aRevisions: channel(.a)?.revisions, bRevisions: channel(.b)?.revisions,
        aSourceMissing: channel(.a)?.sourceMissing ?? true,
        bSourceMissing: channel(.b)?.sourceMissing ?? true,
        aSubjectLocked: channel(.a)?.hasLockedSubject ?? false,
        bSubjectLocked: channel(.b)?.hasLockedSubject ?? false)
}

func dispatchVoice(_ pending: VoiceCommandAdapter.Pending,
                   format: VoiceCommandAdapter.Format,
                   now: TimeInterval) -> CommandResult {
    switch voiceAdapter.prepareDispatch(pending, world: voiceSnapshot(now: now), format: format) {
    case .failure(let reason): return .rejected(reason.message)
    case .success(let bound):
        guard bound.target == previewChannel, bound.target == pending.token.start.preview,
              let camera = channel(bound.target) else { return .rejected("Preview changed") }
        let command = camera.makeCommand(bound.action, origin: .voice)
        return dispatch(ShowCommand(command: command,
                                    controlTargetRevision: pending.token.start.controlTargetRevision))
    }
}
```

`showIsRunning` and `hasLockedSubject` above are proposed read-only accessors; use the actual show lifecycle and lock state when integrating. Add `CameraManager.makeCommand(_:origin:)` or an equivalent coordinator factory so the origin is `.voice` and cannot be forged as `.operatorUI`. Route **every** manual camera command through `voiceAdapter.manualCommandOccurred()` first, every Return to Wide (including voice-origin Wide) through `returnToWideOccurred()`, Take through `operatorTakeOccurred()`, mute transitions through `muteChanged()`, and Stop through `stopOccurred()`. Bump show session generation on restart and mute generation on every mute transition. Bind utterance IDs and `voiceSnapshot` when recognition starts, then pass only final text through `accept`; never synthesize a start token at final text. The coordinator must own the adapter so no alternate `dispatch` path can bypass this gate. These hooks require a later approved speech stack and privacy decision. No microphone, audio retention, recognizer, entitlement, or UI mute control is in this branch.

The adapter retains at most `capacity` start tokens, pending commands, and recently finalized IDs each. Exact deduplication beyond this bounded window requires the transcript source to guarantee session-unique utterance IDs; that contract must be checked when a recognizer is selected.

## Hardware integration

After H1/H3/H4 and a named device are approved, implement `HardwareTransport` in a new adapter and add the exact entitlement for that selected transport. Firmware/device control must enforce watchdog, lease expiry, e-stop and physical limits locally. A host `HardwareLink` heartbeat is observational; it is not a safety deadline. Keep motion disabled until the independent stop and bench qualification gates pass. Do not map digital crop coordinates to actuator stroke.
