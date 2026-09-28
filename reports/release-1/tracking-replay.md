# TRACK-QA — identity and framing on matched footage

**Status: Not run.** Card: https://trello.com/c/lxmF5I9Q

Goal: uncertain identity holds or widens rather than switching confidently to someone else. Replay the **same raw source, settings and selection** on the baseline and the candidate; interface recordings are not equivalent raw inputs.

## Corpus

Consented clips only. Record each clip's source resolution and rate. Use Alfie's validation-clip input (Inspector → Playback, shown while `DeveloperFlags.exposeClipPlaybackControls` is on) so both builds see identical frames.

| Clip | Scenario | Duration | Resolution / fps | People visible | Selection (who, when) |
| --- | --- | --- | --- | --- | --- |
| | Pacing at lectern distance | | | | |
| | Lectern turns (face lost) | | | | |
| | Tiny faces (far subject) | | | | |
| | Occlusion (walks behind) | | | | |
| | Projected person on screen | | | | |
| | Crossing another person | | | | |

## Procedure

1. Pin both builds: baseline fingerprint and candidate fingerprint (from each session manifest).
2. For each clip and build: Start with the clip, Detect → tap the named person at the recorded time, Crop, let it play to the end. Keep the session files.
3. Screen-record the program pane. A reviewer marks: wrong-person switches, time to recover after loss, time spent held/wide, and a 1–5 framing judgement.
4. Attach the diagnostics summary for each run (observation age and detection rate come from it).

## Results

| Clip | Build | Wrong-person switches | Recoveries / losses | Mean recovery s | Held/wide s | Framing 1–5 | Reviewer |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | baseline | | | | | | |
| | candidate | | | | | | |

Denominators matter: report switches per clip and per loss event, not a single percentage.

## Outcome

- [ ] Corpus, denominators, both fingerprints and reviewer recorded.
- [ ] No wrong-person switches in the release corpus.
- [ ] Each reproduced failure filed as a focused defect with a regression fixture; no universal accuracy claim.
