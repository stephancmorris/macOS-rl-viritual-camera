# C-06 / C-07 software delivery — 20 October 2026

This branch builds on PR #67 (`0466d0f`). It reuses A-13's model/tests from PR #57 (`addfb828eb26b48eb59aa05a43978684513c28de`) and C-06's initial component from PR #23 (`e048f913369ea90f05ddecf7743bd922e72a5999`). Those candidates remain separate review context; no parent PR was merged into main by this batch.

## Delivered

[C-06](https://trello.com/c/auY6HYtj): the notice works with any observable DirectorConsoleControlling. Cancellable notices expose an actual labelled Cancel button. One interactive notice owns plain Escape; removed/noncancellable notices do not consume it. Callbacks check the current notice, reject repeat/modified keys, and clear when dismantled. Backup stays plain status. Huge finite countdowns no longer trap or overflow display rounding; unusable durations are omitted without hiding cancellation. No notice duration is chosen here.

[C-07](https://trello.com/c/JAU8oFd7): reusable editor, per-show UUID storage and current/next strip. Add/edit/apply, reorder/remove, optional names and typed positions are supported. Selection follows stable segment IDs through reordering; removing current chooses its following neighbour or preceding final row. Unknown/corrupt/future files and nonregular/symlink targets are preserved, with saving refused. Atomic valid saves contain only versioned segment metadata/current ID. Advance never wraps and Command Shift Return is suspended during name editing. Unapplied edits must be applied/cancelled before another Edit or Save.

The Debug gallery supplies two synthetic shows in unique temporary stores. It has no live Director callback, camera action, qualification file or production show registry. See [the component guide](../../../docs/auto-director/run-sheet-ui.md).

## Verification

Full unsigned Debug unit target: **725 passed definitions / 1,032 expanded executions, 0 failures, 3 existing opt-in skips**. Unsigned Release app/extension build passed. Diff whitespace check passed. Xcode 26.2, arm64 macOS 27.0.1.

Final results: `/private/tmp/alfie-ui-batch-20261020/unit-verified.xcresult` and `unit-verified.log`; Release: `release-build.log`. Earlier integration attempts exposed missing Combine imports, Swift Testing macro limitations around mutating value methods, and an old gallery assertion for the intentionally retained Escape hint; all were repaired before the final passing run.

Build-input fingerprint from `CinematicCoreMacOS/scripts/source_fingerprint.py`: `02da80e830c0d576caf77a1e13d0eeec8c0e920cfd6413be76ab7847126014a5`.

## Actual GUI checks

- C-06: unrelated `a` left the notice unchanged; Escape removed only the interactive notice and incremented cancellation once. Repeated Escape did nothing. Accessibility-selected Cancel also cancelled once. Replacing with Backup showed no Cancel action and Escape left it unchanged. Comparison cards stayed intact.
- C-07: empty fallback and disabled Advance were visible. Command Shift Return advanced Presenter → Panel. While editing Panel's name, the shortcut did not advance, other Edit controls and Save were disabled, and Apply retained the current identity.
- Moving the edited Panel upward retained it as Current and changed Next to Presenter. Save succeeded. Show B began empty; a separate Performance segment with a name and Right position was added, saved and reloaded there. Returning to Show A retained its four rows, edited name, order and selection. Reload after unsaved advancement restored Show A's saved Panel state, demonstrating independent saved files.
- Keyboard advancement stopped at the last segment without wrapping. Removing the current first row selected the following Presenter row. Store tests also cover removal positions, malformed/future files, late corruption, symlink targets and persistence.

Screenshots and accessibility text are alongside this report. Native accessibility activation/labels were checked; spoken VoiceOver was not run. No Start, camera capture, actual cut, permit or qualification was requested. All review app instances were confirmed quit.

## Remaining integration

C-06's real deadline/permit cancellation and attended Debug rehearsal still require B-08. Production show identity, live console/controller wiring and style-scoped policy-change events remain B-11 work. F3/live integration review is separate. This delivers the components and synthetic software evidence, not whole-card live acceptance or release qualification.
