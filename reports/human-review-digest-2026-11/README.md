# Human Review digest (4 November 2026)

Trello: [HR-DIGEST](https://trello.com/c/IwgrhJkg). Source: `origin/main` after PR #92. Board snapshot: 👀 Human Review, 92 cards.

**Method.** For each card, the commits, PRs and branches named in its description (or its ticket key, such as `A-07` or `SU-04`) were checked against merged PRs and `git merge-base --is-ancestor <sha> origin/main`. Gates were read from labels (`needs:device-test`, `needs:privacy-review`) and from wording on the card: rig, receiver, physical, signed install, owner decision, sign-off, sitting.

**Result.** Every card's software is on `main`: class (d), evidence missing, is **0**. Twelve cards had no reference in their description. They were traced through their ticket key or a later integration: A-09 (commits on main), C-06 (`DirectorNextCutNotice` on main), SU-09 and SU-10 (#84 via #85), and today's cards.

| Class | Cards |
|---|---|
| (a) recommend Done | 54 |
| (b) waiting on a rig, receiver or privacy gate | 23 |
| (c) waiting on an owner decision | 15 |
| (d) evidence missing | 0 |

Class (a) means software complete with no physical or decision gate named on the card. Move these to Done only if you agree the card asked for nothing on the rig. Software tests never satisfy a physical, release, privacy or qualification gate. Classes (b) and (c) stay in Human Review until their gate is met.

## (a) Software complete, recommend Done

| Card | Delivered by | Gate |
|---|---|---|
| [[HYGIENE][B13][REFACTOR] Split ShotComposer.swift (move only) · Sol 6.1](https://trello.com/c/JkIvhOM8) | #88 | – |
| [[R2][MODE-MODEL][FEATURE] Add the three-mode model and derive format, capture profile and console from it](https://trello.com/c/A7kvW5VM) | #77 | – |
| [[R2][MODE-SWITCH][FEATURE] Pick Single Cam / Multi Cam / Webcam from the main window and guard live switches](https://trello.com/c/fGLSkXF7) | #77, e972b2a, codex/single-cam-webcam-testing | – |
| [[R3][AD-DATASET-DIGEST][FIX] Bind scorer datasets to the bytes actually parsed](https://trello.com/c/8vf2UFYx) | 33ba93a, codex/next-ticket-batches-2026-10-24 | – |
| [[R3][AD-EVIDENCE-FINGERPRINT][TOOL] Identify exact shadow input bytes in reports](https://trello.com/c/sB0AbpE0) | 980fffc, codex/next-ticket-batches-2026-10-24 | – |
| [[R3][AD-EVIDENCE-INVENTORY][TOOL] Report declared evidence classes and accepted counts explicitly](https://trello.com/c/URMUc3OZ) | codex/next-ticket-batches-2026-10-24 | – |
| [[R3][AD-EVIDENCE-STATUS][FIX] Keep evaluation session summaries consistent with capture completeness](https://trello.com/c/FsPvuofO) | de3b993, codex/next-ticket-batches-2026-10-24 | – |
| [[R3][AD-MATCH-WINDOW][TOOL] Retain the actual matching window in evaluation artifacts](https://trello.com/c/PfUxs7j0) | codex/next-ticket-batches-2026-10-24 | – |
| [[R3][AD-MEMO-COMPLETENESS][FIX] Keep source loss and missing bindings visible in parameter memos](https://trello.com/c/7QVGgPMu) | codex/next-ticket-batches-2026-10-24 | – |
| [[R3][AD-PARAMETER-ATTRIBUTION][FIX] Separate speed evidence by segment, settings and input](https://trello.com/c/nB2el8ZI) | f2afb0b, codex/next-ticket-batches-2026-10-24 | – |
| [[R3][AD-PHASE-MODEL-SAMPLES][FIX] Preserve unobserved judge samples within study phases](https://trello.com/c/2BkIe1XZ) | codex/next-ticket-batches-2026-10-24 | – |
| [[R3][AD-TRAINING-COMPLETENESS][FIX] Refuse scorer training when C-05 blocks source sessions](https://trello.com/c/tSDoot5K) | codex/next-ticket-batches-2026-10-24 | – |
| [[R3][AD-WINDOW-PRECISION][FIX] Preserve matching-window precision in standalone reports](https://trello.com/c/qZ9gNww6) | 3a390fa, codex/next-ticket-batches-2026-10-24 | – |
| [[R3][RUNSHEET-FOLLOWUPS][FIX] Current marker follows Advance; Dark sheet background · Sol 6.1](https://trello.com/c/K3yljzlQ) | #89 | – |
| [[R3][S3 A-01][Sol 6.1] Reconcile shot vocabulary (N3)](https://trello.com/c/KEP9a0e6) | #6 | – |
| [[R3][S3 A-02][Sol 6.1] Identity evidence and two readiness bars (P1, P2, N5)](https://trello.com/c/Pp4Qx61z) | #7 | – |
| [[R3][S3 A-03][Sol 6.1] Authority levels v2 and Assist semantics (U2, A1, N1)](https://trello.com/c/lTm0DOzF) | #11 | – |
| [[R3][S3 A-04][Sol 6.1] Console status model and control API (U2)](https://trello.com/c/mvNmZuap) | #10 | – |
| [[R3][S3 A-05][Sol 6.1] One parameter source and style profiles](https://trello.com/c/8PTAcfTW) | #8 | – |
| [[R3][S3 A-06][Sol 6.1] DirectorJudge seam (AI-1)](https://trello.com/c/Vaxqejhv) | #9 | – |
| [[R3][S3 A-07][Sol 6.1] Evidence adapter (pure)](https://trello.com/c/DHZ8Yyc4) | #12 | – |
| [[R3][S3 A-08][Sol 6.1] Replay through the sink protocol](https://trello.com/c/2tGH9vfr) | #18 | – |
| [[R3][S3 A-10][Sol 6.1] Shot policy v2 for Assist](https://trello.com/c/bZJ8YmgQ) | #25 | – |
| [[R3][S3 A-11][Sol 6.1] TakePermit and level-aware Take events (A3, N1)](https://trello.com/c/ubKJgTwM) | #26 | – |
| [[R3][S3 A-12][Sol 6.1] CutPolicy and CutNotice](https://trello.com/c/khjdjadA) | 434e26a | – |
| [[R3][S3 A-13][Sol 6.1] RunSheet and StyleProfile model (F3)](https://trello.com/c/s0beu1Pm) | 434e26a | – |
| [[R3][S3 A-14][Sol 6.1] SubjectSelector (E1, P2)](https://trello.com/c/UL42Le8H) | 434e26a | – |
| [[R3][S3 A-15][Sol 6.1] On-air move policy (N2)](https://trello.com/c/UH9qLSdJ) | 434e26a | – |
| [[R3][S3 A-17][Sol 6.1] Backup fallback rule (R1, R2)](https://trello.com/c/uNbaquTL) | 434e26a | – |
| [[R3][S3 B-00][Opus 5.5] Make OperatorCommand.Preset shareable (merge first)](https://trello.com/c/Udx29X9T) | #3 | – |
| [[R3][S3 B-01][Opus 5.5] Read-only evidence accessors](https://trello.com/c/xppmScjj) | #4 | – |
| [[R3][S3 B-02][Opus 5.5] Director origin and manual-action hook](https://trello.com/c/DxeOCC66) | #5 | – |
| [[R3][S3 B-03][Opus 5.5] DirectorController in shadow mode](https://trello.com/c/pj2ZbM6j) | #22 | – |
| [[R3][S3 B-07][Opus 5.5] Permit-checked Take (A3)](https://trello.com/c/DCd6gN5I) | 434e26a | – |
| [[R3][S3 B-11][Opus 5.5] Run sheet wiring (F3)](https://trello.com/c/aKjuMfoo) | 12a2bc5 | – |
| [[R3][S3 C-01][Grok 4.7] Director gallery states](https://trello.com/c/8UiB9wGU) | #13 | – |
| [[R3][S3 C-02][Grok 4.7] Mode control and Hand to Alfie (U2, A1)](https://trello.com/c/4FVemMN9) | #14 | – |
| [[R3][S3 C-03][Grok 4.7] Next-shot director line and AUTO tile badge](https://trello.com/c/PA87fkd9) | #16 | – |
| [[R3][S3 C-04][Grok 4.7] Style settings and preferences store (F1)](https://trello.com/c/tE0tzjNz) | #17 | – |
| [[R3][S3 C-06][Grok 4.7] Next-cut notice UI (A4)](https://trello.com/c/auY6HYtj) | main (DirectorNextCutNotice) | – |
| [[R3][S3 C-07][Grok 4.7] Run sheet editor and strip (F3)](https://trello.com/c/JAU8oFd7) | 12a2bc5 | – |
| [[R3][S3 C-08][Grok 4.7] Subject pick display and override (E1)](https://trello.com/c/7BJdvATP) | #70, #71 | – |
| [[R3][S3 D-05][Astra] Rehearsal runbooks](https://trello.com/c/Csi7ssyT) | 434e26a | – |
| [[R3][SU-01][Opus 5.5] Load saved Director styles at launch](https://trello.com/c/u9jGWzzb) | #78 | – |
| [[R3][SU-02][Sol 6.1] DirectorFeel and feel table v1](https://trello.com/c/dWeFphQF) | #78 | – |
| [[R3][SU-03-SETTLE-EVIDENCE][FIX] Track settling under the style's actual motion bound](https://trello.com/c/JRBFINdK) | #82, 82cca82, b98dad8, claude/director-wave-2 | – |
| [[R3][SU-03][Sol 6.1] Enforce settle time before director-ready recommendations](https://trello.com/c/tbiVuVba) | #78 | – |
| [[R3][SU-04][Opus 5.5] Built-in Live event style when nothing is saved](https://trello.com/c/NeFGaJvf) | #80 | – |
| [[R3][SU-05][Grok 4.7] Settings › Director: feel choices, autosave, exact values](https://trello.com/c/5rdCXiC9) | #79 | – |
| [[R3][SU-06][Sol 6.1] Rhythm preview from the real policy](https://trello.com/c/zOz51WTQ) | #82 | – |
| [[R3][SU-07][Opus 5.5] Mid-show style change pauses, applies on Hand to Alfie](https://trello.com/c/htQr6kuK) | #82 | – |
| [[R3][SU-08][Astra] Document feel table v1 and the new Director settings](https://trello.com/c/yrb9YKrE) | #82 | – |
| [[R3][SU-09][Grok 4.7] Run sheet in Show setup with a durable show identity](https://trello.com/c/K59uZ1IC) | #85 (via #84) | – |
| [[R3][SU-10][Opus 5.5] Run sheet drives the Director in a live show](https://trello.com/c/ETj5sOD5) | #85 (via #84) | – |

## (b) Software complete, waiting on a rig, receiver, install or privacy gate

| Card | Delivered by | Gate |
|---|---|---|
| [[24 OCT BATCH] Restore verification and retire stale pair starts](https://trello.com/c/7lJuEA8O) | #81, 12a2bc5, 92cb8c0, codex/next-ticket-batches-2026-10-24 | rig, receiver or device test |
| [[R1][CAPTURE][FEATURE] Choose capture formats for Stage and Webcam](https://trello.com/c/Ed2ctBWc) | #77, e972b2a, codex/single-cam-webcam-testing | rig, receiver or device test |
| [[R1][DOCS][DOCS] Operator guide and current capability contract](https://trello.com/c/qNmix3yK) | #72, #73, #76, 238f8d2, 2d1b4ea, codex/director-study-evidence | rig, receiver or device test |
| [[R1][FRAMING-PIPELINE][FIX] Preserve replay continuity, actor parity and valid BC splits](https://trello.com/c/OgqmUJvo) | #76, 238f8d2, codex/director-study-evidence | rig, receiver or device test |
| [[R2/R3][SOURCE-LIFETIME][FIX] Bind source provenance to non-reused instance IDs](https://trello.com/c/P3z9tx7P) | codex/next-ticket-batches-2026-10-24 | rig, receiver or device test |
| [[R2][ADMISSION-LIVE-VETO][FIX] Honour a current failed pair check alongside historical certification](https://trello.com/c/qp95US3G) | codex/next-ticket-batches-2026-10-24 | rig, receiver or device test |
| [[R2][ADMISSION][FEATURE] Admit two-input configurations using measured workload budgets](https://trello.com/c/9oUnHGu4) | #73, #77, e972b2a, codex/single-cam-webcam-testing | rig, receiver or device test |
| [[R2][PAIR-FIRST-FRAME][FIX] Prove initial Program handoff before starting Preview](https://trello.com/c/spNkdsvk) | #86 | rig, receiver or device test |
| [[R2][RECORD-STOP][FIX] Close recording admission in the operator Stop action](https://trello.com/c/UUrJrSXP) | codex/next-ticket-batches-2026-10-24 | rig, receiver or device test; privacy review |
| [[R2][SCHEDULER-PRIORITY][FIX] Reset contention history for the current Program](https://trello.com/c/XmaaT3MT) | codex/next-ticket-batches-2026-10-24 | rig, receiver or device test |
| [[R2][SHOW-FORMAT-LIFETIME][FIX] Freeze the standard while any input runs or starts](https://trello.com/c/oFzfzIib) | e1a22f1, codex/next-ticket-batches-2026-10-24 | rig, receiver or device test |
| [[R2][SHOW-SETUP][FEATURE] Assign inputs to slots and run the two-camera check before Start](https://trello.com/c/ztw0PPkU) | #73, #77, e972b2a, codex/single-cam-webcam-testing | rig, receiver or device test |
| [[R2][TAKE-CLOCK][FIX] Reject invalid or future Preview timing and nonfinite dimensions](https://trello.com/c/AzTxvqP6) | codex/next-ticket-batches-2026-10-24 | rig, receiver or device test |
| [[R3][AD-BINDING-API][FIX] Validate legacy evaluation bindings at the Python entry point](https://trello.com/c/v5e2dwnA) | 952d05d, ff261ea, codex/next-ticket-batches-2026-10-24 | rig, receiver or device test |
| [[R3][S3 A-09][Sol 6.1] Shadow record type](https://trello.com/c/RADJVXDn) | main commits (A-09) | privacy review |
| [[R3][S3 B-05][Opus 5.5] Assist off-air preparation sink](https://trello.com/c/UDJjhR6j) | #73 | rig, receiver or device test |
| [[R3][S3 B-08][Opus 5.5] Cut execution and notice (A3, A4)](https://trello.com/c/aDEyv84C) | #69, #70, a20a348 | rig, receiver or device test |
| [[R3][S3 B-09][Opus 5.5] On-air slow move sink (N2)](https://trello.com/c/q4H7i3Bt) | #69, #70, a20a348 | rig, receiver or device test |
| [[R3][S3 B-10][Opus 5.5] Bounded subject discovery mode (E1)](https://trello.com/c/9ifoF0DZ) | #70, #71 | rig, receiver or device test |
| [[R3][S3 B-12][Opus 5.5] Backup fallback execution (R2)](https://trello.com/c/axfQoBKj) | #69, #70, a20a348 | rig, receiver or device test |
| [[R3][S3 B-13][Opus 5.5] Backup level wiring](https://trello.com/c/LTxj751i) | #69, #70, a20a348 | rig, receiver or device test |
| [[R3][S3 C-09][Grok 4.7] Backup alerts](https://trello.com/c/DRRk4TJu) | #69, #70, a20a348 | rig, receiver or device test |
| [[R3][S3 D-02][Astra] Shadow record schema and privacy note (C3, AI-4)](https://trello.com/c/HBSY3JF2) | #15 | privacy review |

## (c) Waiting on an owner decision or sign-off

| Card | Delivered by | Gate |
|---|---|---|
| [[R2][DEVICES][INFRA] Allocate and start two capture devices independently](https://trello.com/c/F96mnFgL) | #74 | owner decision / sign-off; rig, receiver or device test |
| [[R2][MODES-SPEC][DOCS] Record the three operator modes: Single Cam, Multi Cam, Webcam](https://trello.com/c/EcUhCgvE) | #77 | owner decision / sign-off |
| [[R2][PRIVACY][COMPLIANCE] Privacy, camera consent and diagnostic data audit](https://trello.com/c/ecKr4f2R) | #72, #73, #74, #76, 238f8d2, 3c8a7d4, codex/director-study-evidence | owner decision / sign-off; rig, receiver or device test; privacy review |
| [[R2][SINGLE-CAM][FEATURE] Bring back the single-camera console with every Stage shot](https://trello.com/c/pgwTdM7I) | #77, e972b2a, eb22299, codex/single-cam-webcam-testing | owner decision / sign-off; rig, receiver or device test |
| [[R3][AD-RECONCILE][REPORT+FIX] Reconcile AD-AUTHORITY-CORE / AD-LIFECYCLE / AD-POLICY / AD-INTEGRATE with the shipped S3 tickets · Sol 6.1](https://trello.com/c/jhhQuzKv) | #90 | owner decision / sign-off; rig, receiver or device test |
| [[R3][S3 A-16][Sol 6.1] LearnedJudge adapter (CoreML)](https://trello.com/c/E4adcm5o) | #70, #71, #74, #75 | owner decision / sign-off; rig, receiver or device test |
| [[R3][S3 B-04][Opus 5.5] Shadow logging to disk (AI-4, C3)](https://trello.com/c/3tyDYrWL) | #73, #74, #75, #76, 238f8d2, codex/director-study-evidence | owner decision / sign-off; rig, receiver or device test; privacy review |
| [[R3][S3 B-06][Opus 5.5] Qualification records per level](https://trello.com/c/KfmsFyHQ) | #24, #19 | owner decision / sign-off |
| [[R3][S3 C-05][Grok 4.7] Shadow report script](https://trello.com/c/6RaMJbfT) | #73, #74, #75, #76, 238f8d2, 3f9797e, codex/director-study-evidence | owner decision / sign-off; rig, receiver or device test |
| [[R3][S3 C-10][Grok 4.7] Learned scorer training (after shadow data)](https://trello.com/c/7HOi1AOx) | #72 | owner decision / sign-off; privacy review |
| [[R3][S3 D-01][Astra] Reconcile the specs with recorded decisions](https://trello.com/c/551GFUVp) | #20 | owner decision / sign-off |
| [[R3][S3 D-03][Astra] Discovery workload protocol (C1, C2)](https://trello.com/c/pO1kLChg) | #27 | owner decision / sign-off; rig, receiver or device test |
| [[R3][S3 D-04][Astra] Qualification protocol and record format (Q1–Q3)](https://trello.com/c/9qoW56pQ) | #24 | owner decision / sign-off; rig, receiver or device test |
| [[R3][S3 D-06][Astra] Run and report evaluations per level](https://trello.com/c/865rDWWm) | #72, #74, #75, #76, 238f8d2, fcf2cc4, codex/director-study-evidence | owner decision / sign-off; rig, receiver or device test |
| [[R3][S3 D-07][Astra] Consent and fixture register (E3, AI-3)](https://trello.com/c/rvrRqGbH) | 434e26a | owner decision / sign-off; privacy review |

