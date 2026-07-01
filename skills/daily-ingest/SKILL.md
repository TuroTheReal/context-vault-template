---
name: daily-ingest
description: Daily automatic enrichment of the your-company context vault. Consumes the day's already-captured raws (external sources) AND your reasoning (your own messages + validated decisions from the day's Claude Code transcripts), synthesizes via /ingest into notes, bundled into ONE daily PR (vault-sync/<date>-daily) for you to review. STRICTLY FACTUAL — only your words and actions, zero deduction/inference/hallucination. Replaces manual /ingest for the daily flow; manual /ingest stays for one-offs. Triggers on "vault ingest", "daily ingest", "enrich the vault", "/daily-ingest", or the nightly daily-ingest agent.
---

# /daily-ingest

Daily auto-enrichment of the vault. Orchestrates: external raws of the day + reasoning capture (Claude Code transcripts) → `/ingest` for synthesis → **ONE** consolidated daily PR. Reuses `/ingest` for all note-writing. Manual `/ingest` stays for one-offs.

## North star

Grow the vault day by day until it can answer **"as you"**. The lever is your **reasoning** (the *why* of your choices), not just facts. Each day adds a little; iterations + your review sharpen it.

## ⛔ Fidelity rule (NON-NEGOTIABLE)

The whole value depends on this. Stricter than `/ingest`'s own faithfulness rule, applied hard to the reasoning source:

- Synthesize **only** from your **stated words** (your own messages) and your **actions** (decisions you explicitly made or validated).
- **Never** infer, conclude, generalize, extrapolate, or stylize. **Zero deduction.**
- Factual register only: "you a dit X sur Y", "you a décidé Z", "you en est là sur \<projet\>".
- The assistant's analyses / proposals / suggestions are **NOT** your position. Capture them only if you **explicitly validated** them, and then frame it as "you a validé X".
- If something isn't in your words or actions, it does **not** enter the vault. A note adding something you didn't say/do is a **bug**, not a feature.
- When unsure whether you actually said/validated something → leave it out.

## When to use

- Nightly, via the `daily-ingest` agent (end of day).
- Manually to enrich the vault from today's activity on demand.

## When NOT to use

- You want a one-off ingest of a single source → `/ingest <source>` (manual flow stays).
- You only want today's read recap → `/daily-digest`.
- Zero new raws and zero reasoning since last run → exit clean, no empty PR.

## Inputs

All optional:
- `--since <YYYY-MM-DD | ISO>` — override the window. Default = `last_ingest` cursor in `.vault-state.yml`; if null, last 24h.
- `--dry-run` — produce the raws + the planned list of ingests, write NOTHING to git, no PR. For validation.
- `--no-reasoning` — skip the Claude Code transcript capture (external raws only).
- `--no-sources` — skip external raws (reasoning only).

## Pipeline

### Step 0 — schema, identity, cursor

- Read `<VAULT>/CLAUDE.md` + `<VAULT>/SCHEMA.md` in full (schema source of truth). Never operate from memory.
- Identity: `VAULT = <vault>`, `EMAIL = <user_handle.email>`, CC transcripts root = `~/.claude/projects/`.
- Read the `last_ingest` cursor from `<VAULT>/.vault-state.yml` (created on first run). It is **separate from `last_fetch`** (the digest's): daily-ingest fetches with its OWN cursor via `fetch-sources --cursor ingest`, so the two never steal each other's window.

### Step 1 — external sources of the day (fetch via dedicated cursor)

- Run `/fetch-sources --cursor ingest --summary full`. This fetches the day's delta from the **your-company core sources** (Slack, Notion, GitHub PRs/issues, GitHub Discussions, Linear) since `last_ingest`, and writes `digest/<date>-fetch-summary.md`. `--cursor ingest` reads/writes `last_ingest.<source>` (NOT `last_fetch`), so the digest's window is untouched.
- `fetch-sources` no longer deposits individual raws — it produces this single summary. `/ingest` consumes the summary directly (it accepts a raw OR the whole summary).
- Apply the "content > event" filter: noise (auto-tag / CODEOWNERS review-requests, pure logistics) is NOT promoted to notes — only items carrying a decision / position / tradeoff / learning. your own active Linear/GitHub work IS signal.

### Step 2 — reasoning capture (Claude Code transcripts)

- Find CC transcripts modified since `last_ingest`: `~/.claude/projects/*/*.jsonl`. **Exclude** `**/subagents/**` and `**/workflows/**` (internal agent runs, not your reasoning). Prefer sessions where you actually interacted (real `type=="user"` text messages, not just tool-results).
- Extract **only your signal**:
  - `type == "user"` entries whose content is genuine you text (a plain string), NOT injected tool-results/system reminders.
  - your explicit decisions: validations ("go", "ok", "valide"), your picks in `AskUserQuestion` answers, your corrections.
- **Do NOT** capture assistant turns as your position (apply the Fidelity rule).
- Group into atomic ideas by topic/project. For each, write a raw under `<VAULT>/raw/conversations/<date>-<topic-slug>.md`:
  - Frontmatter: `source: claude-code-conversation`, `date`, `session_id`, `ingested: false`.
  - Body: faithful, factual capture of what **you said/decided** ("you a dit/décidé/validé …"). No assistant analysis, no inference.

### Step 3 — synthesize via /ingest, ALL on ONE branch

- Create the day's single branch once: `git -C <VAULT> checkout -b vault-sync/<YYYY-MM-DD>-daily origin/main` (reuse if it already exists today — see /ingest "Branch reuse").
- For each atomic raw from Steps 1-2: run `/ingest <raw> --no-pr`. The `--no-pr` flag makes `/ingest` write the note + index + log + flip the raw, **commit on the current branch**, and **skip** its own branch-switch/push/PR. One ingest = one commit (clean per-note history).
- `/ingest` keeps its full faithfulness + atomicity + **tagging** (controlled taxonomy) + create/update/supersede + coherence logic. We only take over the git packaging.

### Step 4 — ONE consolidated PR

- After all ingests: `git -C <VAULT> push -u origin vault-sync/<date>-daily` then **one** `gh pr create --title "vault-sync: daily <date>" --body "<per-note summary + sources>"`.
- **Exactly one PR per day. Never one-per-note (no 25 PRs).** If nothing was ingested (all aborted/logistics), delete the empty branch and exit without a PR.
- `auto_merge: false` — you reviews and merges.
- Advance `last_ingest` to now in `.vault-state.yml` (only on success).
- Output the single PR URL.

## Notes

- **One PR/day, hard rule.** The whole point of `--no-pr` + single branch is to avoid PR spam. A git-spice stack is the only acceptable alternative if ever needed; default is one flat PR with N commits.
- **No cursor conflict with the digest:** daily-ingest reads existing raws + transcripts via its own `last_ingest`; it never calls `fetch-sources` and never advances `last_fetch`.
- **Reuses `/ingest`** for synthesis (your intent). Manual `/ingest <source>` is unchanged and stays available.
- **Dedup:** raws are content-hashed by `/capture`; already-ingested raws (`ingested: true`) are skipped.

## Related

- [/ingest](../ingest/SKILL.md) — does the actual synthesis (called with `--no-pr` here)
- [/fetch-sources](../fetch-sources/SKILL.md) — deposits the external raws daily-ingest consumes (run by the digest, not here)
- [/daily-digest](../daily-digest/SKILL.md) — morning read recap (separate cursor, separate purpose)
- Vault schema: `<VAULT>/CLAUDE.md` + `<VAULT>/SCHEMA.md`
