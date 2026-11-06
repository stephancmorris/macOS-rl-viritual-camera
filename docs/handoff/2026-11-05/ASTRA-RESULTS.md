# Astra UX programme results

Updated 6 November 2026. Programme in progress; this is not final acceptance or rig sign-off.

## Assignment and isolation

The owner's 6 November assignment supersedes the original docs-only handoff. Sol owns Wave 1 (UX-F2/F3/F4), UX-KEYS, UX-M3 and Track B. Astra owns Track C, then Track A unless Sol has claimed it first. Astra reviews Sol's tagged foundations, observer and Track B PRs; Sol reviews Astra's journey PRs. Claude reviews main at the end.

The owner's checkout was not edited. S1 uses an independent clone at `/private/tmp/alfie-astra-source-20261105` and worktree `/private/tmp/alfie-ux-astra-20261105`, branch `astra/ux-s1-specs`, with its own DerivedData. New implementation branches will use separate worktrees and DerivedData.

## PRs and validation

| Tag | PR | Merge commit | Local tests | Hosted CI |
| --- | --- | --- | --- | --- |
| UX-S1 | [#115](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/115) | `2c993f3ea7d6ede837cfb584447101e3ff409e66` | 1,237 total: 1,233 passed, 4 opt-in skips, 0 failures | [Final-head run](https://github.com/stephancmorris/macOS-rl-viritual-camera/actions/runs/42093549604): passed, Xcode 26.2; 1,233 passed / 4 skipped / 0 failed; 127 + 16 Python tests; unsigned Release and consistency passed |

S1 documents readiness, all ten camera errors, Inspector organisation, all 19 commands, Stop, Webcam and D1–D6. It also records the 6 November ownership update and the clarified Webcam first-use timing (after the first successful Start).

Unsigned Xcode 27.1 build-for-testing passed. The first sandboxed build could not access the installed Metal toolchain; the build outside the sandbox succeeded without product changes. The initial parallel unit run timed out in `DirectorSubjectDiscoveryIntegrationTests.cancellingDiscoveryWaiterPreservesRenderWaiterAndRunningPermits` (1,184 reported tests, 1,179 passed, 1 failed, 4 skipped; interrupted total). A narrow isolated-filter attempt ran zero tests and is not counted as a pass. The subsequent full run, with `-parallel-testing-enabled NO` and the required 1,800-second alarm, passed all 1,233 runnable tests, including the previously failing test. No UI-test suite was run.

Local evidence: `/private/tmp/alfie-astra-full-20261106.xcresult`; initial failure: `/private/tmp/alfie-astra-unit-20261105.xcresult`. DerivedData and logs are not committed. `git diff --check`, local Markdown-link audit, 19/19 command coverage and 10/10 CameraError coverage passed.

## Assigned keys

Detect **D**; Wide **W**; Full Body **F**; Waist Up **U**; Push In **]**; Pull Out **[** — all bare characters, with responder-aware typing protection. Bare **1–4** cue Preview only. Escape requires typing/composition protection on its separate path. TAKE has no shortcut. Existing Stop **⌘⌥⇧S**, Director hand **⌘⇧H**, Advance **⌘⇧Return**, modes **⌘1/2/3** and Inspector **⌥⌘I** remain. Sol's UX-KEYS owns installation; S1 edits no command source.

## Reviews and implementation gates

No UX-KEYS, UX-F2, UX-F3, UX-F4, UX-M3 or UX-TB review PR was available at the latest title-based check on 6 November, after merging S1. UX-F3 and UX-F4 are not merged, and no tagged foundation PR is open yet. No findings or approvals are claimed. Review actual PR heads in isolated worktrees, regenerate their galleries into scratch folders, and label each finding Blocking or Follow-up. Record the head, settings and final resolution here.

Track C new-file preparation waits for merged UX-F3; changes to existing views wait for merged UX-F4. Track A waits for merged Track C and the UX-TA claim check. No Track C or Track A code has been written yet. These are gates, not a docs-only handoff to Opus.

The requested persistent 15-minute continuation was rejected by automatic approval review because its recurring edit/push/merge authority was not explicitly approved as an automation. No automation was created. Use the owner's permitted gate-stop/“continue” workflow; do not mistake this closed gate for completion or a docs-only assignment.

## Appended roles or variants

None in S1.

## Unverified and attended checks

No static capture or software suite certifies the cursor, real keyboard traversal, VoiceOver delivery, receiver picture, clean-Mac permissions, extension approval, camera lights, device disconnect/reconnect or meeting-app stream use. Journey PRs must add their own captures and synthetic tests, then leave an explicit attended checklist.

The owner's final rig pass must include first launch on a clean Mac; allow/deny/revoke camera access; install/approve the extension; Direct-to-ATEM with no extension installed; explicit preview on/off and camera lights; unplug/reconnect while live; stopped/live fault recovery; hold/cancel/keyboard/VoiceOver Stop; Inspector traversal; Settings search/reset confirmation; and Webcam selection in Zoom, Meet and FaceTime, multiple consumers, release/crash and extension restart. Receiver output after Stop must be observed, not inferred.

## Owner questions

None currently. D1–D6 remain decided.

## Ready for Claude's review

Not yet. Main at the S1 milestone is `2c993f3ea7d6ede837cfb584447101e3ff409e66` (before this results-only commit). This section will contain the final main SHA, completed PR/CI/review trail, remaining attended checks and justified deferrals when both implementation tracks finish.
