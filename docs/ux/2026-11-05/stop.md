# Stop a session

S1 specification · 5 November 2026. Implements owner decision D3 without changing the retained menu shortcut.

## On-screen control

Visible resting label: **Stop session**. Help: **“Hold for 0.8 seconds to stop this session.”** Keep the normal arrow cursor. One uninterrupted press inside the control for **0.8 seconds** completes Stop, once. Fill the control progressively; use a visible **“Keep holding to stop”** label during the hold. No scale/bounce effect.

| State | Exact visible copy | Behaviour / accessible output |
| --- | --- | --- |
| Resting, live | Stop session | Press begins the hold. VoiceOver name “Stop session”; hint “Opens a confirmation before stopping.” |
| Short click or early release | Hold to stop | Keep the session running; clear progress to zero. Help remains until the next interaction or focus leaves. |
| Holding before 0.8 s | Keep holding to stop | Progress represents elapsed hold time; no partial Stop effects. |
| Pointer leaves, Escape, window loses focus, or gesture is cancelled | Hold to stop | Cancel and clear progress. Re-entry/re-press requires a fresh full hold. |
| Hold completes | Stopping session… | Invoke the existing session Stop once, disable duplicate Stop, announce “Stopping session.” |
| Stop completes | See stopped-screen copy below | Only claim output/camera off after the lifecycle confirms it. |
| Stop fails or remains unresolved with a reported error | Could not stop the session. Try again. | **Try stopping again** invokes the guarded Stop action; announce the error. Keep the actual live/output state visible and do not show a completed-session message. |

Increase Contrast makes progress/focus boundaries stronger; words carry the state. Reduce Motion uses a nonanimated progress value/fill update and the changing labels, without pulse, flash, sliding or easing. Progress indication must remain understandable without colour. A normal keyboard activation (Space/Return through Full Keyboard Access) uses the confirmation alternative below, so holding a key is not required. Do not make Space a new global Stop key.

## Accessible confirmation and menu

VoiceOver's standard Press action opens a confirmation; no custom timed accessibility gesture. Title **“Stop this session?”**; buttons **Keep running** and **Stop session**. Initial/default focus is Keep running; Escape keeps running. The explicit Stop action performs one Stop without an additional hold. Accessible button names equal their visible labels. Cancelling restores focus to Stop session and announces “Session kept running.”

Confirmation message and persistent Multi Cam header helper describe the **actual frozen active route**:

| Active route | Header helper | Confirmation message |
| --- | --- | --- |
| Direct, verified destination is ATEM | Stops Program output to the ATEM. | This stops the cameras and Program output to the ATEM. |
| Direct, destination named otherwise | Stops Program output to {destination}. | This stops the cameras and Program output to {destination}. |
| Direct, identity unknown | Stops Program on Direct output. | This stops the cameras and Direct Program output. |
| Virtual camera | Stops Program output to Alfie camera. | This stops the cameras and Program output to Alfie camera. |
| Rehearsal | Stops the rehearsal cameras. | This stops the rehearsal cameras. No external output is active. |

The helper is readable at 11 pt or more in `secondaryText`, not hidden only in help. The Multi Cam Stop stops the whole session, not just the selected input. Track B owns the header; Track A owns the pill Stop. Both use the same interaction contract.

**Session › Stop Session ⌘⌥⇧S remains the immediate explicit menu action**, with no timed hold or new confirmation. D3 specifically adds safeguards to the on-screen control. Publish it whenever the session is running, including when an input has failed; withdraw it after Stop. Sol's command publisher fix must verify this path remains reachable. TAKE still has no key.

## Stopped screen

Heading: **Alfie is standing by.** Mode line: **“{mode} · Session stopped”**, at least 11 pt, sentence case. Before any session: **“Alfie camera is off.”** After a completed virtual-camera session, for example:

**“Session ended 14:32 after 42 min. Alfie camera is off.”**

Use the actual end time in the user's local time format and elapsed duration, not time since stopping. Duration under a minute is **“less than a minute”**; then whole elapsed minutes, or **“1 hr 12 min”**. If start time is unavailable, omit the duration: **“Session ended 14:32. Alfie camera is off.”** Never fabricate it. Direct output ends **“Program output is off.”** Rehearsal ends **“Rehearsal cameras are off.”** When previews are explicitly enabled later, replace the off-state line with **“Camera previews are on. Program output is off.”**

VoiceOver announces the complete stopped sentence once. Focus moves to Start session unless readiness needs attention, then to its first blocker. The [Get ready](readiness.md) checklist reappears for regressed prerequisites. Stop always returns previews to off; restarting requires Start. Do not say “Virtual camera released” or suggest the system extension has been uninstalled.

Implementation evidence: click, release at 0.79 s, completion at 0.8 s, gesture cancellation/outside release, repeated input, route helpers, keyboard confirmation/default/cancel, VoiceOver action, immediate menu shortcut, reduced motion and all stopped lines. A real camera/ATEM/meeting-app check must establish what the receiver shows when the session stops; these specs do not promise receiver blackout or delivery behaviour.
