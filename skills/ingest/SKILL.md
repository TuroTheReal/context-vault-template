---
name: ingest
description: Synthesize a source (URL or raw file) into a vault note. Creates or updates a note in notes/, fills sources, links, and citations per the vault schema. The main writer-into-the-second-brain.
---

# /ingest

Synthesizes a source into `<vault>/notes/`. Two entry flows converge on the same synthesis logic. Honors the vault schema (`<vault>/CLAUDE.md`) and produces a reviewable change (PR if `git_mode.notes: true`).

## When to use

- You read something (Slack thread, Notion page, GitHub PR, web article, conversation with me) and you decide it deserves to be in the second brain
- You're triaging a raw and concluded « this one becomes a note »
- An existing note's source has evolved (raw flagged `stale`) and you want to refresh the note

## When NOT to use

- You just want to archive without synthesizing → use `/capture`
- The source is generic company-wide data not specific to the user → out of scope (covered by your general knowledge tool, e.g. Confluence, Dust, Glean, etc.)
- The source captures only logistics (« meeting happened ») with no decision/position/tradeoff/learning → leave as raw, don't promote

## Inputs

One of:

- **`<URL>`** — origin URL. Flow B (direct). Calls `/capture` internally first, then synthesizes. Examples: any URL accepted by `/capture`.
- **`<path-to-raw>`** — local raw file. Flow A. Reads the raw, synthesizes from it (or live-fetches the source if the raw is a stub).

Optional flags:
- `--force-create` — bypass the « update existing note on same topic » detection. Use when you genuinely want a separate note despite topic overlap.
- `--note <existing-note-path>` — explicitly target an existing note for update (skip the auto-detection).

## Configuration read

From `<vault>/.vault-config.yml` (static config):
- `vault_path`, `git_mode.notes`, `git_remote`, `branch_prefix`, `auto_merge`

Does not read `.vault-state.yml` (no high-water mark needed for single-note ingest).

## Behavior — high level

```
Input → resolve raw (capture if needed, live-fetch if stub) →
  analyze content → determine type + links →
  decide create vs update →
  write/patch note (frontmatter + body + citations + position + obsidian-graph) →
  reverse-link integrity check + contradiction flag →
  update index.md + log.md + raw ingested status →
  git PR if enabled
```

## Behavior — precise steps

### Step 0 — re-read schema

Read `<vault>/CLAUDE.md` in full. Never operate from memory. The schema is the source of truth.

### Step 1 — resolve raw

- **Flow B (URL given)**: call `/capture <URL>` first → get the raw path back. Continue as flow A.
- **Flow A (raw path given)**:
  - Read the raw file (frontmatter + body).
  - If `stable: true` (stub raw) → **live-fetch** the source URL now. The stub is metadata only; synthesis needs current content. **If the live-fetch fails (404 / unreachable)** → flip the stub to `ingested: orphan` + set `dead_at: <today>`, abort synthesis, tell the user. Do NOT create or update a note from a dead source.
  - If `stable: false` (full raw) → use the body as content.
  - If `ingested: stale` → enter **semantic diff mode** (see Step 4b).

### Step 2 — analyze content

- Read the content **deeply**. Don't type from title — type from content.
- Determine:
  - **Type** — `project-` (multi-ticket initiative), `decision-` (choice + tradeoff), `context-` (everything else: position, learning, gotcha, org context). Apply the « content > event » filter: if the source is logistics with no density, **abort the ingest** (leave the raw as `ingested: false`, consultable only).
  - **Atomicity check** — does this source contain ONE atomic idea, or several? If several → split into multiple ingestions (one per atomic idea). Never bundle.
  - **Candidate links** (impact/dependency only): which existing notes does this impact? Which does it depend on? Same topic ≠ link. `context-` notes never get linked.

**Faithfulness rule** — the synthesized note is a **factual summary** of the source. Never invent, infer beyond what the source states, or stylize. If a fact is not in the source, it does not go in the note. Same rule as CLAUDE.md « Note format » section. This is non-negotiable: a note that adds a fact not in its source is a bug, not a feature.

**Author attribution — explicit only**: set `author:` in the note frontmatter **only when the source explicitly identifies an owner / author** (Notion page `Created by` or in-body `**Owner:** <Name>` / `Author: <Name>` line; Slack message `from`; GitHub PR `Author:`; meeting prep doc with named author). **Never infer** from « X is owner of the parent project » or « X is the most-cited person in the content ». If the source doesn't explicitly say who wrote it, leave `author:` empty. Same strict rule for `My position:` entries — only when the source explicitly identifies the speaker as the user. Never attribute a "we said" from a page in another team's space.

**Verify the source's home before attributing**: read the Notion ancestor path (`<ancestor-path>` in the fetched content) or the Slack channel / GitHub repo. If the source lives in another team's space and uses "we" referring to that team, the attribution and any "My position" framing must reflect that — not the user. When in doubt → no `author:`, no `My position:` entry.

