# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| F1 Preference input? | Structured controls; free text; both executable | Structured first; free text may draft a reviewed structured change later | AD-PREFS, voice direction | Yes |
| F2 Mid-show edits? | Locked; immediate; apply with pause | Apply with global pause and explicit resume; no cue/edit may cut | AD-PREFS/OVERRIDE | Yes |
| F3 Rundown execution? | Timed automatic cues; operator-advanced cues; none | Operator-advanced cues constrain policy, never grant authority | AD-PREFS/SCOPE | Yes |

Status: proposed schema and defaults, 2026-09-30. `origin/s34/sol:Director/DirectorPreferences.swift` already supplies versioned Codable validation and migration hook; its provisional style defaults differ from this recommendation. `DirectorShotPolicy.swift` selects candidates but is unwired. Existing `ShowCoordinator.makeCommand`/`ChannelRevisions` remain integration boundaries.

## Proposed structured document

| Field | Default / validation |
|---|---|
| schemaVersion / policyVersion | Proposed schema 1 plus immutable policy hash; unknown future schema rejected, migrations explicit and tested |
| serviceUseCase | sermon; worship/panel/wholeService unavailable for authority in initial qualified scope |
| desiredMode | Off on launch/show start; stored preference never restores permission |
| roleAssignments | Explicit device/channel→safeWide or speaker; no inferred assignment; rebind invalidates verification |
| subjectNominations | Runtime per-channel lock references and operator aliases; do not persist face galleries or automatically reacquire at launch |
| style | Full parameter set in [shot-style](shot-style.md), units retained; no independent defaults copied into UI |
| cues | Ordered cue ID, label, allowed roles/presets, nomination requirement, optional planned duration; all advance explicitly |
| privacy | Audio disabled; ephemeral-only if later approved; recording consent is a separate field, never implied |
| qualification | Read-only reference to approved scope/rig/policy evidence; cannot be enabled by importing preferences |

Validate finite positive durations/ages, min ≤ preferred ≤ soft max, permitted enum values, available channels, and role consistency. A safe-wide camera cannot simultaneously require a tight tracking composition. Reject invalid imports with field-level errors; retain previous valid document. A future version is not silently downgraded. Persist versioned settings, not live authority tokens, pin state or countdown.

Conflict order: locked safety/qualification → operator pause/pin/manual → role/identity restrictions → active cue → user style → default. Intersect allowed capabilities; combine quantitative limits only when their meanings/units match (e.g. slower speed ceiling, longer minimum). Empty intersection is invalid, not an excuse to invent a new maximum. Wide cadence and maximum duration are soft reminders; taking their minimum does not create a safety guarantee. Unknown or contradictory natural language produces no executable configuration.

## Cues and example

| Cue | Allowed behavior | Transition |
|---|---|---|
| Welcome | Director Off; manual R2 | Operator advances |
| Sermon | Nominated speaker, safe-wide alternative, selected qualified mode | Advance pauses; verify nominations/roles then Resume |
| Prayer / worship | Off in initial scope | No timer or transcript automatically advances |

A cue duration is planning metadata, not a scheduled Take. Changing a cue, role, nomination, style or privacy permission increments proposed policy/cue revision, invalidates proposals and pauses. Applying a stricter safety restriction takes effect immediately; resumption still needs explicit action.

Acceptance: encode/decode equality; unknown-version and nonfinite-value rejection; migration preserves meaning; contradictory roles and conflicting bounds fail; settings change during countdown cancels before Take; restarts never restore authority. Risks: too many settings burden volunteers; expose a single “Sermon · Calm” proposal and scope controls, with numeric tuning in rehearsal settings and immutable approved policy IDs for service use.
