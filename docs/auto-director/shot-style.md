# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| T1 Sermon pace? | Fixed timer; bounded duration suggestions; event-only | Bounded suggestions with soft maximum; never manufacture a cut to satisfy time | AD-STYLE/PREFS | Yes, requalify |
| T2 Cuts into movement? | Allowed; settled only; motion-class whitelist | Settled only first; simplifies volunteer prediction and evaluation | AD-STYLE/PREPARE | Yes, requalify |
| T3 Scheduled Wide? | Mandatory interval; soft contextual reminder; none | Soft reminder, fixed safe-wide role; no cut forced by timer | AD-STYLE/ROLES | Yes |

Status: proposed, 2026-09-30. Every number in the parameter table is a **proposed starting value** for study, not a broadcast standard or approved setting.

## Practice and current implementation

Blackmagic describes preparing a source on Preview before using Cut, which supports Alfie's existing preview-first workflow ([ATEM Television Studio features](https://www.blackmagicdesign.com/products/atemtelevisionstudio/features), accessed 2026-09-30). This does not establish a sermon shot-duration rule. BBC R&D's [WHP402 multicamera production dataset](https://downloads.bbc.co.uk/rd/pubs/whp/whp-pdf-files/WHP402.pdf) (accessed 2026-09-30) is a relevant evaluation precedent, not church footage or permission to use its assets without checking terms. No authoritative universal minimum duration, Wide frequency or movement speed was verified; the values below are editorial hypotheses to test.

`ShotComposer.swift` / `Config.ShotPreset` provides Wide, Full Body, Waist Up; `CameraManager` and `CropEngine.swift` provide existing one-rung moves and interpolation. `ProgramTake.swift` allows technically ready moving shots in manual R2. Proposed director policy restricts its own choices; it does not rewrite those controls or substitute a new crop engine.

## Proposed DirectorShotPolicy parameter contract

All names are proposed adapters until matched to Sol's final types. Units must be explicit; log-scale speed is dimensionless per second; center speed uses normalized **source** coordinates. Existing engine/quality restrictions always win.

| Parameter | Proposed starting value | Rationale / how measured |
|---|---|---|
| minimumShotSeconds | 20 s | Reduce restless sermon cuts; compare reviewer distraction and missed moments |
| preferredShotSeconds | 45 s | First point to consider variation, not a timer trigger; measure useful-proposal rate |
| maximumShotSeconds | 90 s, soft | Prompt a check on static coverage; allow indefinite hold if no better eligible candidate |
| wideReminderSeconds | 120 s since last full-stage view | Context reminder; measure accept/ignore rate |
| wideMinimumSeconds | 8 s | Give context time to read; reviewer comprehension check |
| repeatHistoryCount | 2 committed shot descriptions | Penalize repeated equivalent framing, not A/B route alternation itself |
| minimumDistinctScaleRatio | 1.25 | Suppress near-identical size jump; compare rendered crop heights, also respect different genuine angles |
| maximumCenterSpeedPerSecond | 0.02 | Conservative settled-shot ceiling; crop-trajectory replay and visual review |
| maximumLogScaleSpeedPerSecond | 0.02 | Detect residual zoom; review source-rate-normalized trajectory |
| settledWindowSeconds | 0.75 s | Continuous stability before director readiness; evaluate latency vs false-ready |
| minimumFreshObservations | 3 | Require independent evidence within window; don't count repeats |
| observationMaxAgeSeconds | 0.15 s | Initial perception freshness hypothesis; measure at decision time |
| proposalIntentTTLSeconds | 5 s | Bound stale editorial intent; count expiry/reproposal churn |
| takeNoticeSeconds | 3 s, only later Auto Direct | Gives chance to cancel; timed volunteer trials |
| allowMovingShotTake | false | No cut during pan/zoom; ongoing plan vetoes a slow endpoint |
| allowDirectorLiveMoves | false | Off-air preparation first; existing Program tracking is not a new director move |
| forceWideOnTimer / forceCutAtMaximum | false / false | Soft editorial limits cannot override readiness or authority |
| faultSafeTakeEnabled | false | Matches fault revocation recommendation |

Precedence: safety/authority and R2 eligibility → subject/role/motion → minimum duration → repetition/pace preference. A qualified later emergency fallback, if ever approved, needs its own exception; no ordinary maximum-duration rule overrides minimum duration. Safe-wide dwell uses `wideMinimumSeconds` instead of ordinary minimum so returning to the speaker is not blocked unnecessarily. Manual cuts ignore director pace restrictions and pause direction.

Repetition key: physical-person nomination + shot size + camera viewpoint, not UUID alone or channel role. If only one valid shot exists, remain on it and show “No useful alternate”; do not oscillate just because minimum time expired. Program tracking follows existing engine constraints; a speed exceeding director entry threshold blocks a new cut, not the live stream.

Acceptance: freeze these candidates before replay; report cuts/hour, duration distribution, below-minimum count, Wide reminder acceptance, near-identical cut pairs, motion-on-entry count and reviewer-rated bad movement per rendered minute. Compare manual baseline, Suggest and Auto Prepare. Parameter sweep uses training split only; publish abstention and worst case as well as averages. Risk: fixed-frame movement limits are viewpoint dependent; named rigs and reviewer evidence determine qualified settings.
