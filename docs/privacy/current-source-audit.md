# Current-source privacy audit

2 October 2026. Base `7691e6e1046ab40bca9b4e27a80e0b500f409c83`. Source audit only; no camera permission was changed, no live people/frames were captured, no existing user files were read/deleted, and no diagnostic export was transmitted. [PRIVACY](https://trello.com/c/ecKr4f2R) remains open. This is a behavior inventory, not a compliance approval.

## Data inventory

| Data / owner | Persistence and content | Cleanup / consent boundary |
| --- | --- | --- |
| CameraManager capture, crop buffers, ProgramRouter/output | In-process frames; IOSurface/XPC handoff to local extension; selected Program sent to display or receiving camera client. No video-file writer found in these frame paths. | Stop/source invalidation clear/retire session work; downstream clients and physical receiver are separate owners. This is not a proof that every pixel buffer is freed immediately. |
| ShotComposer identity acquisition / FaceSignatureGallery | Vision face feature-print observations and identity evidence in process; gallery used for reacquisition. No serialization path found for gallery prints. | `reset(clearManualLock: true)` invalidates identity work and sets lock inactive; CameraManager Stop/rebind uses it. Ordinary `reset()` can retain the lock/gallery intentionally. No zeroization or external-client deletion guarantee. |
| TrainingDataRecorder | App Documents/CinematicCore/TrainingData/session_*/frames.jsonl and metadata.json; person bounding box/confidence, derived depth proxy, pose coordinates, crops/labels, timing and camera/configuration metadata. Writer stores observations, not raw images or face feature prints. | Start requires persisted operator consent. Defaults retention 30 days, configurable 1–365 in UI; cleanup runs on recording Start or explicit Delete Expired Sessions, not continuously. Explicit Delete Completed Sessions is separate. Old sessions can therefore remain beyond 30 calendar days. |
| DiagnosticsLog | App Documents/CinematicCore/Diagnostics: soak CSV, memory CSV, session JSON. Metrics, timing, thermal/CPU/memory, build/machine/OS, camera/mode/route and free-text notes/errors. Automatic from first processed capture frame; no separate diagnostics consent control found. | CSV-only modification-date pruning at next session begin, older than 30 days. JSON manifests are excluded. Stop flushes/closes; does not delete. No approved imagery redaction/export packager found. |
| AlfieDiagnosticsLog | App Library/Logs/Alfie/alfie-diagnostics.log; append-only extension/XPC/routing text, identifiers/errors/timestamps. Also OSLog messages, including public device names and error strings. | No text-file rotation/retention found; unified-log retention is OS-owned. Inspector Reveal logs opens this folder, not the CSV/JSON folder. |
| UserDefaults | Saved devices/proposals, composition settings, route/show standard, training consent, admission records. Admission fingerprint includes camera/model/mode/format/host context. | Persistence survives Stop. Not a saved Director grant. No general erase-data control found. |
| Offline readiness study (separate unmerged candidate) | Operator-supplied consented clips/annotations; CSV stores clip filenames and metrics, no frames or prints. | Input consent/retention is supplied by the study owner; runtime deletion not performed. Empty annotations now reject in isolated repair; no dataset has been evaluated. |

Paths are resolved with FileManager's app-domain Documents/Library in the sandbox, rather than assuming ordinary user Documents. Entitlements enable sandbox, camera, app group, IOSurface and extension installation; no microphone or network entitlement was found in the reviewed app entitlement file. Searches of app Swift for URLSession/NWConnection/upload found no active upload path. This source result does not prove zero OS traffic, external receiving-client behavior or all linked-library behavior.

## Concrete gaps

1. Diagnostics CSV retention excludes session JSON manifests; text log has no rotation. Disclosure cannot promise all diagnostics expire in 30 days. Agree retention requirements, then implement/test each file family together.
2. Training consent UI is disabled while recording. Current workflow is Stop recording, then revoke. The public model property can change without stopping recording, and `recordFrame` checks only `isRecording`; future revoke paths require a final-write boundary. This is a model/UX gap, not evidence that the current disabled toggle can be clicked.
3. File sharing is manual Finder access, with no dedicated sanitizing export. Camera names, device IDs, paths, timestamps and errors can be identifying; a CSV without imagery is still not anonymous.
4. Current engine has no tracked PrivacyInfo.xcprivacy. The older Sol candidate contains one; review required-reason declarations and built-bundle packaging against the chosen release. No legal/Store approval is inferred here.
5. Permission refusal/revocation, fresh-install persistence, gallery/buffer lifecycle and export contents need runtime verification on an approved candidate. Source-only checks do not satisfy those acceptance items. Safe synthetic PrivacyAuditTests passed no-consent Start refusal and an allowlisted observation/speaker/pose JSON schema check. These test the guard/schema, not a full exported session or live cleanup.

## Verification plan (pending runtime evidence)

Use a disposable app-data fixture/new test account, candidate fingerprints and synthetic/consented input. Never run deletion controls on the operator's retained data as part of an audit. Record pre/post inventories (relative filename, type, size, modification date; no private file contents in public report).

- Deny camera permission: Start should explain refusal, with no fabricated source/Program. Approve/revoke through macOS only under an explicitly authorized permission test; record restart/recovery behavior.
- Start without training consent: no session writer/files. Consent and start a synthetic recording: inspect JSONL schema for observation fields, confirm no image/base64/frame-print payload; Stop and wait for queued writes before inventory.
- Stop, revoke, attempt restart: reject. Design/qualify a future mid-recording revoke event before wiring it.
- Place old/new CSV, JSON and text fixtures in isolated storage; verify deletion policy independently for each family. Current private DiagnosticsFileWriter cannot be injected with a root through public DiagnosticsLog; add a test seam before exercising its real directory in an automated test.
- Stop/rebind/identity reset: inspect late-work rejection and gallery ownership, avoiding claims of memory zeroization.
- Review manual export for build/device/path/note fields; approve recipient and data before sharing. Check manifest contents and privacy declarations in the actual built app and extension.

No existing private logs were uploaded, and no network or Store policy claim was approved. Remaining policy/retention choices belong to the product owner.

## 4 October 2026 consent repair

The consent finding above described the reviewed 2 October base. [Quality sprint evidence](../../reports/quality-sprint-2026-10-04.md) records the subsequent serialized Stop/revoke admission boundary, editable consent binding, temporary writer tests and actual persisted JSONL schema. Already accepted observations drain without deletion; restart requires consent and completed shutdown. This narrow source/test repair does not close the remaining permission, retention, export, disclosure or Store acceptance items.
