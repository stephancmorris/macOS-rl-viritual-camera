# Stage 3 Auto Director: hybrid AI options

Prepared 10 Oct 2026 as a companion to [STAGE3-DESIGN-PLAN.md](STAGE3-DESIGN-PLAN.md). This is exploration only. Nothing has been built, and no API was called or tested. **Every recommendation here is AWAITING OWNER.**

The question: should the Auto Director be a hybrid, using lightweight AI models alongside its rules, and in particular decision models such as TypeSafe's **Jev** or OpenAI's **Decisions API**?

---

## 1. Short answer

Yes, a hybrid is the right direction, as long as **the rules keep authority and the AI only ranks and judges inside them.** Authority, staleness checks, "Preview only" and "never Take" must stay deterministic, testable code. AI earns its place where the rules are weakest: **which shot fits this moment, and whether now is a good moment.** Those are matters of taste, and rules can't capture taste well.

**Jev and the Decisions API cannot be "baked into" Alfie.** Both are hosted services with no downloadable weights. Using either means Alfie needs a network connection during a service and a new sandbox permission, and the chosen data leaves the Mac. The options that genuinely live inside Alfie are:
- a small learned model running on the Mac through CoreML;
- Apple's on-device Foundation Models;
- a small local vision-language model (later).

**Recommended hybrid for Stage 3:**
1. **Local learned shot scorer (CoreML)**, trained from the operator's real choices recorded in shadow mode. This is the main AI decision-maker. It reuses the existing `training/` pipeline (BC/PPO → `export_coreml.py`) and the `CinematicAgent` CoreML loader.
2. **Apple Foundation Models (on the Mac)** turns plain-language preferences into structured Director settings ("calmer, more wides in prayer") and writes the operator-facing explanations. It never makes a camera decision.
3. **OpenAI Decisions API, offline only:** an image-aware judge that scores *recorded, consented* footage during evaluation (E-2). It labels data and checks quality. It is never in the live loop for Stage 3.
4. **Jev:** don't adopt it for Stage 3. Revisit if it gains image input and a local or private deployment option.

---

## 2. What was looked up

| | **Jev** (TypeSafe AI) | **OpenAI Decisions API** |
|---|---|---|
| What it is | A "System One" decision model: state + typed questions → structured answers in one parallel pass, with no text generation | `POST /v1/decisions`: predefined questions → one chosen answer each. Runs on `gpt-6-luna` |
| Question types | **Choice** (1–255 options, label + confidence + probabilities), **Score** (2–10 level rubric), **Noul** (yes/no probability) | **choice** (choice, confidence, probabilities), **score** (ordered levels), **predicate** (yes/no probability); may return a **refusal** |
| Inputs | Text/JSON state only. No images reported | Text and **images** (inline base64 only) |
| Latency (vendor-reported) | 70–500 ms; 0.114 s in one vendor benchmark | "About 10× faster than Responses"; no absolute figure published |
| Price (reported) | ~$0.042 per 1M input tokens; output free | $0.10 per 1M input tokens; output free |
| Deployment | **Hosted only**; no weights, no on-prem. TypeSafe API behind a waitlist; Eden AI resells an **alpha** endpoint | **Hosted only**; public beta since 6 Oct 2026, GA "within weeks". Zero data retention and US/EU residency for eligible customers |
| Known limits | ~68% on the vendor's own four-workflow benchmark; "can still be confidently wrong"; no data-residency guarantee | Beta; rate limits and choice limits unconfirmed |
| Released | 15 Sep 2026 | Announced DevDay 29 Sep 2026; beta 6 Oct 2026 |

Source quality: both products are only weeks old, and most coverage is secondary (blogs and resellers). Treat the figures as indicative until checked against the vendors' docs or a test call.

What both get right, and what Alfie should copy whatever is chosen: **a fixed answer space, calibrated probabilities and an explicit way to decline.** These map directly onto the Director's existing design. A candidate list becomes a choice question, and a low top probability becomes an **abstention**, alongside the existing `noEligibleCandidate`, `movement` and other reasons.

---

## 3. Where AI could enter the Director

