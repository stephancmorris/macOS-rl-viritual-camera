# Explicit run-sheet controller context (B-11)

The controller can receive a validated `RunSheet` explicitly at initialization or through `setRunSheet`. No production show UUID or authored sheet is inferred or restored by this path. Empty/missing sheets use the validated Live event style; invalid or unavailable preferences provide no effective style.

`advanceSegment` is an explicit, non-wrapping action. It updates current/next labels even in Manual, increments the existing policy revision and retires outstanding preparation and Take permits. Its style-scoped `policyChanged` event does not call the authority state machine's global `.policyChanged`: that existing event pauses authority. Segment advancement preserves level, epoch, pause, health and qualification. Saving preferences retains the existing global policy-change behavior.

`choosePreparation` reads the current effective style at invocation and calls the existing pure `DirectorShotPolicy`. It does not dispatch a command or grant permission. The explicit preparation and Take boundaries still revalidate independently. Operator Take dwell uses the same effective style. The default Director tick still samples evidence and reports cut-policy unavailability; this change does not add an automatic scheduler.

The live console can show the supplied sheet and invoke Advance against an already attached Director. It never creates a Director to paint status. The gallery includes a separate synthetic controller rehearsal: a Presenter cadence favors wide at the fixture time, then a Panel cadence favors the stronger close candidate, while Manual authority and its epoch remain unchanged. Fixture values are not production defaults.

Logging uses the actual segment type and a fresh session-local token instead of the persisted segment UUID. Segment names and positions remain out of shadow records. F3's live integration review, production per-show identity/persistence handoff and real-camera acceptance remain pending.
