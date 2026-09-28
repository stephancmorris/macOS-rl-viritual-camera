# Release 2 two-input evidence

**Status: Not run.** These are runbooks and empty result tables. No two-input hardware result or certification is claimed. Use [multi-qa.md](multi-qa.md) for [MULTI-QA](https://trello.com/c/uO1HAlYm), after the Multiview console, admission, Take, diagnostics and degradation integration are present in a candidate build.

Every run records its candidate from `alfie_session_<stamp>.json` (build number, source fingerprint, macOS and machine), the two named inputs and route. If the current manifest only identifies one source, attach a separate verified pair record and mark the diagnostics limitation; do not infer that a single-source row proves two-input behavior.

Freeze numerical budgets **before** each qualification run from a same-rig baseline. Missing hardware or downstream observation remains **unverified**, never a pass. App handoff counts are not physical presentation; capture an external output record for cadence and Take checks. The single-camera R1 60-minute baseline remains a separate prerequisite: [R1 evidence](../release-1/README.md).
