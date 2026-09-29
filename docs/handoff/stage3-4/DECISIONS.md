# Decisions for Stephan

All decisions below are **OPEN**. Recommendations are proposals, not approvals. Updated 2026-09-30. The first ten rows are the suggested first sitting; remaining rows resolve implementation and qualification detail. R2 validation, manual priority, truthful Program, no unqualified auto-cut, local physical stop and no unapproved audio retention remain binding constraints. H4 asks how to demonstrate safety, not whether to waive it.

| ID | Question | Options | Recommendation | Blocks which card/code | Urgency |
|---|---|---|---|---|---|
| [S1](../../auto-director/product-contract.md) | First directing scope? | Sermon Auto Prepare; sermon Suggest; worship/panel; whole service | Sermon Auto Prepare, nominated subject | AD-SCOPE; director orchestration | Now |
| [A1](../../auto-director/authority-and-override.md) | Manual override scope? | Global pause; channel pause; temporary suppression | Global pause, explicit resume | AD-OVERRIDE; DirectorAuthority | Now |
| [A3](../../auto-director/authority-and-override.md) | Who may cut automatically? | Never; qualified Auto Direct; fallback-only | Separate qualified Auto Direct gate; unavailable initially | AD-TAKE; atomic permit/Take integration | Now |
| [E1](../../auto-director/subject-evidence.md) | Who selects a different person? | Operator; visual salience; audio/visual fusion | Operator nomination per camera | AD-SUBJECT; identity evidence adapter | Now |
| [P1](../../auto-director/prepare-and-readiness.md) | Director-ready shot definition? | R2 only; identity + settled; permitted motion | Identity + continuously settled, on top of R2 | AD-PREPARE; DirectorReadiness | Now |
| [R2](../../auto-director/roles-and-fallback.md) | Automatic loss fallback? | Ask; widen live; safe Take | Ask and pause; safe Take needs separate later decision | AD-ROLES/TAKE; fault transitions | Now |
| [H1](../../hardware/control-target-decision.md) | First physical target? | Feedback actuator; VISCA PTZ; Sony SDK; Blackmagic/ONVIF | L12-100-210-12-P yaw bench + local safety MCU, subject to load review | HW-CHOICE/S5–S7; adapter and simulator | Before hardware round |
| [V1](../../voice/speech-stack-decision.md) | First recognizer spike? | whisper.cpp; on-device SFSpeechRecognizer; SpeechAnalyzer | SpeechAnalyzer first on 26.2; measured whisper comparator | S4; recognizer adapter/assets | Before voice round |
| [V2](../../voice/speech-stack-decision.md) | Grammar versus voice-directed LLM? | Grammar only; LLM execution; staged structured proposals | Grammar executes; local LLM later drafts reviewed intent | S4/AD-PREFS; parser boundary | Now |
| [E2](../../auto-director/subject-evidence.md) | Director audio policy? | None; local ephemeral; retained study audio | None initially; separate approval for local ephemeral evidence | AD-SUBJECT/COMPUTE; audio collection | Before any audio |
| [A2](../../auto-director/authority-and-override.md) | Pin semantics? | Program shot intent; person; fixed pixels | Pin Program intent, tracking may continue; unpin leaves paused | AD-OVERRIDE/UI; pin state | Before wiring |
| [A4](../../auto-director/authority-and-override.md) | Auto Direct notice? | None; countdown; confirm each cut | Proposed 3 s cancellable notice only in qualified Auto Direct | AD-TAKE/UI; deadline token | Before Auto Direct |
| [S2](../../auto-director/product-contract.md) | What stays manual? | Cuts + subject changes; cuts only; autonomous speaker | All cuts initially, nominations, cues and recovery | AD-SCOPE/SUBJECT; operator workflows | Before wiring |
| [P2](../../auto-director/prepare-and-readiness.md) | Ambiguous identity? | Guess; abstain; confirmation | Abstain and ask nomination; preserve manual Take | AD-SUBJECT/PREPARE; readiness reasons | Before wiring |
| [P3](../../auto-director/prepare-and-readiness.md) | Proposal lifetime? | Unlimited; fixed; revisions + expiry | Revision-bound plus proposed 5 s intent lease | AD-PREPARE; proposal validator | Before wiring |
| [E3](../../auto-director/subject-evidence.md) | Study media retention? | No media; expiring consented fixtures; indefinite | Private consented fixtures, proposed 30 days and explicit renewal | AD-QA; fixture register | Before collection |
| [R1](../../auto-director/roles-and-fallback.md) | Camera roles? | Reserve safe wide; interchangeable; optional fallback | One verified safe-wide camera and one speaker camera | AD-ROLES; role eligibility | Before wiring |
| [T1](../../auto-director/shot-style.md) | Sermon pace? | Fixed timer; bounded suggestions; event-only | Proposed 20/45/90 s min/preferred/soft max; no forced cut | AD-STYLE; DirectorShotPolicy | Before study freeze |
| [T2](../../auto-director/shot-style.md) | Cut into movement? | Allowed; settled; whitelist | Settled only first; retain manual R2 moving Take | AD-STYLE/PREPARE; motion gate | Before wiring |
| [T3](../../auto-director/shot-style.md) | Wide frequency? | Mandatory; soft reminder; none | Proposed 120 s soft reminder, no timer cut | AD-STYLE/ROLES; style policy | Before study freeze |
| [F1](../../auto-director/preferences.md) | Preference authoring? | Structured; free text; both executable | Versioned structured controls; text drafts later | AD-PREFS; DirectorPreferences | Before wiring |
| [F2](../../auto-director/preferences.md) | Mid-show policy edits? | Locked; immediate; pause then apply | Invalidate proposals and pause, explicit resume | AD-PREFS/OVERRIDE; policy revision | Before wiring |
| [F3](../../auto-director/preferences.md) | Rundown execution? | Timed automatic; operator advanced; none | Operator advanced cue constraints, never authority | AD-PREFS; cue model | Before wiring |
| [U1](../../auto-director/ui-notes.md) | Director controls location? | Next-shot panel; pill; inspector | Next-shot panel; Pause/Pin/Resume inline | AD-UI; DirectorSection | Before UI prototype |
| [U2](../../auto-director/ui-notes.md) | Mode display? | Generic Auto; explicit levels; hidden levels | Four explicit levels, clear qualification state | AD-UI/TAKE; seam mode enum | Before UI prototype |
| [C1](../../../reports/auto-director/workload-plan.md) | Initial analysis? | Reuse observations; extra vision model; audio/LLM | Reuse existing bounded video observations | AD-COMPUTE; scheduler | Before wiring |
| [C2](../../../reports/auto-director/workload-plan.md) | Admission evidence? | R2 certification alone; workload fingerprint; generic Mac list | Separate workload fingerprint tied to exact R2 rig | AD-COMPUTE/QA; admission integration | Before live trials |
| [C3](../../../reports/auto-director/workload-plan.md) | Director logs? | None; sanitized local; media/transcripts | Bounded metadata, proposed 30-day expiry, explicit export | AD-COMPUTE/privacy; diagnostics | Before collection |
| [Q1](../../../reports/auto-director/qualification-protocol.md) | Qualification gates? | One gate; per-level; direct live | Replay, supervised live, explicit per-level sign-off | AD-QA/TAKE; qualification permit | Before trial |
| [Q2](../../../reports/auto-director/qualification-protocol.md) | Frozen error budgets? | Average quality; zero critical + bounded quality; guarantee | Protocol table: zero observed critical events plus exposure/uncertainty | AD-QA; replay/live reports | Before scored run |
| [Q3](../../../reports/auto-director/qualification-protocol.md) | Signatories? | Developer; owner/operator/technical reviewer; operator | Stephan + volunteer lead + independent technical reviewer | AD-QA; release permission | Before trial |
| [H2](../../hardware/control-target-decision.md) | Initial motion capability? | Manual jog; goto; visual servo | Bounded manual jog after stop tests; measured-position goto later | S6/S7; hardware commands | Before motion |
| [H3](../../hardware/control-target-decision.md) | First installation/transport? | Short USB; stage wired bridge; wireless | Short USB bench; measure final cable run before bridge | S5; transport | Before procurement |
| [H4](../../hardware/control-target-decision.md) | Safety evidence design? | Host stop; watchdog; watchdog + physical stop/limits | Local watchdog + independent physical stop/limits, mandatory | S5/S6; firmware and stop plan | Before motion |
| [V3](../../voice/speech-stack-decision.md) | Listening gesture? | Wake prefix; push-to-talk; both | Close-talk wake-prefix trial + mute; PTT if gate fails | S4; mic/UI | Before acoustic trial |
| [V4](../../voice/speech-stack-decision.md) | Voice target binding? | Current target; explicit channel; named Program allowed | Explicit A/B with two inputs, captured at utterance start, Preview only | S4; VoiceCommandAdapter | Before wiring |
| [V5](../../voice/speech-stack-decision.md) | Voice privacy? | Disabled; local ephemeral; retained diagnostics | Opt-in local ephemeral; separate recording consent | S4; permissions/retention | Before mic capture |

Numerical recommendations are proposed starting values; approve/freeze the complete parameter and metric tables in their linked memos before runs. Audio V5 and E2 are separate purposes: approving booth commands does not approve sermon active-speaker analysis.

Decision recording procedure: Stephan records ID, selected option, scope, conditions, date and approver in this file in the next decision round. Until then all rows stay OPEN; Sol may continue isolated decision-independent foundations only.
