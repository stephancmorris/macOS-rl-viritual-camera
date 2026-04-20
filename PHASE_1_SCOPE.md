# Phase 1 Scope

This document locks the Phase 1 product scope for the church-stage MVP.

It turns the current broad idea into a buildable first version with clear assumptions, open questions, and a recommended technical direction.

## Goal

Build the first usable version of an autonomous church camera assistant that:

- receives a wide stage camera feed on a laptop
- detects and tracks the primary speaker
- produces a stable waist-up view
- forwards that processed view into the church switching workflow

## Confirmed Use Case

The intended workflow is:

1. A Blackmagic or Sony camera captures the full stage.
2. That camera feed is sent into a laptop running this application.
3. The application detects the primary speaker and tracks them.
4. The application generates a waist-up output view.
5. That processed view is sent to a Blackmagic Design ATEM switcher.
6. The ATEM then uses that processed feed as one of the available live production inputs.
7. The final switched production continues downstream to the Resi box.

Confirmed deployment details:

- ATEM model: `ATEM 1 M/E Constellation HD`
- Stage camera signal preference: `HDMI`
- Available converter: `Blackmagic Micro Converter BiDirectional SDI/HDMI`
- Downstream livestream path: `ATEM -> Resi encoder`
- Host machine options:
  - `MacBook Pro M3`
  - `MacBook Pro M4`
  - `Mac mini`

## Phase 1 Product Decisions

### Tracking scope

Phase 1 assumes:

- one active speaker at a time
- occasional second person on stage may appear
- the system should prefer the main target and ignore others when possible
- worship/multi-performer tracking is out of scope for MVP

### Framing rule

Phase 1 framing target is:

- always waist-up

No automatic shot-style switching is included in Phase 1.

### Manual fallback controls

Phase 1 will include only simple fallback controls:

- `Return to Wide`
- `Resume Tracking`

These are included to help the operator recover when tracking is wrong or temporarily unstable.

### Output flexibility

Long term, the product should support more than one output method.

However, for Phase 1 we should build around one primary output path first, then add flexibility later. Trying to solve NDI and physical output equally in MVP will slow the project down and increase risk.

## Recommended Phase 1 Output Strategy

### Recommendation

Use a physical Blackmagic output path as the primary MVP target.

Recommended priority:

1. HDMI camera into laptop via capture hardware
2. Processed laptop output back to ATEM as SDI
3. NDI as a later secondary option

### Why

- Your downstream destination is an `ATEM 1 M/E Constellation HD`.
- ATEM Constellation models are officially described by Blackmagic as SDI-based switchers with SDI inputs and outputs, plus USB webcam output on some models, according to Blackmagic's product and technical specification pages.
- The `ATEM 1 M/E Constellation HD` specifically provides `10 standards converted 3G-SDI inputs` and `6 independent 3G-SDI aux outputs` in the official Blackmagic specifications.
- I did not find official Blackmagic documentation describing native NDI input support for ATEM Constellation. That means NDI may still be possible in your workflow, but likely not as a direct built-in ATEM input path.
- A physical Blackmagic input/output path is more aligned with your actual broadcast chain and should be more predictable for a church MVP.

Sources:

