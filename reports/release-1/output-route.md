# DISPLAY-QA — Program Display and downstream cadence

**Status: Not run.** Card: https://trello.com/c/HFyNhYO3

Goal: the named destination receives Alfie's clean program at the session-frozen show standard. Matching display refresh is necessary, not sufficient. Initial church qualification: Program Display → HDMI converter → ATEM at **1080p50**. Qualify 59.94/60 only if claiming them.

## Candidate and route

| Item | Value |
| --- | --- |
| Source fingerprint / build | |
| Mac model, macOS | |
| Program Display (name, as selected in Settings → Output) | |
| Display mode reported by **Settings → Output → bring-up checks** (size @ Hz) | |
| Converter make/model and its output format | |
| ATEM model, input number, input format as shown by ATEM | |
| Show standard | |

## Procedure

1. Set the show standard, select the Program Display, Start capture. Confirm the bring-up check "Program Display · Mode" is OK (refresh matches the standard). Record the check text.
2. Confirm the ATEM input shows Alfie's crop, **no overlays, no cursor, no menu bar**, full frame, correct aspect.
3. Cut the ATEM to that input (Program) and back (Preview) — verify the picture on both ATEM outputs, not just the control app.
4. Record the ATEM multiview or program output with an external recorder for 5 minutes including movement and a Push in / Pull out. Count repeated/dropped frames in the recording (frame-step a 20 s section of steady pan).
5. Unplug the Program Display cable for 10 s, reconnect. Record what Alfie shows (route status), whether the operator window stayed on the operator screen, and whether the program window returned to the **same** display.
6. Stop; run `scripts/diagnostics_report.py` on the session and attach it.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| Bring-up mode check matches standard | | |
| Clean frame on ATEM input (no overlays/cursor) | | |
| ATEM Preview and Program both show the input | | |
| Downstream cadence from external recording (frames repeated / dropped per 20 s) | | |
| Alfie handoff fps over the same period (from the summary) | | |
| Reconnect: no route stealing, same display restored | | |
| Unsupported modes observed (list) | | |

Handoff fps is what Alfie sent; the external recording is the only evidence of physical cadence. Do not report one as the other.

## Outcome

- [ ] No route stealing on reconnect; no overlays; physical cadence evidence distinct from sends; unsupported modes listed.