| # | Decision point | Today | Could AI help? |
|---|---|---|---|
| D1 | **Which shot to prepare** (Wide / Full Body / Waist Up on Preview) | Fixed sort: wide cadence → confidence → preset order (`DirectorShotPolicy.swift`) | **Yes, the strongest case.** Taste and timing are what an operator brings |
| D2 | **Is this a good moment** (eyes open, facing camera, not mid-stride, not reading notes) | Lock phase + settled + speed under a threshold | **Yes, but only with vision.** Text-only models see the same numbers the rules do |
| D3 | **Explaining** to the volunteer | Fixed reason strings | Yes. Low risk |
| D4 | **Authoring preferences** from plain language | Numbers in `DirectorPreferences` | Yes. Matches register V2's "LLM drafts, human reviews" |
| D5 | **Qualification and labelling** of recorded footage | Manual annotation | Yes, offline. No live risk |
| — | Authority, Pause, staleness, Preview-only, never-Take | Deterministic state machine | **No.** Must stay rules: safety, auditability and deterministic tests |

---

## 4. Options compared

**Confidence** below means: confidence that the option *measurably improves Stage 3* (fewer manual framing actions, fewer bad preparations, better operator agreement) within the Stage 3 timeframe, without weakening the safety envelope.

### Option A: Local learned shot scorer (CoreML), trained from shadow mode

A small model (gradient-boosted trees or a tiny MLP) scores each candidate shot. Its inputs are derived features only: lock phase, speed, settled time, time on Program, time since last wide, current presets on Program and Preview, and history. It learns from what the volunteer actually did during shadow-mode services.

| Pros | Cons |
|---|---|
| Fully local: no network, no new entitlement, works offline in any church | Needs data. Several services of shadow logs before it beats the rules |
| Fast (sub-millisecond) and deterministic, so it replays exactly in tests | Learns one operator's habits, including bad ones. Needs a held-out check against a second operator |
| Learns *this* church's taste rather than generic rules | Features only. It can't see that the pastor's eyes are closed (that's D2) |
| Outputs probabilities, so abstention is calibratable | A new training and release step per model version |
| Reuses the existing pipeline (`training/`, `export_coreml.py`, `CinematicAgent` loader, `TrainingDataRecorder` pattern) | |
| No media kept: features are metadata, which fits C3 | |

**Confidence: Medium–High** for D1 once data exists. **Low** before data, so the rules stay the default until it beats them.

### Option B: Apple Foundation Models (on-device LLM)

Apple's on-device model, with guided generation (`@Generable` Swift types). The output is type-checked against the type, so it can only produce a valid `DirectorPreferences` or explanation.

| Pros | Cons |
|---|---|
| On the Mac, private, free, no network | Needs Apple Intelligence enabled; the model may be absent or still downloading |
| Typed output fits the code style directly | ~4K context on device; no calibrated probabilities |
| Strong for language tasks: preferences (D4) and explanations (D3) | Weak at numeric judgement and not deterministic, so unsuitable for D1 |
| | Image input is reported for the newer framework (v3 / OS 27). **Unverified for macOS 26**, which is what the rig runs (26.6.2) |

**Confidence: High** for D3/D4. **Low** for D1/D2.

### Option C: OpenAI Decisions API

| Pros | Cons |
|---|---|
| **Takes images**, so it can judge D2 ("Is the subject facing camera with eyes open?" as a predicate; shot quality as a score) | **Congregation images, possibly including children, leave the building.** Needs a new privacy decision at least as strict as E2/E3, and consent |
| Calibrated probabilities and refusals, which map onto abstention | Needs `com.apple.security.network.client` (the app has **no network entitlement today**) and a reliable church network mid-service |
| Low cost: likely cents per service for text, more with images (estimate, unverified) | Public beta; one supported model; rate limits unknown; vendor dependency for a live show |
| Ideal as an **offline judge** on recorded consented clips (D5): labels E-2 footage and scores shot quality at scale | Latency unpublished. Fine for once-per-Take preparation, never for the frame path |
| | Zero data retention only for "eligible" customers |

**Confidence: Medium** as an offline evaluator and labeller (D5); it would speed up qualification. **Low–Medium** live (D2) in Stage 3, because of privacy, network and beta status. Revisit for Stage 3b.

