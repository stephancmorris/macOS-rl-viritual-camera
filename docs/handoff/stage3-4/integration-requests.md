# Integration requests after Stage 2 and decisions

Director lifecycle repair review candidate, 30 September 2026. These are **future integration requirements**; no running-app hooks are implemented. All 37 decisions remain OPEN. `decision-review.md` and `event-authority-contract.md` are proposed semantics. The isolated constructor requires `DirectorAuthority(reviewPolicy: .conservative)`; selecting that profile in tests does not install or approve a production policy. The voice and hardware requests below remain separate, unapproved work.

## Event sources and ownership

A future coordinator must own one authority and one `DirectorPreparation` lifecycle, serialize their mutations with the camera effect on MainActor, and retain authority generation history across show Stop/restart. Never reconstruct an active grant from `DirectorPreferences`. Exhaustion is terminal for that authority owner: do not reset its counter to recover. Retired session callbacks must be destroyed before replacing an owner.

| Future source / owner | Exact foundation event | Ordering and recovery contract |
| --- | --- | --- |
| All camera/editorial command ingress / ShowCoordinator, including Wide, subject/shot/mode changes and cue/role edits | `.manualCommand` (or dedicated `.nominationChanged` / `.policyChanged`) | Apply before any admission check, including commands ultimately refused. Consume transition cancellations to retire queued/delayed Director work globally. Existing admitted R2 tracking continues. |
| Every operator Take ingress / ShowCoordinator | `.operatorTake` | Apply before `makeTakeRequest`/`take` eligibility and output checks. A refused Take still pauses. After a committed Take, snapshot new roles and route. Never retarget old Preview work to new Program. |
| Edit Live ingress / ShowCoordinator | `.editLive(true/false)` | Enter revokes and pauses before `setEditLive`. Exit removes inhibition only; it does not Resume. |
| Inspector/navigation and label cosmetics / UI classification | `.navigation`, `.cosmeticEdit` | No revocation. Classify by semantic effect, not pointer focus. No new UI is in this repair. |
| Bounded nominated-person observations / evidence adapter | `.evidenceAvailable(false/true)` | An explicit temporary unavailable/stale/ambiguous gap removes readiness and preparation eligibility without changing epoch. The snapshot's `evidenceAvailable` must also be false. Current adequate evidence may recover under the same grant; no new identity is inferred. |
| Declared loss of nominated identity / evidence adapter | `.identityLost(channel)` | Revoke and latch Pause immediately. The adapter must explicitly declare loss based on a separately supplied study/product policy; this foundation invents no timeout, confidence-loss threshold or cross-camera identity association. |
| Source lifecycle / CameraManager or capture admission owner | `.sourceLoss(channel)`, `.sourceRebound(channel)` | Emit on loss, restart or device rebind, including successful restart. Snapshot the changed `sourceGeneration` before future work is admitted. Recovery does not Resume. |
| Downstream output lifecycle / output/router owner | `.outputFault` | Revoke and pause before reporting recovered health or dispatching new Director effects. HOLD/standby, raw-output prohibitions and committed Take behavior remain R2-owned. |
| Pair/workload admission owner | `.admissionLost` | Revoke on loss/invalidation of the exact admitted workload/fingerprint. No simulator result may certify this gate. |
| Aggregate lifecycle adapter | `.healthRestored` | Supply only after **all** relevant sources, output and admission prerequisites are current. This removes health inhibition, never the Pause latch. |
| Behavior-affecting settings, role/cue or nomination owner | `.policyChanged`, `.nominationChanged` | Revoke/pause before mutation, increment corresponding revision, then publish one coherent snapshot. Cosmetic labels do not increment behavior revisions. |
| Show lifecycle / ShowCoordinator | `.stopShow`, `.restart` | Stop retires all work and leaves Off before teardown. Restart remains Off. Neither saved level preferences nor Resume can activate Off. |
| Explicit available-level enable or Resume / operator through coordinator | `.enable(level)`, `.resume` with `Prerequisites` | Read nominations, current Preview availability, source health, output health and admission in the same turn. All five booleans must be true. A superseding grant gets a new epoch. Enable cannot clear Pause; use explicit Resume. Auto Direct returns `.autoDirectUnqualified`, preserving current level/epoch; never substitute Auto Prepare. |
| Deferred Pin, if separately chosen | `.pin(channel)`, `.unpin` | Pin retires work and pauses; unpin does not Resume. No Pin UI is added. |

Events and grant prerequisites are trusted adapter inputs, not facts this isolated module can independently discover. Missing or stale snapshots must fail closed. Keep a temporary evidence gap separate from a declared identity loss and from source/output/admission faults.

## Snapshots, requests and final effects

`DirectorLiveState` must atomically contain authority, stable Program/Preview channel identities, Preview `ChannelRevisions` (source generation, control epoch, discrete shot revision), route generation, source-missing state, policy revision, nomination revision and current sufficient-evidence status. `ShowDirectorWorld` remains an unwired, read-only R2 snapshot bridge: it cannot supply nomination/policy revisions or identity freshness, and its evidence status defaults false. It is **insufficient to authorize preparation**. An eventual evidence adapter must supply bounded immutable observations, their monotonic age, retained nominated identity, confidence, framing settlement and motion, using explicitly selected study parameters. Ordinary renders and tracking interpolation do not increment `shotRevision` or refresh identity evidence.

