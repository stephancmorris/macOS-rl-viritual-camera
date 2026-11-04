# Workload Inspector render check — 4 November 2026

The actual Inspector drawer was rendered over a 1280×800 pt Multiview console using in-memory running-channel fixtures, with no camera capture or output started. The PNGs are 2560×1600 pixels on the local Retina display (Xcode 27.1).

- [Policy disabled](inspector-workload-disabled-1280.png): manually inspected; the Show section goes straight from Router to Inputs, with no Workload row.
- [Policy enabled](inspector-workload-enabled-1280.png): manually inspected; Workload reads **Reducing optional UI**, with **Last change: CPU pressure, Program deadline misses**. Both lines fit within the 400 pt drawer. Three injected policy windows supplied CPU fraction 0.95 and Program deadline-miss fraction 0.05.

The row is a read-only projection inside the Inspector's existing 0.5 s TimelineView. A nil policy produces no workload detail. The initial enabled state is Normal without an invented reason; later windows retain the last transition's reasons until another transition, including recovery. VoiceOver receives the Workload label and the same level/last-change value. The compile-time developer flag stays off by default, including Release. Higher levels use advice wording because only optional UI refresh currently acts on the policy's runtime hints.

`InspectorWorkloadTests` covers all six levels, all nine reasons, disabled/initial states, transition/recovery copy, enabled single-input layout and both 1280 pt renders. Export the images with `TEST_RUNNER_ALFIE_GALLERY_SNAPSHOTS=1` on the normal bounded test command; files go to `FileManager.default.temporaryDirectory/AlfieMultiviewGallery` in the test host.

These synthetic software renders do not qualify a camera pair, rig, release, privacy review or Director authority.