### Option D: Jev (TypeSafe)

| Pros | Cons |
|---|---|
| Fast (vendor: 70–500 ms), cheap, built exactly for typed choices with probabilities | **Text only.** It sees the same derived numbers the rules see, so it adds little that a local learned scorer (A) can't do offline |
| "Smart if-statement" shape fits D1 cleanly | Hosted only, waitlist or alpha reseller, no data-residency guarantee |
| | ~68% on the vendor's own benchmark; "confidently wrong" warning |
| | The same network entitlement and live-dependency cost as C, for less capability |

**Confidence: Low** for Stage 3.

### Option E: Small local vision-language model (MLX or CoreML), research spike

| Pros | Cons |
|---|---|
| Local and private, and could answer D2 visually | Competes with two 50 Hz camera pipelines, Vision and Metal crop for GPU and memory, which is a real admission risk (C1/C2) |
| No cloud, so the privacy story stays simple | Latency of roughly 0.5–2 s and accuracy on church footage are unknown; would need its own workload fingerprint |

**Confidence: Low** for Stage 3; **Medium** as a Stage 3b spike after the learned scorer exists.

### Summary

| Option | Local? | D1 shot choice | D2 good moment | D3/D4 language | D5 evaluation | Stage 3 confidence |
|---|---|---|---|---|---|---|
| A. Learned scorer | ✅ | ●●● | ● | — | ● | **Medium–High** (after data) |
| B. Foundation Models | ✅ | ● | ?¹ | ●●● | ● | **High** for D3/D4 only |
| C. OpenAI Decisions | ❌ | ●● | ●●● | ● | ●●● | **Medium** offline / Low live |
| D. Jev | ❌ | ●● | — | — | ● | **Low** |
| E. Local VLM | ✅ | ● | ●● | ● | ●● | **Low** (3b spike) |

¹ Depends on unverified image support on the rig's macOS.

---

## 5. Recommended hybrid architecture

```
 evidence (rules)   ─►  candidates  ─►  DirectorJudge (AI or rules)  ─►  ranked + probabilities
                                                │                               │
                                       RuleJudge = today's sort         max p < τ → abstain (new reason)
                                       LearnedJudge = CoreML            │
                                                                        ▼
                    DirectorAuthority + Proposal validator + atomic sink (unchanged, deterministic)
```

**Principle: AI proposes, rules dispose.** A judge can only reorder or veto candidates that the rules already allow. It can never create a shot, target Program, extend a lease or skip a check.

### Implementation implications

| Area | What it means |
|---|---|
| **New seam** | `protocol DirectorJudge { func judge(_ context: JudgeContext, candidates: [Candidate]) -> Judgement }`, where `Judgement` is `.ranked([(Candidate, p)])` or `.abstain(reason)`. `RuleJudge` wraps today's sort, which becomes the baseline and the fallback. Lands in Phase 1 of the plan: pure, with no behaviour change |
| **Binding and staleness** | Each judgement carries the evidence revision and timestamp it was computed from. The proposal validator rejects any judgement older than its maximum age, or from an older revision. This is the same mechanism proposals already use. Slow or async judges (B, C, E) can't act on a scene that has changed |
| **Fallback** | Timeout, error, model missing or network down all fall back to `RuleJudge` and show "rules only" in the panel. AI is never required for safety or for the show to run |
| **Determinism in tests** | Record every judgement in the `[DIRECTOR]` log, and give replay a `RecordedJudge`. The synthetic fixtures still prove 0 stale commits and 0 Director cuts with any judge plugged in |
| **Data for Option A** | Shadow mode (Phase 3) logs features plus the operator's actual choice at each Take. Metadata only; no frames. Needs C3 (log retention) and a new decision on whether those logs may train a model |
| **Training** | Add a `train_director_scorer.py` beside `train_bc.py`, export to CoreML, and ship the model in the app bundle (versioned, as `CinematicAgent` loads its model). Report a held-out agreement score and calibration before any model becomes the default |
| **Rollout** | Shadow A/B: log the rules' pick and the model's pick side by side for several services. Promote the model only if agreement with the operator and the bad-preparation rate both beat the rules |
| **Foundation Models (B)** | Settings screen: "Describe your style" → draft `DirectorPreferences` → operator reviews and saves, which emits `.policyChanged` as planned. Explanations are generated from the judgement and the abstention reason. Both are optional and disappear cleanly when the model is unavailable |
| **Cloud (C, D), if ever** | Add `com.apple.security.network.client`; a privacy notice; per-show opt-in; no frames unless a separate decision allows them; zero data retention where available; a hard timeout. Today's offline guarantee becomes "offline unless enabled" |
| **Offline judge (C for D5)** | A Python script in `training/` sends consented E-2 frames to the Decisions API to label "good moment" and "shot quality". It runs on the developer's machine, never in the app, so Alfie needs no entitlement change |
| **Workload** | B and E run on the same Mac as two camera pipelines and must be measured through `[SOAK]` and the admission fingerprint before live use. A is negligible |

