# Director preferences and the optional run sheet

Status: reconciled 2026-10-10 for D-01. [Recorded decisions](../handoff/stage3-4/DECISIONS.md) take precedence over older proposed text. Implementation references describe the open A-07 stack at `ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42`, not merged or qualified behavior. Unrecorded choices and recommendations remain **AWAITING OWNER**. See the [product contract](product-contract.md) and [event contract](event-authority-contract.md).

## Actual A-07 schema

`DirectorPreferences.currentVersion` is **2**. The persisted value contains `version` and `styles: [SegmentType: DirectorStyle]`. Supported segment keys are `presenter`, `panel`, `performance`, `videoBreak`, `liveEvent`. `liveEvent` is required and supplies the fallback for a segment without an explicit style. See [shot-style](shot-style.md) for the exact fields, units and validation constraints.

`validated()` rejects unsupported versions, missing Live-event style, invalid durations/movement and conflicting constraints. `migrate` accepts only schema 2; schema 1 was never persisted in this implementation and has no supported migration. Unknown/future versions fail closed. These facts describe the open stack, not deployment history or completed console persistence.

There is no saved authority level, grant, cut permit, countdown, live composition, nomination gallery or qualification approval in this schema. Launch starts Manual with no handback, even when qualification records allow other levels. A preferences file cannot select an unqualified level or authorize a cut.

`DirectorStyle.resolve` resolves explicit style conflicts conservatively. The 18 October review repair makes `DirectorPreferences.resolve` merge each segment's effective styles, including the other input's Live-event fallback for a one-sided segment. Incompatible effective constraints refuse the merge. The pinned A-07 snapshot did not handle that fallback; regression coverage now checks both input orders and conflicts. Feel table v1 now supplies the Live event default when nothing is saved (SU-1); see [shot-style](shot-style.md).

## Product requirements and open choices — AWAITING OWNER

A run sheet is optional guidance for a live-event backup producer. E1 allows a position hint, but the shown subject remains overridable and an operator nomination wins. A person's name is operator-supplied display metadata, never inferred identity. N1, A1 and A3 remain binding regardless of segment or style.

| Decision | Options | Recommendation and tradeoff | Evidence required |
|---|---|---|---|
| F1 authoring | Structured controls; executable free text; reviewed drafts | Versioned structured controls, with any future text producing a reviewed draft; less flexible but auditable | Round-trip validation and operator understanding |
| F2 live edits | Lock during show; immediate apply; pause then apply | Invalidate proposals and pause before applying a new policy revision, explicit handback; safer provenance at the cost of interruption | Races with dispatch, pending cuts and takeover |
| F3 run sheet | Timed automatic advancement; operator advancement; none | Optional operator-advanced segments, style hints only; adds a small operator task without treating the schedule as authority | Segment transitions and unscripted events, with and without a run sheet |

These remain open choices. At A-07 `RunSheetLine` is only console display text and the console protocol exposes `advanceSegment`; that does not supply the later run-sheet model or an automatic scheduler. `SegmentType.performance` is not permission to analyze music or collect audio.

## Storage and evidence boundaries

C3/AI-4 authorize bounded Director metadata with 30-day expiry and explicit export, including metadata-only training datasets. Do not serialize frames, crops, face signatures/embeddings, audio, transcripts, inferred names or children as targets. E3 and AI-3 remain open for any separate media collection/offline transfer. AI-2 forbids network during a show; no background upload or cloud parser is implied by preference authoring.

Keep schema version, policy/parameter revision and evidence provenance separate. A sample number in a synthetic fixture is not a production default. Reports must identify synthetic, recorded and live sources and the frozen parameter set; only explicit per-level sign-off qualifies operation on the rig.

## Settings › Director (AD-STYLE-UX, 2026-10-25)

- **Feels, not numbers.** Each segment type is set with Pace, Wide shots and When someone moves; exact values stay editable, and an edit that breaks a rule (for example minimum longer than preferred) is refused inline and not saved.
- **Saves automatically (SU-3).** Every change is validated, written through `DirectorPreferencesStore` and pushed to the running Director. An unreadable file is moved aside on the next save, never overwritten.
- **Launch (SU-01, SU-04).** `ShowCoordinator.startDirectorShadow` loads saved styles; with none saved the built-in Live event feel applies; an unreadable file gives no styles. Launch stays Manual.
- **Mid-show changes (F2).** A style saved while Alfie is directing invalidates pending work and pauses ("Paused: style changed"); the new style applies when the operator chooses Hand to Alfie. In Manual it applies at once. Saving an edited run sheet mid-show pauses the same way ("Paused: run sheet changed", SU-10, through `runSheetEdited`); `setRunSheet` itself stays the setup path and leaves authority unchanged.
- **Run sheet (F3).** Optional and operator-advanced, never timed. Advancing a segment changes the style without pausing; only editing the segments counts as an F2 change.
- **Visibility (SU-5).** The page appears only where the Director runs (`DeveloperFlags.runDirectorShadow`, Debug today).

