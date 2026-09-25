# [DOCS] Align spec / README with settled next-program behaviors

**Astra role:** coding agent, docs only.  
**Trello:** https://trello.com/c/qNmix3yK  
**Depends on:** a behavior that has actually shipped in code, not a memo.

## Prompt (paste this file as the whole prompt)

You are updating Alfie product docs to match **shipping** behavior after a next-program session landed.

Do not invent features in `ALFIE_SPEC.md` or `README.md` that are not in the tree. Do not rewrite `PHASE_1_SCOPE.md` or `CHURCH_MVP_TASK_LIST.md` (historical). Do not treat `reports/ALFIE_DESIGN_PROGRAM_2026-09-19.md` as the spec — it is discovery; some of it is already stale relative to S1 (hold-to-zoom vs one-rung shot moves).

## When to run this

After **each** of S1–S7 is operator-accepted, run a small docs pass. Do not wait until S7 and dump everything.

## Conflicts already known (fix only if still true in code)

Confirm against the tree before editing:

- Tracking Wide cap vs manual/pan Wide 1.0 (pan travel can be zero)
- Tracking Full Body cap vs spec 0.95
- Program Display is the default route; spec still reads virtual-camera-primary in places
- Product copy says macOS 14+; Xcode `MACOSX_DEPLOYMENT_TARGET` is 26.2
- Spec lists a Resume Tracking pill control that may still be missing (T2)
- Quality floor is a hard ~4× degeneracy limit, not a “comfort tier”
- S1 command dispatcher and zoom exist — spec operator-pill section must list Push in / Pull out if they ship
- After S3: one-camera constraint in the spec mission is wrong; update mission + architecture diagram
- After S4: speech is a command interface, not a new perception policy
- After S7: “no physical PTZ” mission line must change to hybrid digital + 1-DoF yaw, with Return to Wide semantics (current sensor view, not original stage)

## What to update

- `ALFIE_SPEC.md` — architecture diagram, operator console, deferred list, success criteria
- `README.md` — one-paragraph behavior, hardware requirements (second capture card, Pico, actuator — only once those are real)
- Performance table: write measured numbers when T1 soak exists; do not invent latency

## Acceptance

- A volunteer reading README can describe what Sunday Alfie actually does this week.
- Deferred / non-goals still list the wait-list (third channel, SDI, multi-axis, cloud speech).
- No docs-only “features.”

## Out of scope

- Marketing site
- Rewriting training/RL guides unless a flag name changed
- Trello archaeology