- [ATEM Constellation product page](https://www.blackmagicdesign.com/products/atem/)
- [ATEM Constellation tech specs](https://www.blackmagicdesign.com/products/atemconstellation/techspecs/W-ABP-05)
- [UltraStudio Recorder 3G tech specs](https://www.blackmagicdesign.com/products/ultrastudio/techspecs/W-DLUS-12)
- [UltraStudio Monitor 3G tech specs](https://www.blackmagicdesign.com/developer/products/capture-and-playback/techspecs)

### Engineering consequence

For Phase 1, the system should be designed around:

- one HDMI capture path into the laptop
- one SDI output path from the laptop into the ATEM
- processed output delivered as a real switcher-ready video source

NDI should remain a planned future extension, not the first implementation target.

## Recommended Phase 1 Signal Path

The most practical MVP path for your environment is:

1. `Camera HDMI out`
2. `Laptop capture device`
3. `This application`
4. `Laptop playback/output device`
5. `HDMI or SDI out from laptop playback device`
6. `If needed, use Micro Converter BiDirectional SDI/HDMI`
7. `ATEM 1 M/E Constellation HD SDI input`
8. `ATEM program output`
9. `Resi encoder`

### Recommended target wiring

Preferred Phase 1 target:

- camera to laptop: `HDMI`
- laptop to ATEM: `SDI`

Why:

- this preserves your preferred camera connection style
- it matches the ATEM's native SDI input model
- it gives the cleanest long-term church deployment path

### Important clarification

The `Micro Converter BiDirectional SDI/HDMI` is useful for format conversion, but it is not a laptop capture interface by itself.

That means:

- camera `HDMI -> Micro Converter -> SDI` does not by itself get video into the laptop
- you still need a real laptop capture device
- you also likely need a real laptop playback/output device for sending the processed feed back out

## Hardware Reality Check

### Current gap

You noted that there are currently no capture cards.

That is a real blocker for Phase 1.

If the application is meant to:

- ingest a camera feed on a laptop
- process it
- then forward a processed feed to ATEM

then the laptop needs a real video input path, and likely also a real video output path.

### Minimum hardware requirement for Phase 1

At minimum, the Phase 1 deployment needs:

- one camera feed into the laptop
- one processed feed out of the laptop

For a laptop-centered Blackmagic workflow, that usually means:

- a capture device for ingest
- a playback/output device for sending the processed feed onward

### Practical Blackmagic-aligned examples

Examples from official Blackmagic product pages:

- `UltraStudio Recorder 3G`
  - laptop input via Thunderbolt 3
  - accepts HDMI and SDI input
- `UltraStudio Monitor 3G`
  - laptop output via Thunderbolt 3
  - provides HDMI and SDI output

These are examples, not a final purchasing decision.

### Best-fit Phase 1 hardware pattern for your setup

Given your stated preferences and existing hardware, the cleanest pattern is:

- ingest: `camera HDMI -> UltraStudio Recorder 3G -> laptop`
- egress: `laptop -> UltraStudio Monitor 3G ->`
  - either direct `SDI -> ATEM`
  - or `HDMI -> Micro Converter -> SDI -> ATEM`

This is a recommendation based on the current official Blackmagic specs and the equipment you described.

## Open Questions

These do not block software planning, but they do affect the final deployment path.

### Open Question 1: Final host machine selection

Known options:

- `MacBook Pro M3`
- `MacBook Pro M4`
- `Mac mini`

Still to decide:

- which one will be the primary deployment target
- how many Thunderbolt-capable ports will be reserved for video I/O and accessories

Why it matters:

- the Blackmagic host I/O path depends heavily on Thunderbolt-class connectivity

## Scope Boundaries For Phase 1

Included:

- single-stage, single-primary-speaker tracking
- waist-up framing
- processed output generation
- forwarding processed output into the switching chain
- ATEM-compatible output planning for `ATEM 1 M/E Constellation HD`
- basic recovery controls: `Return to Wide` and `Resume Tracking`

Not included:

- worship-team tracking
- autonomous multi-person switching
- advanced cinematic shot variation
- RL as a required runtime dependency
- multiple output modes implemented at once

## Phase 1 Success Criteria

Phase 1 is successful when:

- a stage camera feed enters the laptop reliably
- the application identifies and follows the primary speaker
- the output remains a stable waist-up framing
- the processed view is sent out of the laptop as a real downstream feed
- the `ATEM 1 M/E Constellation HD` can use that processed feed as an input option
- the operator can recover using `Return to Wide` and `Resume Tracking`

## Recommended Immediate Work Order

1. Freeze Blackmagic physical output as the primary MVP delivery path.
2. Freeze camera ingest preference as `HDMI into laptop`.
3. Freeze ATEM delivery preference as `SDI into ATEM`.
4. Pick the primary host machine and confirm the final port layout.
5. Finish the software so the processed crop, not the raw input, becomes the real output feed.
6. Build the simplest stage-aware single-speaker waist-up tracker before investing further in RL behavior.

## What I Still Need From You

Phase 1 is mostly defined now.

The main remaining detail I would still want, when you have it, is:

- which of the available Apple Silicon Macs will be the primary deployment target

That matters mostly for confirming the final Thunderbolt-based I/O layout, but it does not prevent us from moving forward with software work right now.
