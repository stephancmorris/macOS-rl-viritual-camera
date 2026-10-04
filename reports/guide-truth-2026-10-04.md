# Operator guide consent and pair-history delta

4 October 2026. [GUIDE-TRUTH](https://trello.com/c/BdCAAOVw), parent [Operator guide](https://trello.com/c/qNmix3yK). Branch `codex/alfie-quality-sprint-2026-10-04`.

The guide still told operators that consent could not be removed during recording. Source fix `bb7e692bd422aa1f41bb0889b58568475e54c560` now permits that action, closes new-observation admission synchronously and drains accepted observations before writer close. Revised copy describes that boundary, preserved files, waiting for shutdown before renewed recording and deliberate deletion controls. The existing observation-versus-video description is retained; no anonymity or privacy-compliance claim is added.

Pair instructions now explain dated stored evidence and current format/profile/mode uncertainty, matching `1bcb3d6`. Unknown pairs can start an unmeasured trial and measure after Start. A short check does not qualify sustained load. This updates the two affected paragraphs only; the original workflow review remains tied to `7691e6e`.

Changed files: `README.md`, `docs/user-guide/README.md`, `docs/user-guide/index.html`, and this report. The HTML edition date and evidence references were updated. No app source, CSS, controls, output routes or release policy changed.

Verification: static HTML parser checked unique IDs, internal anchor targets and local asset/link existence; Markdown evidence links resolve; `git diff --check` passes. Source and prior exact test evidence are in [the quality sprint report](quality-sprint-2026-10-04.md): consent targeted 6 definitions/7 runs; setup targeted 96/102, both zero failures/skips. Their full runs passed 447/552 and 452/560 respectively, with 3 skips each. These are the original repair snapshots, not reruns for this copy edit.

The parent acceptance remains open: supplied candidate installation/permission walkthrough, 1280-point app rehearsal, screenshots and actual camera/receiving-output verification. Static copy checks do not establish those outcomes or privacy/release qualification.
