# Feedback layer · schema

How-to-work-for-you layer. **Source of truth** for behavioral feedback: what you
validate / modify / reject / refine on what the AI proposes, distilled into rules
so the AI ships better first drafts (code, text, design, planning, process).

Portable by design: plain markdown in git. Any AI can be pointed at `INDEX.md`. The Claude
Code `~/.claude/projects/<project>/memory/feedback_*.md` files are a **regenerable projection**
of this layer (the harness auto-loads them), never the source of truth.

This layer is SEPARATE from `notes/` (domain knowledge). Do not mix them:
- `notes/` = what you know/decide about your work. Faithfulness to external sources.
- `feedback/` = how the AI should work for you. Faithfulness to your reactions.

## ⛔ Fidelity rule (NON-NEGOTIABLE)

A wrong feedback is WORSE than none: it degrades every future session until caught.

- Distill **only** from your **stated words** and **observed actions** (validated, edited,
  rejected, reordered). Never infer a preference you did not express or enact. **Zero deduction.**
- Every feedback traces to at least one concrete **episode** (session id + what you said/did
  on what the AI proposed). No episode = no feedback. Mirrors `notes/`'s "no source URL = no note".
- The AI's own analyses/suggestions are NOT your preference. Capture them only if you
  explicitly validated them, framed as "you validated X".
- Uncertain whether it's a real preference or a one-off → leave it out. (Don't confuse this with
  `confidence`: inclusion is about whether it's a real preference; `confidence` is about how well
  the AI already applies it.)
- Never overwrite a past lesson. Reversed preference → mark the old rule section clearly, add the new one.

## File = one PILLAR (a small fixed set of them)

`feedback/` holds a small fixed set of PILLAR files (one per work-domain). Each pillar = a list
of rules as `###` sections. Capture EDITS the relevant pillar (add / modify / remove a rule
section); NEVER create a new file for a rule that fits an existing pillar. A new file only when a
genuinely new pillar/domain emerges (rare).

### The 5 pillars

| pillar | loaded_when |
|---|---|
| `safety` | before any risky action (git push, deletion, external action, permissions) |
| `voice` | when writing any text/message/draft for you |
| `planning-design` | when planning a roadmap or designing a feature/architecture |
| `git-repos` | when doing git / opening a PR on a repo |
| `routines` | when running one of your recurring vault skills/routines |

### Pillar frontmatter

```yaml
pillar: <name>                                        # safety | voice | planning-design | git-repos | routines
loaded_when: <one line: the work-moment when this pillar is relevant>
status: active
memory_name: feedback_<name>                           # filename of the memory projection (round-trip key)
source: claude-code-conversation
```

### Pillar body

Intro line, then one `### <rule>` section per rule. Each `###` heading carries a
`· scope:<..> · confidence:<..>` tag. Each rule section:

```
### <rule> · scope:<global | work | repo:<name>> · confidence:<low | medium | high>

<one-line pattern statement · the rule itself>

**Why:** <your reason, traced to the episode · never invented>

**How to apply:** <concrete directive the AI follows next time it does this kind of work>

**Episodes:**
- session <id> · you <said/did X> on <AI proposal Y>
```

- `scope` = where the rule applies (`global | work | repo:<name>`).
- `confidence` = ADHERENCE, not evidence: how reliably the AI meets this NOW. `low` = still
  frequently missed / you keep re-giving it = HIGH vigilance. `medium` = mostly applied.
  `high` = reliably met, rarely corrected.
- A reversed preference does not overwrite a rule: mark the old section clearly and add the new
  one (mirrors `notes/`'s supersede rule).

Link related feedback in the body with `[[other-name]]`.

## kind · the retrieval key

| kind | reaction signals in transcripts | lesson is about |
|---|---|---|
| `code` | merge as-is / edits the diff / rejects approach / review comments / revert | structure, naming, test style, lib choice, smallest-change, no speculative code |
| `text` | sends as-is / rewrites in your voice / cuts length | voice, format, length |
| `design` | accepts design / redirects scope / picks a different AskUserQuestion option | priorities, tradeoffs you weight (MVP-first, security-first) |
| `planning` | reorders priorities / cuts speculative items / changes granularity | how you sequence and scope |
| `process` | corrects HOW the AI operates (git, PR, permissions, ask-first) | workflow and conventions |

## scope

- `global` · applies everywhere (e.g. no em dash). Candidate for a portable cross-context store later.
- `work` · work-specific (team voice, crew conventions).
- `repo:<name>` · repo-specific (e.g. `repo:portfolio` PR format).

## INDEX.md

Thin always-loadable index, one line per pillar. The scaling lever: any AI loads only the
index, retrieves the full pillar file by relevance. Format:

```
- [<name>](<name>.md) · loaded when <moment> · <short hook listing its rules>
```

A top "verify before delivering (low-adherence)" block surfaces the currently-`low` rules;
an "archived" block lists resolved atomic files kept for reference.
Regenerated by `/learn-feedback`, never hand-edited.
