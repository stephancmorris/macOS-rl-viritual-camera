# Five-item follow-up delivery

18 October 2026. Base: baf1418. All five scoped work items are implemented and verified. This is software/synthetic evidence, not live Director qualification.

| Work item | Result |
| --- | --- |
| C-02 / MR-01 | Qualified selection updates the gallery status to Watching; explicit takeover/handback works; unrelated fault reasons remain. Regression fails before the fix and passes after. |
| SHOW-SETUP / MR-02 | Stopped setup says Planned output, at the selected rate. Actual UI checked at 50.00 and 59.94 fps; original 1080p50 restored; Start never pressed. |
| A-02 follow-up | Negative person counts classify unavailable, immediately inhibit a confirmed adapter and fail both readiness bars; zero/one/multiple semantics and declared wideWaiting loss remain. The separate adapter debounce issue is still open. |
| A-05 follow-up | Effective segment profiles merge against the other input's Live-event fallback in either order. Incompatible constraints refuse; no schema/default/authority change. |
| C-05 | Offline JSONL-to-Markdown script, typed schema table, synthetic fixture, CLI guide and deterministic example delivered. Separate prepare/cut agreement rows, abstentions, dwell and completeness accounting. |

Validation: final full Swift unit target **670 definitions / 946 executions passed, zero failures, three opt-in skips**. The initial four regression definitions failed before repair. A later adapter-specific regression also failed before its immediate-inhibition fix; the final full run includes that case and the Swift fixture decoder. C-05 has **13 passing Python tests**. Intermediate counts in the manifest overlap; do not sum them as independent exposure. The fixture passes the app's actual Swift schema decoder.

UI screenshots were captured from the passing initial repair build; the only subsequent app-source change was the tested negative-count adapter guard. The final manifest records both source fingerprints. Assist selection, takeover/handback, stopped 50.00/59.94 fps target wording and restoring 1080p50 were observed. All Alfie candidates were confirmed exited afterward.

Fresh-cache Xcode attempts failed before tests because SDK/App Intents/Metal tooling was unavailable. Reusing the earlier baseline compiler cache succeeded with the normal Debug command and signing disabled; the logs/results remain in /private/tmp/alfie-followups-20261018. No Xcode installation or project setting was changed. The successful runs prove the exercised source behavior, not a clean-cache/toolchain installation check.

[Validation manifest](validation.json), [Assist screenshot](fix-assist.jpg), [stopped setup](fix-stopped.jpg), [fractional rate](fix-stopped-fractional.jpg), [C-05 guide](../../../docs/auto-director/shadow-report.md), [example report](../shadow-report-synthetic-example.md).

No live cut, camera session, media collection, owner decision or qualification was performed. Four repairs complete their scoped follow-ups; broader parent-card live acceptance remains as previously recorded. B-04 export and full B-06 qualification integration are unchanged. Trello statuses were not moved by this delivery.
