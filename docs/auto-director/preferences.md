# Director preferences and the optional run sheet

Status: reconciled 2026-10-10 for D-01. [Recorded decisions](../handoff/stage3-4/DECISIONS.md) take precedence over older proposed text. Implementation references describe the open A-07 stack at `ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42`, not merged or qualified behavior. Unrecorded choices and recommendations remain **AWAITING OWNER**. See the [product contract](product-contract.md) and [event contract](event-authority-contract.md).

## Actual A-07 schema

`DirectorPreferences.currentVersion` is **2**. The persisted value contains `version` and `styles: [SegmentType: DirectorStyle]`. Supported segment keys are `presenter`, `panel`, `performance`, `videoBreak`, `liveEvent`. `liveEvent` is required and supplies the fallback for a segment without an explicit style. See [shot-style](shot-style.md) for the exact fields, units and validation constraints.

`validated()` rejects unsupported versions, missing Live-event style, invalid durations/movement and conflicting constraints. `migrate` accepts only schema 2; schema 1 was never persisted in this implementation and has no supported migration. Unknown/future versions fail closed. These facts describe the open stack, not deployment history or completed console persistence.

There is no saved authority level, grant, cut permit, countdown, live composition, nomination gallery or qualification approval in this schema. Launch starts Manual with no handback, even when qualification records allow other levels. A preferences file cannot select an unqualified level or authorize a cut.

`DirectorStyle.resolve` resolves explicit style conflicts conservatively. `DirectorPreferences.resolve` currently merges explicit dictionary keys; a review finding notes that a one-sided segment can ignore the other input's effective Live-event fallback. Do not claim the current merge is conservative across all effective profiles until that is resolved and tested. No defaults are supplied for study numbers.

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
