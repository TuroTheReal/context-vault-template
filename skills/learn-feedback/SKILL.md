---
name: learn-feedback
description: Learn your preferences from the propose→react loop in Claude Code transcripts, so the AI ships better first drafts of code, text, feature design, and planning. Mines all projects' transcripts for episodes where you validated / modified / rejected / refined what the AI proposed, distills each into an atomic behavioral lesson (tagged by work-type), and bundles candidates into ONE review PR in the vault feedback/ layer (source of truth). On merge, lessons are projected into the Claude Code memory system (auto-loaded → changes behavior). STRICTLY FACTUAL · only your stated words and observed actions, zero deduction. Triggers on "learn feedback", "what did I correct", "/learn-feedback", or the weekly learn-feedback agent.
---

# /learn-feedback

Self-improvement loop. Reads how **you react** to what the AI proposes, distills durable
**behavioral lessons**, and makes them auto-load so the next first draft lands closer to what you
want. Operates across all work types: code, text, feature design, roadmap planning, process.

## North star

Converge the AI's first-draft quality toward your preferences, **per work type**. The lever is
your **reactions** (validate / modify / reject / refine), not the AI's own opinions. Each week
adds a few lessons; the PR review keeps them honest.

## Two-layer model (read this before anything)

- **Source of truth = `<VAULT>/feedback/`** · portable atomic markdown + `INDEX.md`. Survives an
  AI switch. Governed by `<VAULT>/feedback/SCHEMA.md` (read it every run, never operate from memory).
- **Projection = Claude Code memory** `~/.claude/projects/<project>/memory/feedback_*.md` + `MEMORY.md`.
  Harness-specific, **regenerable**, auto-loaded into every session → this is what actually changes
  behavior today. One-directional: `feedback/` (approved) → memory.

The PR gates the source of truth. The projection is mechanical and follows from it.

## ⛔ Fidelity rule (NON-NEGOTIABLE)

Identical to `/daily-ingest`, applied to reactions. A wrong lesson degrades every future session.

- Only your **stated words** and **observed actions**. Never infer a preference you didn't express
  or enact. **Zero deduction.**
- Every lesson traces to ≥1 concrete **episode** (session id + what you said/did on what the AI
  proposed). No episode = no lesson.
- The AI's suggestions are not your preference unless you explicitly validated them.
- Unsure if it's a real preference vs a one-off → omit (an inclusion call, separate from `confidence`).

## When to use / not

- Weekly, via the `learn-feedback` agent (Thursday evening, Friday-morning catch-up; same
  large-window pattern as daily-ingest, anchored on Thursday to avoid a Monday-morning review pile).
- Manually to distill recent corrections on demand.
- NOT for domain knowledge (positions, decisions, project state) → that's `/daily-ingest`.
- Zero new episodes since the cursor → exit clean, no empty PR.

## Inputs (all optional)

- `--since <YYYY-MM-DD | ISO>` · override the window. Default = `last_feedback` cursor in
  `.vault-state.yml`; if null, last 7 days.
- `--dry-run` · produce the candidate list (episodes + distilled lessons + dedup verdict), write
  NOTHING to git/memory, no PR. For validation.
- `--seed` · one-time: back-fill the existing memory `feedback_*.md` files into `feedback/` (no
  transcript mining), so the portable layer starts complete. Then exits.
- `--sync` · only run the reconcile step (project merged `feedback/` → memory, drop deleted), no
  mining, no PR.

## Identity

- `VAULT = <vault>`, `EMAIL = <user_handle.email>`.
- CC transcripts root = `~/.claude/projects/`. Memory root = `~/.claude/projects/<project>/memory/`
  (the canonical memory dir loaded across sessions).
- Slack self-DM target: `<user_handle.slack_user_id>`.

## Pipeline

### Step 0 · schema + cursor

- Read `<VAULT>/feedback/SCHEMA.md` in full. Read `<VAULT>/.vault-config.yml` (handles, git mode).
- Read `last_feedback` cursor from `<VAULT>/.vault-state.yml` (separate from `last_ingest` /
  `last_fetch`). If absent, default window = last 7 days.

### Step 1 · reconcile (idempotent, always first)

Keep the two layers consistent before mining:
- **`feedback/` (approved on main) → memory**: any active feedback whose `memory_name` projection
  is missing or stale → (re)write `~/.claude/.../memory/feedback_<slug>.md` and ensure its one-line
  pointer exists in `MEMORY.md`. `superseded`/deleted feedback → remove its memory file + MEMORY.md line.
- **memory-only → back-fill candidate**: any memory `feedback_*.md` with NO counterpart in
  `feedback/` → queue it as a back-fill candidate for this run's PR (so the portable layer becomes
  complete). Distill it into the `feedback/` schema (kind/scope/episode from its `originSessionId`).
- Reconcile is the only writer to memory. In `--sync` mode, stop after this step.

### Step 2 · find episodes (transcript mining)

- Glob CC transcripts modified since the cursor: `~/.claude/projects/*/*.jsonl`. **Exclude**
  `**/subagents/**` and `**/workflows/**` (internal agent runs, not you). All projects, not just
  your main work repo (behavior should align everywhere).
