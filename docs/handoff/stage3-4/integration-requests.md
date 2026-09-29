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

`ShowCoordinator.swift` should expose a command factory that binds an explicitly named channel with `.voice` origin while enforcing the utterance-time target revision and Program Edit Live rule:

```swift
func makeVoiceCommand(_ action: OperatorCommand.Action,
                      target: ChannelID,
                      expectedControlRevision: UInt64) -> ShowCommand?
```

Call `VoiceCommandAdapter.manualCommandOccurred()` before every subsequent manual action, especially Return to Wide. A later approved speech stack supplies only final transcripts with IDs and a stated confidence scale through `SpeechTranscriptSource`. No microphone, audio retention, recognizer, entitlement, or UI mute control should be added until the speech/privacy decision.

## Hardware integration

After H1/H3/H4 and a named device are approved, implement `HardwareTransport` in a new adapter and add the exact entitlement for that selected transport. Firmware/device control must enforce watchdog, lease expiry, e-stop and physical limits locally. A host `HardwareLink` heartbeat is observational; it is not a safety deadline. Keep motion disabled until the independent stop and bench qualification gates pass. Do not map digital crop coordinates to actuator stroke.
