# Astra UX programme results

Updated 6 November 2026. Programme in progress; this is not final acceptance or rig sign-off.

## Assignment and isolation

The owner's 6 November assignment supersedes the original docs-only handoff. Claude completed Wave 1 (UX-F2/F3/F4) while Sol was out of usage. Sol owns UX-KEYS, UX-M3 and Track B. Astra owns Track C, then Track A unless Sol has claimed it first. Astra reviews Sol's tagged foundations, observer and Track B PRs; Sol reviews Astra's journey PRs. Claude reviews main at the end.

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

Wave 1 is merged and the Track C gates are open. Reviewed isolated heads #117 `23a9c21f8c3579fea47aa14588bf2e0b56ab1828`, #118 `b54b6a56b74caa74a2a7d9024300d15efb18304c` and #119 `c17e40b6e1f98ebc739ce7da3ad59c9cb0e27702`, built each and regenerated State/Multiview galleries into scratch directories. Focused serial review suites passed 16, 34 and 36 tests respectively (zero failures); these are not full-suite totals. Compared light/Navy night, button states and all four display-setting overrides.

- [#117 review](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/117#issuecomment-6673289478): Follow-up for native system pickers within the forced-dark console on a light Mac; attended check.
- [#118 review](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/118#issuecomment-6673289918): Follow-up for persistent disabled reasons in journey consumers; actual cursor, focus, hold cancellation and keyboard/VoiceOver confirmation require interaction checks.
- [#119 review](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/119#issuecomment-6673290263): Follow-up for actual system accessibility settings and high-contrast dynamic colours. Static overrides do not prove system observation.

No Blocking findings in those three reviews. UX-KEYS #120 head `1e3fcf978f093476fe4bb3bfb5f4bed2048e9e85`: build passed; 26 command/menu tests and 22 router/gallery tests passed serially. All 31 regenerated PNGs are byte-identical to #119. No Blocking findings; native keyboard layouts, focus, text composition and VoiceOver remain interaction checks. Track C J1 adds readiness, explicit preview-only capture and route-aware stopped copy. J1 integrated validation at `4c88136`: 1,284 total, 1,280 passed, four opt-in skips, no failures; serial and limited to 1,800 seconds. Fifty J1 captures cover light/Navy night and display overrides. Sol's [J1 review](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/122#issuecomment-6674030236) found two blockers: the actual Webcam Start route and background readiness focus. J1 now applies the virtual route before dispatch and returns focus only from a disappearing focused checklist; tests cover saved Direct/Rehearsal and focus leaving the checklist. Removed the temporary Multi Cam wrapper for Sol's J6-owned placement. Added an injected preview worker and delayed-completion/duplicate/unauthorized/no-selection tests. Revised full serial suite: 1,288 total, 1,284 passed, four opt-in skips, zero failures (`/private/tmp/alfie-j1-review-fixes-full.xcresult`).

[#121 review](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/121#issuecomment-6674062023): head `3db8646`, build and 15 observer/gallery tests passed; 31 captures match #119. No Blocking finding. Stream-signal rig checks remain; J5 must stop monitoring on disappearance and announce transitions only.

Track A still waits for merged Track C and the claim check.

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
