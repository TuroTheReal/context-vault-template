---
name: learn-feedback
description: Learn your preferences from the propose→react loop in Claude Code transcripts, so the AI ships better first drafts of code, text, feature design, and planning. Mines all projects' transcripts for episodes where you validated / modified / rejected / refined what the AI proposed, distills each into a behavioral rule (tagged by work-type), and bundles candidates into ONE review PR in the vault feedback/ layer (source of truth). On merge, rules are projected into the Claude Code memory system (auto-loaded → changes behavior). STRICTLY FACTUAL · only your stated words and observed actions, zero deduction. Triggers on "learn feedback", "what did I correct", "/learn-feedback", or the weekly learn-feedback agent.
---

# /learn-feedback

Self-improvement loop. Reads how **you react** to what the AI proposes, distills durable
**behavioral lessons**, and makes them auto-load so the next first draft lands closer to what you
want. Operates across all work types: code, text, feature design, roadmap planning, process.

## North star

Converge the AI's first-draft quality toward your preferences, **per work type**. The lever is
your **reactions** (validate / modify / reject / refine), not the AI's own opinions. Each week
adds a few lessons; the PR review keeps them honest.

## Pillar model (read this before anything)

`feedback/` is a small fixed set of PILLAR files (one per work-domain: `safety`, `voice`,
`planning-design`, `git-repos`, `routines`), NOT atomic one-rule files. Each pillar = a list
of rules as `###` sections (each tagged `· scope:<..> · confidence:<..>`). Capture and dedup
operate on pillars: a new preference is a rule SECTION added to (or edited in) the matching pillar,
never a new file. A new file only when a genuinely new pillar/domain emerges (rare). See
`<VAULT>/feedback/SCHEMA.md`.

## Two-layer model (read this before anything)

- **Source of truth = `<VAULT>/feedback/`** · portable pillar markdown + `INDEX.md`. Survives an
  AI switch. Governed by `<VAULT>/feedback/SCHEMA.md` (read it every run, never operate from memory).
- **Projection = Claude Code memory** `~/.claude/projects/<project>/memory/feedback_*.md` + `MEMORY.md`.
  Harness-specific, **regenerable**, auto-loaded into every session → this is what actually changes
  behavior today. One-directional: `feedback/` (approved) → memory. The memory mirror is one file
  per pillar (`feedback_<pillar>.md`), same rule sections.

The PR gates the source of truth. The projection is mechanical and follows from it.

## ⛔ Fidelity rule (NON-NEGOTIABLE)

Identical to `/daily-ingest`, applied to reactions. A wrong lesson degrades every future session.

- Only your **stated words** and **observed actions**. Never infer a preference you didn't express
  or enact. **Zero deduction.**
- Every lesson traces to ≥1 concrete **episode** (session id + what you said/did on what the AI
  proposed). No episode = no lesson.
- The AI's suggestions are not your preference unless you explicitly validated them.
- Unsure if it's a real preference vs a one-off → omit (an inclusion call, separate from `confidence`).

## Hot-takes (in-session capture)

The weekly mining run is the safety net; hot-takes are the fast path. Capture a preference
IMMEDIATELY, mid-session, when ANY of these 3 triggers fires:

- (a) you say "note: X not Y" (or equivalent explicit correction of what to do),
- (b) you say "keep this" / "remember this" (explicit ask to remember),
- (c) the correction is clear on its face (proactive capture, no ask needed).

On a trigger, capture the **proposed-vs-shipped delta** (what the AI proposed → what you actually
wanted) into the matching pillar's MEMORY file (`~/.claude/.../memory/feedback_<pillar>.md`):
add a new `###` rule section or edit the existing one, dedup INTO the existing pillar (never a new
file, apply Step 4's dedup logic against the pillar's current rules).

**Flag-before-write on two pillars:** for a `safety` or `git-repos` rule, FLAG the proposed capture
to you and get your OK before writing (no silent write on those two, they gate risky/irreversible
behavior). The other three pillars (`voice`, `planning-design`, `routines`) write directly.

Hot-takes touch MEMORY only (immediate behavior change). They do NOT open a PR. The weekly cron
back-fills them into the vault PR (Step 5), where you review / edit / veto them; `--sync-on-merge`
then projects the approved vault state back to memory (vault wins).

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
- `--sync-on-merge` · only run the reconcile step, no mining, no PR. Run it after a feedback PR
  merges to project the approved vault pillars back into memory (VAULT WINS): this is where your PR
  edits / vetoes of mid-week hot-takes take effect, and where deleted rules are dropped from memory.
- `--consolidate` · gardening pass (no mining): scan the active set for duplicate clusters, stale /
  resolved rules, and over-specified files; propose merges / archives / sharpenings to keep the set
  minimal ("smallest high-signal set"). Outputs proposals in the PR + digest, never auto-applies.

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

Keep the two layers consistent before mining (VAULT WINS):
- **`feedback/` (approved on main) → memory**: for each pillar whose `memory_name` projection is
  missing or stale → (re)write `~/.claude/.../memory/feedback_<pillar>.md` (all its rule sections)
  and ensure its one-line pointer exists in `MEMORY.md`. A rule you deleted/vetoed from a pillar
  on merge → drop that rule section from memory. An archived atomic file → remove its memory file +
  MEMORY.md line (the vault keeps the archived copy as the durable record).
- **memory-only → back-fill candidate**: any memory rule (or whole pillar) with NO counterpart in
  the vault pillars → queue it as a back-fill candidate for this run's PR (so the portable layer
  becomes complete). This is where mid-week HOT-TAKES written straight to memory get reconciled into
  the vault. Distill it into the pillar schema (pillar/scope/episode).
