# Run-sheet authoring and strip (C-07)

The optional A-13 run sheet carries Presenter, Panel, Performance and Video break segments, each with an optional operator-entered name and typed position hint. This component chooses style context only. It cannot start capture, nominate a subject, change a Director level or grant authority.

## Authoring

In a Debug build, open Window → Multiview Gallery → Run sheet · C-07. Show A and Show B are synthetic examples with independent temporary storage. Load synthetic run sheet supplies explicit example segments; it replaces that show's unsaved sheet and does not save automatically.

Use Add segment to append a row. Edit loads one row into the separate edit form; Apply segment commits it, and Cancel edit leaves the row unchanged. Other Edit controls and Save are disabled until that edit is resolved. Move up/down retains the current segment by stable ID. Removing the current row selects its next remaining neighbour, or the preceding final row; an empty sheet has no selection and uses Live event context.

The strip names Current and Next. Advance or Command Shift Return selects only the next segment, with no automatic advancement or wrap at the end. The shortcut is suspended while an optional-name text field is focused, so typing cannot advance the sheet. A host with comparison strips must give only one strip shortcut ownership.

Save run sheet writes the selected show only; Reload run sheet reads its saved value and discards unsaved authoring changes. The gallery retains each show's editor while switching examples. Its temporary files are test artifacts, not an application's production show registry.

## Storage and integration

`RunSheetStore(directory:)` receives an explicit local directory. The host supplies an opaque show UUID; the filename derives only from that UUID, never from a name or user-entered path. The JSON contains version, segments and current segment ID. Names are saved only as operator-entered display metadata. No level, qualification, grant, camera route or automatic policy setting is restored.

Load validates the model's version, IDs, authored types and current selection, and rejects unknown storage keys. Missing files are empty. Unreadable/future files, directories and symlink targets produce a visible error and are preserved; save refuses to replace them. After separate repair/removal, Reload can read the corrected state. A failed save retains the in-memory sheet. Valid saves use an atomic write.

These are reusable editor/store/strip components, also exposed in the Debug gallery.

## In a real show (SU-09, SU-10)

Where the Director runs (Debug builds, `DeveloperFlags.runDirectorShadow`), **Run sheet…** opens the show's sheet from Show setup (Multi Cam), from the standby screen (Single Cam, Webcam) and from **Edit…** beside Advance in the live console header. It is optional: with no segments Alfie uses the Live event feel. Each segment shows its feel from Settings › Director.

- **Show identity.** `ShowRunSheet` keeps one opaque show UUID in defaults (`directorRunSheet.currentShowID`), so the sheet survives relaunch. Sheets live in `~/Library/Application Support/Alfie/RunSheets`. **New show…** starts an empty sheet and keeps the old one as the last show's; **Use last show's** copies its segments as unsaved edits.
- **Launch.** `startDirectorShadow` gives the Director the saved sheet (never unsaved edits). Launch stays Manual, so this never pauses.
- **Save.** Saving hands the sheet to `DirectorController.runSheetEdited`. The Director keeps its current segment while that segment still exists. Changed segments are an F2 change: while Alfie is directing it pauses ("Paused: run sheet changed") until Hand to Alfie; in Manual it applies at once. Saving unchanged segments doesn't pause.
- **Advance** (button or Command Shift Return in the console header) changes the style only: no pause, no cut, no level change, never timed. The editor's own Current marker isn't moved by Advance; the Director's position wins when an edit is saved.
- Live advance in the Single Cam console is a follow-up. The underlying A-13 model is reused from PR #57, and C-06's initial component from PR #23. F3/live rehearsal review remains separate. Synthetic tests and gallery interaction are not live qualification.