### Changes to the phased plan

| Plan phase | Addition |
|---|---|
| 1. Reconcile types | Add the `DirectorJudge` seam and `RuleJudge`, plus a "low-confidence" abstention reason |
| 3. Shadow mode | Log features and operator choices as training data. Optionally run the learned judge in shadow once one exists |
| 5. Operator controls | Optional Foundation Models preference drafting and explanations |
| 6. Evaluation | Offline Decisions-API labelling of consented clips; rules-vs-model A/B report |
| Stage 3b | Learned judge as default (if it wins the A/B); local VLM spike for D2; reconsider a live cloud judge |

---

## 6. New decisions (AWAITING OWNER)

| ID | Question | Options | Recommendation |
|---|---|---|---|
| **AI-1** | What may AI decide? | (a) Nothing. (b) Ranking within rule-allowed shots, plus abstention. (c) Also veto readiness (D2) | **(b)** for Stage 3; (c) only once a vision judge is qualified |
| **AI-2** | May Alfie use the network during a show? | (a) Never. (b) Opt-in per show, with offline fallback | **(a) for Stage 3.** Keeps the church-friendly "nothing leaves this Mac" promise |
| **AI-3** | What data may leave the Mac (offline evaluation included)? | (a) None. (b) Derived numbers. (c) Consented frames for offline labelling | **(c) for offline evaluation only**, under E3 consent; (a) for the live app |
| **AI-4** | May shadow-mode metadata train a model? | Yes / No; retention period | **Yes**, metadata only, with the C3 30-day retention unless the operator exports a dataset |
| **AI-5** | Cloud vendor for any future live judge | None / Jev / OpenAI Decisions | **None now.** Re-evaluate in Stage 3b; OpenAI Decisions if image judging is needed |

---

## Sources

- Jev: [Eden AI overview](https://www.edenai.co/post/jev-a-new-kind-of-ai-model-built-for-decisions-not-conversation); [MindStudio demos review](https://www.mindstudio.ai/blog/jev-real-time-game-demos); [Sam Witteveen agent-harness notes](https://ai-tldr.dev/releases/sam-witteveen-jev-agent-harness-sep29/); [critical review](https://www.ai.joaoqueiros.com/blog/fake-jev-demos-decision-model-agent-native-real-use-cases)
- OpenAI Decisions API: [OpenAI Developer Community announcement](https://community.openai.com/t/decisions-api-is-now-available-in-public-beta/1403877); [Unite.ai](https://www.unite.ai/openai-releases-decisions-api-in-public-beta-powered-by-gpt-6-luna/); [SmartScope comparison](https://smartscope.blog/en/blog/openai-decisions-api-use-pricing-public-beta-october-2026/); [eesel.ai explainer](https://www.eesel.ai/blog/openai-decisions-api)
- Apple Foundation Models: [WWDC25 session 360](https://developer.apple.com/videos/play/wwdc2025/360); [v3 summary (unverified)](https://ecorpit.com/apple-foundation-models-v3-afm-api-swift-developers/)
- Repo facts checked: `CinematicCoreMacOS.entitlements` (sandboxed; camera, app group and IOSurface only, no network); `training/` (`train_bc.py`, `train_ppo.py`, `export_coreml.py`); `CinematicAgent.swift` (CoreML loading)
