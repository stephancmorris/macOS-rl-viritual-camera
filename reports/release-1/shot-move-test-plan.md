# S1 shot move rehearsal

Use this after installing a locally built Alfie on the actual one-camera setup. These are operator checks to record, not results from a hardware test. Keep the app window at its 1280-point minimum width and use one hand on the pill while watching the program pane. Run at the show's actual format and rate. Keep the source view available for identity checks, but judge shot motion in the program view.

## Run record

| Item | Record before starting |
| --- | --- |
| App build / date / Mac |  |
| Source make and model, connection, delivered resolution and frame rate |  |
| Output route and receiver (Program Display, virtual-camera client, or physical converter/ATEM input) |  |
| Show standard and measured output rate (50, 59.94, or 60 fps) |  |
| Candidate identity and clothing/location marker used for the lock |  |
| Other visible people and lighting / occlusion conditions |  |

For each row, mark pass/fail, the timecode of any defect, and whether it appeared in Alfie's program pane, the downstream receiver, or both. A smooth-looking preview alone does not prove downstream delivery.

## One-handed pass

1. At 1280 points, confirm Detect, Stage presets, Crop, Manual, Auto Pan, Pull out, Push in, Return to Wide, and Stop remain visible and tappable. Choose the intended source and output. Start capture; verify the receiver shows the same framing and record its delivered rate.
2. Select Stage **Wide**, then begin uncropped with **Return to Wide**. Tap **Push in** once; watch the whole move without holding the button. It should enter Manual and land on Full Body. Tap again to reach Waist Up; each tap lands one rung. At Waist Up, Push in is unavailable. Tap **Pull out** twice to return one rung at a time. Try the opposite button during a move: it should smoothly reverse toward the origin. Repeated same-direction taps during one move should not restart it or skip a rung.
3. Select Webcam format and check **Wide ↔ Tight** with one tap each way. Confirm there is no third rung. Return to Stage for the following checks.
4. Select a visible candidate: **Detect → tap that person → Crop**. Record the candidate marker. With the person standing still, tap Push in and Pull out. The program size should change even if follow position is steady; the locked candidate remains the same. Walk the candidate toward a sensor edge and confirm the crop stays filled and keeps the chosen person in view. At a zoom limit, the pill should report it and the opposite button should respond promptly.
5. While tracking, cover or remove the candidate until recovery starts. Check that an active move stops, the status reports widening, and the program widens smoothly. Select **Manual** during recovery, then let the candidate reappear: automatic reacquisition must not take Manual away. Move the Manual center with one source-view tap and check the visible shot does not jump in size.
6. Select **Auto Pan**. Watch one ordinary sweep, both endpoint dwells, then tap Push in during a sweep and again during a dwell. Check pan continues at its selected rate, size changes smoothly, the endpoint stays at the visible edge during a dwell, and a full-width shot pauses travel without resetting direction. Pull out; check travel returns. Try Slow, Normal, and Fast without changing framing. While Pan is active, check diagnostics for stopped Vision work and confirm a late detection cannot switch the shot back to Crop. Select Crop explicitly to resume the same locked candidate, then Pan again; the sweep should retain its phase and direction.
7. During an active move, use a segmented preset, then start another move and use **Return to Wide**. Each action should cancel the earlier destination. Return to Wide should show the uncropped safety view, clear the subject lock, and permit a fresh Push in. Check focus loss and Stop also end an active move; restart capture before continuing.
8. Repeat the core sequence at every show rate the installation will use. Note any step, breathing, black edge, soft image, stale program frame, or delayed response with a timecode and the route where it occurred. Judge slow intentional travel separately from frame skips or input-to-program lag.

## Recovery controls (RECOVERY-UI)

The pill's lock control reads the composer state: **Pick subject**, **Acquiring…**, **Locked**, **Recovering** (10-second HOLD), **Searching** (wide, waiting for the subject), or **Resume**. See the recovery section of `docs/ALFIE_ENGINEERING_SPEC.md` for the rules.

1. Lock a subject (Detect → tap → Crop). The control reads **Locked**; tapping it unlocks.
2. Hide the subject. Within HOLD the control reads **Recovering** and the program keeps the last crop for 10 s, then widens and reads **Searching**. Let the subject return: tracking resumes without any tap.
3. Lock again, then choose **Manual** or **Auto Pan** (tracking loses ownership). The control should read **Resume** while the subject's face gallery is ready. Tap **Resume**: tracking takes over again, same subject, no jump to someone else.
4. Tap a subject and switch to Manual while the control still reads **Acquiring…** (before Locked). Resume must **not** be offered, because there is no ready subject evidence yet. Record what the control shows (expected **Acquiring…** or **Pick subject**) and that tapping it never re-locks without Detect.
5. **Return to Wide**, then look at the control: no Resume is offered (the lock and its gallery are cleared). Any Resume created before Wide must do nothing.
6. At 1280 points, confirm the longest label (Pick subject / Acquiring… / Resume) does not push any pill control off screen.

## Failure and physical-route checks

- For a render-error injection build, first establish a known program frame, then trigger a crop-render failure. The program pane and selected output should hold that same last successfully rendered frame; no raw wide source frame should leak through. On startup without a good frame, no invented program frame should appear. Record hold duration and recovery behavior. This requires an injection hook or debugger and is not reproduced by unplugging a camera.
- If using Program Display → HDMI/converter → ATEM, verify the *physical* ATEM input sees Alfie's crop and retains the expected resolution and frame rate. Verify ATEM Preview/Program independently, including a cut to that input. The ATEM control app alone is not a video transport test.
- If using a virtual-camera client, verify that client receives the same crop and rate. Record whether the route is a test client or the show's actual receiver.
- Do a 10-minute local run before a service and record dropped frames, output disconnects, and any mismatch between Alfie's program pane and the receiver. The longer 60-minute soak and multi-camera/physical-yaw work belong to later validation.

## Result

| Check | Pass/fail | Timecode and observed behavior | Program pane / receiver |
| --- | --- | --- | --- |
| 1280-point controls |  |  |  |
| Stage and Webcam rung taps and reversal |  |  |  |
| Stationary lock and edge/limit |  |  |  |
| Recovery and Manual authority |  |  |  |
| Pan sweep, dwells, zero travel |  |  |  |
| Preset, Return to Wide, focus, Stop cancellation |  |  |  |
| Recovery labels, Resume with / without a ready subject, post-Wide |  |  |  |
| Render-failure last-good frame |  |  |  |
| Physical output and show rate |  |  |  |
