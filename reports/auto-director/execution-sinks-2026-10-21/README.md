# Director execution group — 21 October 2026

This candidate is stacked on PR69 (`4eee348`). It deliberately includes the existing A-12, A-15 and A-17 policy candidates (PRs56/59/60) for combined validation. Main and the primary modes checkout remain separate. No project, entitlement or Info.plist changes are included.

| Ticket | Implemented software scope | Remaining acceptance |
| --- | --- | --- |
| [B-08](https://trello.com/c/aDEyv84C) | Explicitly configured CutPolicy/notice/scheduler boundary; fresh deadline decision; same-turn permit and real Take; current-notice cancellation and hold; stale callback retirement | A4 timing/notice decision, truthful production timeline/confidence producer, named-rig live cancellation/qualification |
| [B-09](https://trello.com/c/q4H7i3Bt) | Separate Director slow-move admission; bounded eased one-rung geometry; live ownership and interruption checks; operator rates preserved | N2 decision, approved rate/qualification, measured downstream motion; existing authority prerequisites still prevent ordinary one-camera Auto |
| [B-12](https://trello.com/c/axfQoBKj) | Immediate source-loss pause/reservation; distinct fallback grant; actual router hold window; strict final deadline; verified rendered safe wide and terminal refusal | R1/R2 decisions, explicit verified binding/fallback qualification, live unplug/drill evidence |
| [B-13](https://trello.com/c/LTxj751i) | Backup deferred zero-countdown scheduling; uncancellable next-cut status; wide-only candidates for Panel/Performance/Video-Break; pause and handback after fallback | Automatic decision/context producer and visible live walkthrough; no new group-shot vocabulary is invented |
| [C-09](https://trello.com/c/DRRk4TJu) | Typed actual Backup alerts, current-controller live controls/cancel, synthetic gallery cases within the existing console layout | Spoken VoiceOver, visible live fault drill and Q-Backup sign-off |

B-10 discovery is excluded: D-03 has no approved rate/burst budget or calibration table, and rejecting a stale detection result does not cancel full-frame Vision work already in flight at Take. No discovery scheduler, capture permissions, audio or media collection is added.

Every execution adapter requires explicit settings/context/verification. Ordinary app construction installs none. Release automatic effects remain disabled. Synthetic readiness/qualification overrides exist only for tests; they are not a sign-off or production parameter source.

## Verification and review

Root owns serial Xcode validation. Agents implemented separate cut, fallback and move boundaries; cross-review checked fault ordering, final authorization, token-safe cancellation and current-controller UI actions. The first focused compile passed; its run exposed an invalid segment-replacement expectation and a slow-move admission failure. Both must be resolved before publication. Final results and evidence are appended below.


Final validation:

- Full Debug Swift suite: **864 definitions / 1,343 expanded passes, zero failures, three skips**. Result bundle: `/private/tmp/alfie-execution-20261021/full-unit.xcresult`.
- **31 Python tests passed**. Whitespace checks pass.
- **Unsigned Release app and camera extension build passed**. Release automatic effects remain disabled. Build log: `/private/tmp/alfie-execution-20261021/release-build.log`.
- The first focused failure on segment advancement was a test expectation error: advancement retires the old callback, while a fresh independent decision can legitimately create a replacement notice. The corrected test proves the captured old callback cannot consume or cut the replacement.
- The initial slow-move fixture clamped Wide and Full Body to the same 0.85 crop height. The fixture now has a real 0.8→0.6 rung, and zero-distance admission remains explicitly refused.
- A manual opposite-direction zoom now carries only command-local interrupted geometry across the immediate Director takeover, preserving normal reversal without creating a dormant operator gesture or bypassing command admission. A regression uses the actual controller-owned move adapter.
- The two-input positive test drives the actual evidence adapter and readiness calculations with DEBUG-only raw observation facts and real synthetic rendered packets; it does not replace final readiness/alternative decisions. The raw seam is nil in app construction and absent in Release.
- Synthetic coverage includes cancellation before exact-deadline finalization, old callback/replacement separation, fresh policy/qualification/revision checks, technical refusal/no retry, both source-loss event orders, stale/unverified/tight fallback refusal, output refusal, hold/standby deadlines, manual/operator Take/Edit Live/rebind interruption, motion-rate geometry, ownership and unchanged Preview, alert rendering/accessibility and console geometry.
- Independent cross-review found no further material authorization issue after repairs. Existing actor-isolation warnings outside the changed feature scope remain; no warning-free claim is made.
- No new manual live rig drill was performed. Native deadline/key races, actual downstream move duration, Backup visibility, spoken VoiceOver and per-level qualification remain pending. Offscreen gallery components render in the test suite.
- Final source fingerprint: `b7423d474094139195bcfb479a786972a212b7c84106d43325bca0ceee1b2495`.

The branch is a review candidate, with no main merge or production configuration installation. The five cards should receive human software review with the remaining acceptance gates retained.
