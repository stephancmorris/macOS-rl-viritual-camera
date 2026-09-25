# Astra session briefs — Alfie next program

These files are the briefs you paste into the Astra design/coding agent. Each file is one session. Do not paste the whole folder at once.

## How to use a brief

1. Finish the previous session’s acceptance gate (or the human rehearsal named in that file).
2. Open **one** file.
3. Paste the whole file into Astra as the prompt.
4. Keep the agent on that session. If it starts S3 during S2, stop it.

## Order

| Order | File | Agent job | Human job first? |
| --- | --- | --- | --- |
| 0 | [00-PROGRAM.md](00-PROGRAM.md) | Read-only map. Do not implement from this file. | No |
| 1 | [S2-extract-channel.md](S2-extract-channel.md) | Extract Channel; two real cameras; one routed output | S1 zoom must feel right on a real camera |
| 2 | [S3-usable-multi-input.md](S3-usable-multi-input.md) | A/B pill + two Program Displays into the ATEM | DECIDE Q1 + Q6 (Mac, cards, displays) |
| 3 | [S4-speech-to-action.md](S4-speech-to-action.md) | Offline wake-prefix commands | Command layer stable. Must not delay S2/S3 |
| 4 | [HARDWARE-OPTIONS.md](HARDWARE-OPTIONS.md) | Design-only. Buy/print decisions. No firmware yet | Read before S5 |
| 5 | [S5-hardware-link.md](S5-hardware-link.md) | USB + simulator, ping, telemetry, e-stop. No motion | S2 channel ownership. DECIDE Q7 |
| 6 | [S6-actuator-bench.md](S6-actuator-bench.md) | Jog/goto one cheap linear actuator | S5 green. Parts on the bench. DECIDE Q8 |
| 7 | [S7-hybrid-yaw.md](S7-hybrid-yaw.md) | Physical yaw + digital zoom/fine pan | S6 stop-distance measured |
| 8 | [DOCS-align-spec.md](DOCS-align-spec.md) | Update spec/README after a behavior settles | After each landed session, not as a pile at the end |

**Current-code authority for onboarding:** [`docs/ALFIE_ENGINEERING_SPEC.md`](../ALFIE_ENGINEERING_SPEC.md) (architecture, detection constants, and S2–S7 implementation gaps as of 19 September 2026). Session briefs below stay the paste-into-Astra prompts.

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
