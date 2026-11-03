# Next software slice: initial Program handoff before Preview starts

Status: queued, not implemented. This does not alter the seven verified repairs.

The current `LiveShowSetupModel.startPair` waits for A's startup to finish and checks `isRunning`, then adds/starts B. That does not prove a processed Program picture reached the chosen sink. The multicamera lifecycle contract requires a legal fresh initial A frame to reach the output before starting B. The existing synthetic positive ordering test uses `ProgramOutputManager(sinks: [])`, produces no rendered frame and nevertheless starts B; it demonstrates the current behavior without establishing output readiness.

`ProgramRouter.state == .routed` cannot substitute for handoff acceptance: `submit` changes that state before forwarding the frame, while `ProgramOutputManager.sendFrameAccepted` can still return false. Ordinary host counters are also not physical receiver presentation. Do not close DISPLAY-QA or MODE-QA from this software gate.

## Implementation boundary

Use one bounded initial-acceptance state/event tied to the actual camera owner/generation, route/output session and legal fresh rendered frame. Keep the existing router and sink as the only output owner. Do not add per-frame Published state, relax Take rules or choose a new timeout/performance budget. Keep A running with a truthful waiting reason when the output has not accepted a frame. Starting B remains an explicit retained pair intent, never an automatic fallback or Program promotion.

Retire pending admission on Stop, mode departure, source replacement and output/route changes. Reuse the new Stop token and camera lifetime identities; a late old acceptance must not start B in a newer show. Verify Rehearsal with actual synthetic sink acceptance and preserve B-failure isolation.

## Required evidence

- A running flag without a frame, a missing/refusing sink, and held/stale/wrong-source/retired-route evidence do not start B.
- One legal fresh accepted A frame starts the selected B once, after A; preserve the existing ordering test by supplying valid acceptance evidence.
- Stop/restart, leave-and-return mode switches, replacement sources and output changes retire the old wait.
- The operator sees why the pair is waiting; A remains usable and no alternative input is silently routed.
- Run the affected setup/router/Take/source-lifetime suites, then complete Swift verification and Release build. Manual camera/receiver and signed-install gates remain separate.

Likely files: `LiveShowSetup.swift`, `ShowCoordinator.swift`, `ProgramRouter.swift`, `ProgramOutputManager.swift`, setup/status UI if needed, and their existing test suites. No implementation or acceptance is claimed by this plan.
