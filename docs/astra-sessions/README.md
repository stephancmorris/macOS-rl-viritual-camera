# Alfie implementation briefs

The directory name is historical. Use GPT-6 Sol for implementation and Luna for bounded supporting work. The current R2 authority is [ALFIE_MULTICAMERA_SPEC.md](../ALFIE_MULTICAMERA_SPEC.md); it supersedes the September 19 dual-output design. Work one ticket at a time, not the whole release.

## How to use a brief

1. Finish the previous session’s acceptance gate (or the human rehearsal named in that file).
2. Open **one** file.
3. Read the canonical R2 spec and the selected ticket before implementation.
4. Keep the agent on that session. If it starts S3 during S2, stop it.

## Order

| Order | File | Agent job | Human job first? |
| --- | --- | --- | --- |
| 0 | [00-PROGRAM.md](00-PROGRAM.md) | Read-only map. Do not implement from this file. | No |
| 1 | [S2-extract-channel.md](S2-extract-channel.md) | Independent channels, bounded scheduling, one routed output | R1 gate; preserve single-camera equivalence first |
| 2 | [S3-usable-multi-input.md](S3-usable-multi-input.md) | Program/Preview, explicit Take, one feed to ATEM | Core routing and command contracts tested |
| Deferred | [S4-speech-to-action.md](S4-speech-to-action.md) | Historical speech proposal | Only reconsider after R1 and R2 validation |
| 4 | [HARDWARE-OPTIONS.md](HARDWARE-OPTIONS.md) | Design-only. Buy/print decisions. No firmware yet | Read before S5 |
| 5 | [S5-hardware-link.md](S5-hardware-link.md) | USB + simulator, ping, telemetry, e-stop. No motion | S2 channel ownership. DECIDE Q7 |
| 6 | [S6-actuator-bench.md](S6-actuator-bench.md) | Jog/goto one cheap linear actuator | S5 green. Parts on the bench. DECIDE Q8 |
| 7 | [S7-hybrid-yaw.md](S7-hybrid-yaw.md) | Physical yaw + digital zoom/fine pan | S6 stop-distance measured |
| 8 | [DOCS-align-spec.md](DOCS-align-spec.md) | Update spec/README after a behavior settles | After each landed session, not as a pile at the end |

**Current-code reference:** [ALFIE_ENGINEERING_SPEC.md](../ALFIE_ENGINEERING_SPEC.md). R2 design authority: [ALFIE_MULTICAMERA_SPEC.md](../ALFIE_MULTICAMERA_SPEC.md). S5–S7 hardware briefs are historical/deferred until both releases validate; they are not the next implementation assignments.

## What these files are not

- Not a second product spec. `ALFIE_ENGINEERING_SPEC.md` is the current-tree spec; `ALFIE_SPEC.md` is the product story and is stale in places (see §13 of the engineering spec).
- Not permission to generalize Alfie into a broadcast suite.
- Not a shopping list you must buy before S2. Hardware buying starts at `HARDWARE-OPTIONS.md`.

## Locked product rules (every session)

- Volunteer pill stays the live surface.
- Return to Wide is one action and always available.
- Manual override outranks automatic recovery.
- Truthful preview: the operator sees what Alfie submitted downstream.
- Soft failure: hold last good program. Never publish raw source on render failure.
- Speech and hardware must call `CommandDispatcher`. No second control path.
- Do not bind output selection to operator focus (that is a silent cut).