- Reconcile is the only writer to memory during mining. In `--sync-on-merge` mode, stop after this step.

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

### Step 3 · distill (one rule section per durable preference)

For each episode carrying a generalizable preference:
- Determine the target PILLAR (safety / voice / planning-design / git-repos / routines) from
  the work-moment, and `scope` (global/work/repo:X) from where it applies.
- Write the rule as a `###` section per `SCHEMA.md`: `### <rule> · scope:<..> · confidence:<..>`
  heading + one-line rule + **Why** (traced) + **How to apply** (concrete directive) + **Episodes**.
  Set `confidence` by ADHERENCE (see SCHEMA), not evidence count: `low`
  if you keep re-giving it / it's still frequently missed (high vigilance), `medium` if mostly
  applied, `high` if reliably met. Default a fresh lesson to `medium`; use `low` when there's a clear
  pattern of repeated re-correction.
- Drop pure one-offs with no transfer value. A correction specific to one file/PR with no general
  rule behind it is not a lesson.

### Step 4 · dedup vs existing pillars (vault AND memory)

For each candidate, grep BOTH the vault pillars (`feedback/*.md`) AND the memory pillars
(`~/.claude/.../memory/feedback_*.md`) for the same preference. Checking memory too means a
hot-take already captured mid-session (see above) is not duplicated as a "new" rule.
- **new** → add a new `###` rule section to the matching pillar (add the file only if a genuinely
  new pillar/domain emerges).
- **reinforcement** → update the existing rule section in its pillar: add the episode to
  **Episodes:**, bump the pillar's context. CONFIDENCE INVERSION: a repeat correction means you
  are STILL having to re-give this → keep or LOWER the section's `confidence` toward `low` (high
  vigilance). Do NOT raise it. Raise confidence only when corrections have stopped over time.
  Sharpen "How to apply" only with traced detail.
- **contradiction** → mark the old rule section clearly and add the new one in the same pillar.
  Never overwrite a past conclusion (mirrors `notes/` supersede rule).

### Step 5 · ONE review PR

- Branch once: `git -C <VAULT> checkout -b vault-sync/<YYYY-MM-DD>-feedback origin/main`.
- Write/update the pillar files + regenerate `INDEX.md` + append to `log.md`. One commit per pillar
  touched (clean history). This is also where hot-takes captured mid-week get back-filled into the
  vault PR (they already live in memory; the PR reconciles them into the source of truth).
- `git push -u origin vault-sync/<date>-feedback` then ONE `gh pr create --title
  "vault-sync: feedback <date>" --body "<per-rule summary: pillar · scope · confidence · hook + episode refs>"`.
- **Exactly one PR per run.** `auto_merge: false` · you review, edit, delete candidates, merge.
- Nothing learned → delete the empty branch, exit without a PR.
- Advance `last_feedback` to now in `.vault-state.yml` (only on success).
- The PR does NOT touch memory. The projection happens at the NEXT run's reconcile (Step 1) once
  the PR is merged, or on demand via `/learn-feedback --sync-on-merge`.

## Adherence (the real lever)

Capturing rules is easy; APPLYING them is the hard part. A `low`-confidence rule (e.g. peer-voice) is
loaded yet still missed. More rules DILUTE attention (context rot), they do not fix adherence. So the
system optimizes for application, not accumulation:
- **Sharpen, do not pile.** A `low` rule = a crisp directive + 1-2 canonical examples, not a long
  edge-case essay. Minimal set + examples beats exhaustive rule-lists.
- **Surface the `low` ones.** `INDEX.md` lists them in a top "verify before delivering" block. Before
  delivering output of a given `kind`, re-check it against the `low` rules of that kind.
- **Prune to stay lean.** Run `--consolidate` periodically: merge duplicates, archive resolved,
  sharpen the verbose. Keep the active set well under the ~200-line / 25KB startup budget.

## Notes

- **PR gates behavior.** A candidate the AI got wrong never reaches memory unless you merge it,
  EXCEPT hot-takes, which write to memory immediately (the PR back-fills + you can veto on merge).
- **Hot-takes are the fast path.** When you correct mid-session (see Hot-takes above), the AI
  writes the rule straight into the matching memory pillar (flag-first on safety/git-repos). This
  skill is the second-pass safety net: it catches what was missed and back-fills memory-only rules
  into the portable pillars.
- **Retrieval at scale**: `INDEX.md` stays thin (one hook line/pillar); full pillar files are pulled
  by relevance. Same scaling trick as `MEMORY.md`. Keep rules crisp and short.
- **Memory projection format** = one file per pillar, `feedback_<pillar>.md`: frontmatter `name`
  (= `feedback_<pillar>`) + `description` (one line covering the pillar's rules) + `metadata:
  node_type: memory / type: feedback`; body = intro line + one `### rule · scope · confidence`
  section each (pattern + Why + How to apply + `[[links]]`). The pillar's `memory_name:` is the
  round-trip key.

## Related

- [/daily-ingest](../daily-ingest/SKILL.md) · domain reasoning → `notes/` (different signal, different store)
- [/audit-vault](../audit-vault/SKILL.md) · vault health (could later flag stale/low-confidence feedback)
- Feedback schema: `<VAULT>/feedback/SCHEMA.md`
- Vault schema: `<VAULT>/CLAUDE.md` + `<VAULT>/SCHEMA.md`