`DirectorProposal.id` identifies shot intent. `DirectorPreparation.Request.id` identifies a particular inert dispatch request, bound to its intent/context, `issuedAt` and caller-supplied maximum age. `propose` explicitly replaces work; it is not an authorization grant. The scheduler must not call it repeatedly to refresh a lease or reapply an already valid composition. Expire requests via `discardExpiredRequest(now:)`, discard refused/failed matching requests via `discard(request)`, and never silently renew them. Replacement and transition cancellations call `retire()` for queued work/composition metadata; they do not jump a crop or revoke R2 tracking ownership.

At enqueue check `DirectorPreparation.validate(request, live: snapshot, now: clock)`, which uses `.prepare` context authority and the request lease rather than the intent age. `.propose` authority is insufficient. At the **final effect**, take a fresh snapshot and invoke `DirectorPreparation.commit(request, live: snapshot, now: clock, postRevisions: expectedAcceptedRevisions)` synchronously with the simulated sink effect. It checks current request identity, lease, action-specific authority, Preview ownership, source/control/shot revisions, route, policy/nomination revisions and adequate evidence again. Suggest only authorizes `.propose`; `.take` always refuses. A stale callback must not cancel a replacement request.

A future production integration needs an atomic sink boundary that checks these conditions, admits the actual R2 command, and records its accepted revisions in the same serialized turn with no intervening await. The current foundation `commit` records a **simulated acceptance**, not an asynchronous production command reservation: do not invoke it at enqueue or fabricate acceptance after a rejected sink. The future sink must report the exact accepted post-command source/control/shot revisions, with unchanged source generation and increased control/shot revisions. Verify this against the actual preset/mode sequence before using this API; it may require a single acknowledged preparation action rather than several public dispatch calls.

Only the matching stored receipt may pass `acknowledge(receipt, live:)`. The acknowledged `Composition` binds the accepted post-preparation revisions, so its own preset change does not invalidate it. Duplicate, replacement, old-epoch, role/route/source/policy/nomination and revision-mismatched acknowledgements refuse. ACK may arrive after the dispatch lease if the admitted result and context remain valid; it cannot authorize another effect. `refresh(live:evidence:parameters:)` recomputes readiness from current evidence without renewing the request or reapplying framing. Temporary evidence gaps retain composition metadata while withdrawing readiness; retired contexts cannot return after recovery.

## Current Stage 2 incompatibilities

- `ShowCoordinator.controlTargetRevision` changes on retarget, not every camera/editorial intervention. Its existing `makeCommand`/`dispatch`/`take`/`setEditLive`/Stop call sites provide no universal pre-admission Director revocation boundary. Every ingress path must be accounted for before integration.
- `CommandDispatcher` in `OperatorCommand.swift` has operator/safety/recovery origins, channel epoch admission and R2 tracking ownership. It has no Director origin, authority epoch, request ID, nomination/policy revisions or final Director check. Origin alone would remain an audit label, never a grant. Its accepted tracking must continue after retiring Director requests.
- CameraManager exposes no atomic, Director-bound preset acceptance/acknowledgement with expected post revisions and no Director-specific delayed-effect cancellation. Multiple separate commands or async callbacks are not equivalent to one atomic preparation.
- `TakeRequest` binds roles and route, not Director context. `ShowCoordinator.take` currently validates and commits synchronously. Any future qualified execution permit must be one-shot and checked in that same coordinator turn immediately before the existing Take checks. No permit issuance or automatic Take exists in this repair.
- `NextShotStatus.DirectorSection` still has `.off/.suggest/.auto`, no distinct Auto Prepare/Auto Direct or active/paused/inhibited state. `section()` is a legacy unwired projection; it is not a complete product status snapshot. UI changes require explicit U1/U2 choices. Director readiness must never disable an otherwise legal manual moving-shot R2 Take.
- `choosePreparation` selects useful Preview candidates before minimum Program dwell and permits movement; `recommendationDue` is future advisory timing only. Wide reminders and maximum dwell reasons do not authorize cuts. Historical `.proposed` and preference numbers remain unapproved, inconsistent study candidates needing reconciliation after decisions.

Integration/rehearsal still requires explicit product choices, the Stage 2 named-rig real-camera/downstream-output matrix and independent Director workload evidence. `origin/r2/sol:reports/release-2/multi-qa.md` still says **Not run**. Synthetic replay is no substitute. Do not enable motion, microphone or Auto Direct as part of these requests.

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

## C-01 · Missing operator sentences (A-04)

The gallery only shows `DirectorSection` reason text. These contract lines have no typed reason, so they are not in the gallery. Please add reasons if they should appear:

- Assist / Auto when Program's camera is lost and the operator must decide: "Program lost: Take Cam A?"
- Backup when both inputs are stale: "Both inputs stale"