### Step 3 — read index.md and decide create vs update

- Read `<vault>/index.md` to get the catalog.
- **Detect existing note candidates** for the same atomic idea:
  - Match by `source_id` if any existing note references this source
  - Match by topic from index entries
  - Match by `links:` overlap with already-known notes
- Resolve:
  - **No candidate** → CREATE a new note (Step 4a)
  - **One clear candidate** → UPDATE that note (Step 4b)
  - **Multiple candidates** → ask the user explicitly. Don't guess.
  - **Reversing decision** detected (new content contradicts the candidate's conclusion) → CREATE new `decision-` note with `supersedes: [old-note]`, mark old note `status: superseded`. Do NOT modify the old note's body or conclusions (Step 4c).
  - **`--force-create`** flag → skip detection, CREATE.
  - **`--note <path>`** flag → skip detection, UPDATE that note.

### Step 4a — CREATE a new note

- Path: `<vault>/notes/<type>-<short-slug>.md` (e.g. `decision-bigquery-migration.md`)
- Slug: kebab-case, descriptive, ≤ 4 words
- Write frontmatter (template below)
- Write body:
  - **First line**: `**Sources**: <human label 1>, <human label 2>`
  - If body > ~100 lines: TLDR (3-5 lines) right after Sources line
  - Synthesized content (atomic, dense, no fluff)
  - Inline citations `[^N]` if 2+ sources, footnotes at the bottom pointing to **origin URLs** (not raw paths)
  - `My position:` section if the user has expressed a stance on this topic in the source (only what he actually said — never invent)
  - `<!-- obsidian-graph -->` footer mirroring `links:` as `[[note-name]]`

### Step 4b — UPDATE an existing note

- **If raw is stale → semantic diff mode**:
  - Read the existing note + the appended portion of the raw (or live-fetch diff for stub)
  - Identify which **claims** in the note are affected by the new content
  - Patch only those claims; add new claims for genuinely new info
  - Preserve nuances the user already validated. **Never re-synthesize from scratch.**
- **If new info on same topic** (e.g. extra context, sub-decision):
  - Append a new section or extend an existing one
  - If the user has a new stance → append a dated entry under `My position:` (never delete old entries)
- Bump `updated:` to today
- Add new `sources:` URLs if the update brings a new origin
- Add new `raw:` paths if a new raw backs this update
- Re-check inline citations: if the note now has 2+ sources, add `[^N]` markers; if it still has only 1, none needed
- Re-check `links:` — does the new info add an impact relationship? If yes, add it (and re-sync `<!-- obsidian-graph -->`)

### Step 4c — REVERSE a decision

- Create a new `decision-` note (Step 4a) with:
  - `supersedes: [old-note-name]`
  - Body explains what changed and why
- Modify the old note ONLY:
  - `status: superseded`
  - Bump `updated:`
  - Append a single line at the very top of the body: `> Superseded by [[new-note-name]] on YYYY-MM-DD.`
  - Do NOT touch the old conclusions

### Step 5 — reverse-link integrity check

- Grep all `notes/*.md` frontmatter `links:` arrays for entries pointing to the new/updated note
- For each link the new/updated note declares (`links:`), verify the target exists. If missing → fail loud (no orphan links).

### Step 6 — coherence check across impacted notes

- Read every note in the new/updated note's `links:` array (and reverse-grep matches)
- Compare claims. If contradiction (e.g., this note says X, an impacted note says NOT X):
  - Add `⚠️ Contradiction: <one-line summary> vs [[other-note]]` at the **top of the new/updated note's body**, just under the `**Sources**` line
  - Do NOT silently resolve — the user decides

### Step 7 — flip raw status (flow A only)

- If flow A: in the raw frontmatter:
  - `ingested: true` (or stays `stale` if you only patched a partial diff and more remains — but generally flip to `true` after a successful semantic-diff update)
  - Append the new note's filename to `ingested_in: [...]`

### Step 8 — update index.md

- Add (CREATE) or refresh (UPDATE) the note's entry in `<vault>/index.md` under the right section (Projects / Decisions / Context)
- Format: `- [[note-name]] — <description> (created: YYYY-MM-DD, updated: YYYY-MM-DD) [status if not active]`
- Bump `Last updated:` at top of index.md

### Step 9 — append to log.md

- Format: `YYYY-MM-DD | <source URL or raw path> | <action: created/updated/superseded> <note-name> [+ context if useful]`
- One line per ingest. Append-only.

### Step 10 — git PR (if enabled)

If `<vault>/.vault-config.yml` `git_mode.notes: true`:

```
git fetch origin main
git checkout -b vault-sync/YYYY-MM-DD-<short-slug> origin/main   # always branch off origin/main, regardless of current branch
# (if branch already exists locally → see "Branch reuse / conflict" below; the skill will checkout the existing branch instead of recreating)
git add notes/<note>.md index.md log.md
git add raw/<path>.md                                   # if raw frontmatter changed
git commit -m "ingest: <action> <note-name> from <short source label>"
git push -u origin vault-sync/YYYY-MM-DD-<short-slug>
gh pr create --title "vault-sync: <action> <note-name>" --body "<diff summary + sources>"
```

- `auto_merge: false` always — the user reviews and merges
- One ingest = one commit. Multiple ingests in a session = multiple commits on the same `vault-sync/<date>-<slug>` branch (or separate branches if independent)
- Output the PR URL

If `git_mode.notes: false`: just write to disk and skip the git layer. **Caveat**: without git_mode, an ingest crash mid-write (e.g., after `notes/X.md` written but before `log.md` updated) leaves partial state on disk. Recovery is manual. **Recommendation**: keep `git_mode.notes: true` — branch is local until pushed, partial commits stay isolated, rollback is `git revert` or branch deletion.

**Branch reuse / conflict** — if a branch named `vault-sync/<date>-<short-slug>` already exists locally (previous ingest same day, same topic):
- Local branch only, not pushed → reuse it, add this ingest as a new commit on it
- Pushed and PR open → reuse it, push again, the PR updates
- Pushed and PR merged/closed → fail loud. Tell the user. He decides: rename slug to disambiguate (`<slug>-2`), force-push (don't), or push manually after manual merge resolution. Don't auto-resolve.

## Frontmatter template (note)

```yaml
---
title: <human-readable, Obsidian graph friendly>
type: project | decision | context
status: active | done | superseded | reversed
date: YYYY-MM-DD              # date of first creation
updated: YYYY-MM-DD            # date of this ingest
author: <optional — who proposed/owns this>
team: <optional — team or area>
links: [note-a, note-b]
supersedes: <optional — only if this note replaces a previous decision>
sources: [url-1, url-2]        # origin URLs, always at least 1
raw: [raw/source/file-1.md]    # optional — only if raw captures back this note
---
```

## Body skeleton

```markdown
**Sources**: <label-1>, <label-2>.

[⚠️ Contradiction: <summary> vs [[other-note]]]   ← only if applicable

[TLDR (3-5 lines)]                                ← only if body > ~100 lines

<synthesized content, atomic and dense>

Some claim from one source [^1]. Another claim from elsewhere [^2].

[^1]: <origin URL 1>
[^2]: <origin URL 2>

My position:                                       ← only if the user expressed a stance
[YYYY-MM-DD] <the user's actual stance, never invented>

<!-- obsidian-graph -->
[[linked-note-a]]
[[linked-note-b]]
```

## Edge cases

- **Source unreachable** (404, deleted, MCP not authenticated) → fail loud. If flow A on a stub raw with dead source → flip raw to `ingested: orphan`, do NOT proceed with synthesis. Tell the user.
- **Multiple existing-note candidates** matched (ambiguous) → ask the user explicitly: « I see candidates A and B; which one to update, or create new? » Do not guess.
- **Source contains 2+ atomic ideas** → split into 2+ ingest calls, one per idea. Never bundle.
- **Source = pure logistics** (« we synced », « meeting happened ») → abort, leave raw `ingested: false` with a note in body explaining why no note was made.
- **Existing note violates current schema** (e.g., uses old `source:` singular) → migrate the frontmatter to current schema as part of the update + log it. Do not silently leave it broken.
- **Contradiction the user refuses to resolve** → keep the `⚠️` flag. Don't auto-clear. `/audit-vault` will surface long-standing contradictions.
- **Reverse-link target missing** during integrity check → fail loud. Likely caused by a typo in `links:` or a deleted note.
- **PR creation fails** (gh not authenticated, network) → leave commit on local branch, tell the user to retry `gh pr create` manually. Don't roll back the ingest.
- **`/ingest` invoked on a raw already `ingested: true`** with no new content → fail with explicit message. Use `--force-create` if intentional duplicate.

## Outputs

- One note created or updated in `<vault>/notes/`
- `index.md` updated
- `log.md` appended
- Raw frontmatter updated (flow A: `ingested`, `ingested_in`)
- If `git_mode.notes: true`: a PR URL printed
- Stdout: summary line `<note-path> | <action: created|updated|superseded> | <PR URL or "direct write">`

## Does NOT

- Run anything in parallel — one note per ingest, one ingest at a time. For multiple notes, spawn one agent per note.
- Touch unrelated notes (only the target + its `links:` for coherence checks)
- Auto-resolve contradictions
- Modify old notes' conclusions when superseding
- Re-synthesize entire notes on stale raw — patches only impacted claims (semantic diff)
- Operate from memory — re-reads `CLAUDE.md` every time

## Related

- [/capture](../capture/SKILL.md) — called internally for flow B
- [/fetch-sources](../fetch-sources/SKILL.md) — produces raws that feed `/ingest`
- [/audit-vault](../audit-vault/SKILL.md) — surfaces stale notes, broken links, orphan stubs that may need re-ingest
- Vault schema: `<vault>/CLAUDE.md` — re-read at Step 0 every invocation