- **Apply exclusions** from `.vault-config.yml` `learn_feedback:`:
  - drop any transcript whose project dir matches `exclude_projects` (substring/glob on the encoded
    dir name, e.g. `-Users-you-Documents-your-personal-repo`),
  - drop any session whose id is in `exclude_sessions`,
  - drop any session in which ANY of your messages contains the token `#no-learn` (also matches
    `no-learn`, case-insensitive). Position is irrelevant: a marker typed at the very end excludes
    the WHOLE session, earlier turns included.
  Excluded transcripts are never read past this filter → zero quotes from them reach the PR.

  **Mixed-session caveat:** `exclude_projects` matches on the Claude Code project dir (the cwd at
  launch). Work on an excluded repo done from *inside another project's session* (e.g. editing
  `your-personal-repo` files during a work-repo session) is NOT caught by the project filter · that
  session's dir is the work repo. For those, use `#no-learn` in the session, or add its id to
  `exclude_sessions`. Distillation must also drop episodes clearly scoped to an excluded repo even
  when they surface inside a non-excluded session.
- A real turn of yours = `type=="user"` whose `message.content` is a genuine string you typed (NOT
  an injected tool-result / system-reminder / attachment). Anchor on these.
- Identify **propose→react episodes**: an AI output (code edit, message draft, plan, design choice,
  tool call) immediately followed by your reaction. Classify the reaction:
  - **validate** · "go", "ok", "parfait", merges the PR, approves the tool call, accepts the plan.
  - **modify** · you edit the file the AI wrote, or reply with a correction ("plutôt comme ça",
    "non, fais X"), or rewrite a draft. The *delta* is the signal.
  - **reject** · "non", "annule", denies the tool call, reverts, closes the PR, "c'est pas ça".
  - **refine** · picks a specific option in an `AskUserQuestion`, or adds a constraint.
- Cross-signal where cheap: `git log`/PR merge-vs-close, file edits after an AI write. Don't fetch
  external state heavily; transcript text is the primary source.

### Step 3 · distill (one atomic lesson per durable preference)

For each episode carrying a generalizable preference:
- Determine `kind` (code/text/design/planning/process) from the work type, and `scope`
  (global/work/repo:X) from where it applies.
- Write the lesson per `SCHEMA.md`: one-line rule + **Why** (traced) + **How to apply** (concrete
  directive) + **Episodes**. Set `confidence` by ADHERENCE (see SCHEMA), not evidence count: `low`
  if you keep re-giving it / it's still frequently missed (high vigilance), `medium` if mostly
  applied, `high` if reliably met. Default a fresh lesson to `medium`; use `low` when there's a clear
  pattern of repeated re-correction.
- Drop pure one-offs with no transfer value. A correction specific to one file/PR with no general
  rule behind it is not a lesson.

### Step 4 · dedup vs existing `feedback/`

For each candidate, grep `feedback/` for the same preference:
- **new** → new `feedback/<kind>-<slug>.md`.
- **reinforcement** → update the existing file: add the episode to `sessions:`/`Episodes:`, bump
  `updated:`. CONFIDENCE INVERSION: a repeat correction means you are STILL having to re-give this
  → keep or LOWER `confidence` toward `low` (high vigilance). Do NOT raise it. Raise confidence only
  when corrections have stopped over time. Sharpen "How to apply" only with traced detail.
- **contradiction** → new file with `supersedes: <old-slug>`; set old `status: superseded`. Never
  overwrite a past conclusion (mirrors `notes/` supersede rule).

### Step 5 · ONE review PR

- Branch once: `git -C <VAULT> checkout -b vault-sync/<YYYY-MM-DD>-feedback origin/main`.
- Write/update the `feedback/` files + regenerate `INDEX.md` + append to `log.md`. One commit per
  lesson (clean history).
- `git push -u origin vault-sync/<date>-feedback` then ONE `gh pr create --title
  "vault-sync: feedback <date>" --body "<per-lesson summary: kind · scope · confidence · hook + episode refs>"`.
- **Exactly one PR per run.** `auto_merge: false` · you review, edit, delete candidates, merge.
- Nothing learned → delete the empty branch, exit without a PR.
- Advance `last_feedback` to now in `.vault-state.yml` (only on success).
- The PR does NOT touch memory. The projection happens at the NEXT run's reconcile (Step 1) once
  the PR is merged, or on demand via `/learn-feedback --sync`.

## Notes

- **PR gates behavior.** A candidate the AI got wrong never reaches memory unless you merge it.
- **In-conversation memory writes still happen.** When you give feedback mid-session, the AI may
  still write a memory file immediately (existing behavior). This skill is the second-pass safety
  net: it catches what was missed and back-fills memory-only feedback into the portable layer.
- **Retrieval at scale**: `INDEX.md` stays thin (one hook line/lesson); full files are pulled by
  relevance. Same scaling trick as `MEMORY.md`. Keep lessons atomic and short.
- **Memory projection format** mirrors existing `feedback_*.md`: frontmatter `name` + `description`
  (the hook) + `metadata.type: feedback` + `originSessionId`; body = pattern + Why + How to apply +
  `[[links]]`. The `feedback/` file's `memory_name:` is the round-trip key.

## Related

- [/daily-ingest](../daily-ingest/SKILL.md) · domain reasoning → `notes/` (different signal, different store)
- [/audit-vault](../audit-vault/SKILL.md) · vault health (could later flag stale/low-confidence feedback)
- Feedback schema: `<VAULT>/feedback/SCHEMA.md`
- Vault schema: `<VAULT>/CLAUDE.md`
