# Director style: options

Status: summary, 2026-10-25. Epic [AD-STYLE-UX](https://trello.com/c/E3QWhqoq). Decisions: SU-1 to SU-5, F2, F3 in [DECISIONS.md](../handoff/stage3-4/DECISIONS.md).

Settings › Director used to ask for nine raw values per segment type. Four ways to set the style instead were explored; they combine rather than compete.

| Option | What the operator does | Status |
|---|---|---|
| **A · Pick a feel** | Chooses Pace (Calm / Balanced / Lively), Wide shots (Rarely / Sometimes / Often) and When someone moves (Wait until they settle / Cut while moving) for each kind of segment. Exact values stay available. | **Built first.** Feel table v1 in `Director/DirectorFeel.swift`; Settings › Director. |
| **B · Camera roles** | Tags each camera in Show setup as Safe wide, Speaker, Detail or Audience; each segment then favours or avoids roles. Gives Backup an explicit safe wide. | Later, with [AD-ROLES](https://trello.com/c/NIgYGG4C). |
| **C · Run sheet** | Lists the show's segments in order, each borrowing its feel; advances them live with ⌘⇧↩. Without it only the Live event feel applies. | Next: SU-09, SU-10. Model, editor and strip exist; not wired to a real show. |
| **D · Learn from your cuts** | After a show, compares the operator's cuts with what Alfie would have done and offers one-tap feel changes. | Later: needs shadow logs and enough shows. Metadata only, local, 30-day retention. |

What other tools do: Huddly Crew offers two intent modes, Mevo one pace slider, Descript None / Occasional / Frequent cutaways, and Pixellot a behaviour per sport. None of them ask for numbers.

Design canvas (owner access): https://claude.ai/artifact/AerkuuLnFDaiuFu6mxukL4, rows "Director: how operators set up shots" and "Director style: four ways to set it".
