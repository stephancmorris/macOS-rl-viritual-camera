# Director follow-ups — 19 October 2026

Three bounded follow-ups from main `39e05d2`, independent of the operator-modes branch:

- [A-07](https://trello.com/c/DHZ8Yyc4): stale, missing or invalid evidence immediately inhibits preparation/cut readiness and clears pending confirmation and settlement. Fresh lock flicker stays debounced. Older valid samples remain historical and ignored; invalid clocks inhibit without moving the accepted timestamp. Recovery must confirm and settle again. No timing defaults are introduced.
- [C-04](https://trello.com/c/tE0tzjNz): saves identify the invalid field and constraint, select the affected segment and preserve every draft and the existing file. Empty required Live event remains a separate message. Lossless numeric formatting also prevents tiny positive rates becoming zero and large finite values trapping on reload. The DEBUG gallery hosts the real editor against a unique temporary file without a live-preferences callback.
- [C-02](https://trello.com/c/4FVemMN9): the DEBUG gallery provides unqualified and qualified-Assist synthetic scenarios. Switching resets to Manual. Exactly one interactive control owns Command Shift H; the state cards opt out. This never creates saved qualification or live authority.

## Verification

Full unsigned Debug unit target: **689 passed definitions / 975 expanded executions, 0 failures, 3 inherited opt-in skips**. Includes adapter boundary/recovery and existing controller tests; editor save/reload, corrupt/future-file and byte-preservation tests; and synthetic scenario/shortcut-definition tests. Unsigned Release app and extension build passed. Diff whitespace check passed.

Xcode 26.2, arm64 macOS 27.0.1. Local results: `/private/tmp/alfie-takeover-20261019/followups-unit.xcresult`, `followups-unit.log`, `followups-release.log`. Build-input fingerprint from `CinematicCoreMacOS/scripts/source_fingerprint.py`: `9948dab40a7eaee311ca050c8f157bda969b44eee309c2673fdbf4b06574a104`.

## Actual GUI observations

Using the tested unsigned Debug app, Window → Multiview Gallery:

1. Unqualified/Manual: Command Shift H displayed “Choose Assist, Auto or Backup” and stayed Manual. Assist/Auto/Backup were disabled and labelled not qualified.
2. Switching to Qualified Assist cleared the refusal and stayed Manual. Selecting Assist showed “Watching · Alfie is not changing shots”. Command Shift H changed it to “Paused: you took over”; a second press restored Watching/Hand to Alfie. State cards were unchanged. Switching back to Unqualified reset to Manual; the shortcut again refused.
3. Empty scratch style save showed the required Live event message in amber. After loading explicit synthetic values, NaN in Maximum movement produced “Live event: Maximum movement must be a finite number.” Conflicting minimum/preferred lengths named that ordering constraint and retained the draft.
4. Correcting the values saved successfully. Changing a field without saving then reloading restored the saved value. A subsequent invalid save against the existing valid scratch file was refused, and reload restored Maximum movement = 0.2. Deterministic tests additionally assert byte-for-byte preservation and no policy callback for invalid saves.

Screenshots and final accessibility text are alongside this report. These are synthetic gallery checks; no camera session, actual automatic effect, live rig qualification or spoken VoiceOver acceptance is claimed. All review app instances were quit. The application's real style file was not edited by these checks.
