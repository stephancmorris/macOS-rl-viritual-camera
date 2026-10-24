# Next group after PR #72

This is a grouping of existing tickets, not new duplicate cards or approval to bypass their gates. The software candidate is `codex/director-evaluation-tools`, stacked on PR #71. Build and source fingerprint must be pinned again if dependencies change.

## Candidate acceptance group

| Existing ticket | Concrete next action | Can proceed with software alone? |
|---|---|---|
| [DOCS](https://trello.com/c/qNmix3yK) | Walk and capture the guide on the exact candidate at 1280 points; verify visible labels, stopped-mode behavior, refusal reasons and VoiceOver order. Separate camera/receiver instructions from the stopped UI walk. | Partial. Stopped UI can be reviewed now; camera/receiver and signed-install steps need the rig. |
| [PRIVACY](https://trello.com/c/ecKr4f2R) | Exercise camera permission refusal/revocation, fresh-install session files and explicit metrics export; inspect retained files against the inventory. Include the isolated 30-day diagnostics cleanup regression added to this candidate. | Partial. The automated cleanup/export/consent tests are software evidence; live OS permission and retained-store checks require the named candidate/environment. |
| [MODE-QA](https://trello.com/c/bHd5ACBW) | Follow the existing mode walkthrough across Single Cam / Multi Cam / Webcam, both output routes, stopped and refused live mode changes, source loss and recovery. | No full acceptance without real cameras, receivers and installation evidence. |
| [D-06](https://trello.com/c/865rDWWm) | Run D-05's attended Assist rehearsals using D-07's provenance/consent procedure; preserve explicit exports, independent opportunity labels, route and settings before analysis. Investigate the visible synthetic panel wrong-subject case without hiding it in aggregate counts. | Synthetic reporting is implemented. Recorded/live runs and per-level sign-off require the rig, independent labels and frozen owner parameters. |

The bounded diagnostics cleanup seam preserves the existing thirty-day modification-time policy. It does not extend that policy to recordings, archives or other stores, nor establish deletion while the app is closed. No new retention duration is selected.

## Work that remains gated

- [C-10](https://trello.com/c/7HOi1AOx): use the completed pipeline when a credible provenance-preserving metadata export, explicit label rationale and event-aware split specification exist. The synthetic scorer tied RuleJudge; infrastructure success alone supplies no model promotion case.
- [C-07](https://trello.com/c/JAU8oFd7) and [B-11](https://trello.com/c/aKjuMfoo): build the optional run-sheet editor, persistence/strip and controller wiring after the owner records F3. The current model foundation is not approval to select run-sheet behavior. Advance must remain a style/policy change with no authority effect.
- [DEGRADE](https://trello.com/c/hBhrDnIQ): requires readiness calibration, admission evidence and sustained-load measurements before scheduler/status changes or additional Take refusal.
- Conditional cleanup, easing and display work require the measured problem and, where stated, accepted replay/curve evidence. Do not invent performance work solely to consume allowance.

No automatic cut level is qualified, and no owner decision or physical acceptance gate is advanced by this grouping.
