# Next Director group — 20 October 2026

This group builds on the reviewed no-camera follow-ups and C-06/C-07 components (PRs 67/68). The existing B-07, B-05 and B-04 candidates were deliberately integrated for combined validation; they remain separate unmerged upstream PRs 63–65. This branch does not enable automatic effects in Release and does not supply study parameters, storage budgets or rig qualification.

| Ticket | Software work in this group | Acceptance still requiring owner or rig |
| --- | --- | --- |
| [B-04](https://trello.com/c/3tyDYrWL) | Validated retained-session inventory; explicit inclusive UTC selection; atomically published local `records.jsonl`/`manifest.json` bundle; configured-provider selection UI and synthetic rehearsal | Default storage budgets remain absent. External destination UI and signed sandbox export require the owner-reserved user-selected file entitlement change. No entitlement was edited. |
| [C-05](https://trello.com/c/6RaMJbfT) | Strict companion validation, archival export semantics, explicit unbundled labeling, shared Swift/Python fixture and failure coverage | Real consented datasets and D-08 threshold decisions remain separate. |
| [C-03](https://trello.com/c/PA87fkd9) | Console mirrors actual Director status at its existing ≤15 Hz refresh; truthful accepted-shot badges; no lazy controller creation and no manual Take gate | Live rig walkthrough and layout/VoiceOver qualification remain separate. |
| [B-11](https://trello.com/c/aKjuMfoo) | Explicit injected run sheet; current/next labels; operator Advance; validated current style used by a pure preparation decision and operator dwell; style revision retires old work without changing authority | F3 live integration review, production persisted-show identity and the automatic decision scheduler remain pending. No automatic segment advance is added. |

## Hygiene findings and repairs

- A fresh nomination could reuse another subject's cached confirmation/settlement at the final preparation/Take boundary. Current and cached subject UUIDs must now match; the regression covers the interval before the next evidence tick.
- Run-sheet style changes retire both pending permits and preparation using the policy revision while leaving the entire authority value unchanged. Fresh authorized work still succeeds afterward.
- Shadow records now carry the actual segment type and a fresh session-local correlation token; run-sheet names, positions and persisted segment UUIDs are not logged.
- Export selection refuses stale providers and discards an inventory result if its provider changed during the asynchronous read. Failure preserves the visible selection.
- Repeated synthetic session creation uses a current clock. The session selection exposes count, evidence, time range and selection state to accessibility, and Settings bounds the inventory with scrolling.
- C-02/C-06 test discovery uses plain String IDs and resolves UI cases on MainActor. The two retroactive test conformances and their isolation warnings are removed. The imported recorder initialization no longer converts an actor-isolated initializer into a nonisolated map function.
- Independent inspection of PRs 67/68 found no additional actionable issue in stale evidence, numeric style round trips, run-sheet file preservation/editor ownership or Escape handling.

## Validation

Evidence is synthetic unless explicitly stated. Commands and results are recorded below after completion. A passing offline check does not qualify a live Director level or complete an unplug/soak/real-camera walkthrough.

- Full Debug suite: **787 definitions / 1,125 expanded passes, zero failures, three skips**. The UTC precision regression covers all 1,000 wire milliseconds with three sub-millisecond offsets (4,000 assertions including canonical values).
- Manual rehearsal found an initial injected-sheet display gap; initialization now publishes the supplied current/next labels immediately. The subsequent controller/status/privacy checks pass: **38 definitions / 41 expanded passes, zero failures**.
- Python discovery: **31 tests passed**, including 26 shadow report checks. The shared fixture reports 2/2 exact synthetic cuts and a 10-second interior dwell.
- Unsigned Debug and Release app/extension builds pass, including the final explicit accessibility labels. This is not a signed sandbox entitlement check.
- Actual mouse/AX rehearsal: Presenter initially visible; pure choice Wide; explicit Advance selects Panel; pure choice Waist Up. Manual level and epoch 0 remain unchanged, policy revision becomes 1, and last-segment Advance is unavailable. Screenshots are in `evidence/`.
- Explicitly selected both synthetic sessions and created a six-record bundle. The real Swift-produced bundle is retained in `evidence/actual-swift-export`; C-05 validates its manifest and accepts all six rows. These are abstentions with unavailable study parameters, so no tuning or qualification is claimed.
- The Mac locked after successful export, before its final screenshot, repeat-click rehearsal and final label inspection. Automated nonoverwrite and selection tests pass. The gallery remains open; no camera was started. Spoken VoiceOver and signed/real-camera acceptance remain pending.
- Independent review caught and repaired duplicate/raw-integer transport mismatches, stale provider completion, gallery-clock reuse, subject settlement reuse, and relevant test isolation warnings. The precision test initially failed, was repaired, and passed the complete rerun.
- Source fingerprint: `a0097ef1854d8e2e2109fdc93b9c2250b484ab142333a0da10ee0478c75e2c05`. Raw validation logs and xcresults remain under `/private/tmp/alfie-five-hour-20261020`.

The main checkout and its unrelated untracked work were preserved. No main merge, entitlement edit, capture permission, media collection or rig sign-off was performed.
