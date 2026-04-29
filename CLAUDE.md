# Context Vault — Schema

AI-maintained knowledge base. The user feeds sources, AI structures and maintains.
A wrong note is WORSE than no note — false context, wasted time, compounding errors. Accuracy > speed.

**Purpose**: two objectives.

1. Second brain — AI can think, argue, and respond as the user (positions, reasoning, tradeoffs, context).
2. Code context — when coding, AI has project constraints, dependencies, and blast radius awareness from the vault.

## Skills (operational tooling)

The vault is operated via 4 user-level skills. Full SKILL.md files live in `skills/`. This is just a pointer.

- **`/capture <URL>`** — archive a source as raw (full content for volatile sources, stub for stable ones). No synthesis.
- **`/ingest <URL | raw-file>`** — synthesize into `notes/`. Runs `/capture` internally if given a URL. On stub raw, does a live fetch of the source.
- **`/fetch-sources [--since DATE]`** — batch capture across configured sources (Slack/Notion/GitHub/...). Manual at first, cron later. Uses high-water mark per source.
- **`/audit-vault`** — flags stale notes, broken links, orphan stubs, schema violations, raws pending triage. Writes detailed reports to `<vault>/audit/audit-YYYY-MM-DD.md` (gitignored) and one compact line to `log.md` per run. Suggests cleanups; never auto-applies.

Skills read two config files at the vault root:

- **`.vault-config.yml`** (committed) — static config: paths, handles, git mode, sources enabled, audit thresholds. Changes rarely.
- **`.vault-state.yml`** (gitignored) — dynamic state: per-source `last_fetch` high-water marks. Auto-updated by `/fetch-sources`.

## What to capture / what NOT to

Capture: decisions & tradeoffs, project state, non-documented learnings, blast radius context.
Don't capture: technical concepts you can find in docs, code (read the code), live ticket status (ticket tracker is authoritative), documented processes (live in their canonical location).

### Content > event rule

Capture the CONTENT, not the event.

- "X and Y synced on topic Z" → raw only (logistics, no density)
- "Decision: migrate to system A because cost" → note (content, tradeoff)
- "Meeting M happened" → raw only
- "Position of P on topic T" → note

If an event has no decision / position / tradeoff / learning attached, it stays in raw. Never promote logistics to notes.

## Note format

All notes in English (or your language of choice — pick one and stick to it). One note = one atomic idea. Flat in `notes/`, prefixed by type.
If note > ~100 lines, add TLDR (3-5 lines) at top.
No source URL = no note.

Mention source(s) in the first line of the body (before TLDR / content). Format: `**Sources**: <short human label>, <short human label>`. Full URLs live in frontmatter `sources:`.

**Notes are factual summaries. Never invent, infer beyond the source, or stylize for effect.** Every claim in a note must trace to a source (its `sources:` URL or a citation). If a fact is not in the source, it doesn't go in the note. This rule applies to all notes — `project-`, `decision-`, `context-` — not just `My position:` (which has a stricter version of this rule).

### Prefixes — decide by CONTENT, not title

Read the source content deeply before choosing a type. Never type from title alone.

- `project-` → multi-ticket initiative (has team, timeline, deliverables). Test: "is this tracking a delivery?"
- `decision-` → choice + tradeoff (X chosen over Y, with reasons). Test: "does this capture a WHY?"
- `context-` → everything else (position, learnings, gotchas, org context)

Other prefixes (person-, area-) only when referenced in 5+ notes.

### Frontmatter template

```yaml
title: [human-readable, Obsidian graph friendly]
type: [project|decision|context]
status: [active|done|superseded|reversed]
date: YYYY-MM-DD
updated: YYYY-MM-DD
author: [optional — who proposed/owns this]
team: [optional — team or area name]
links: [note-a, note-b]
supersedes: [optional — only if replacing a previous decision]
sources: [url-1, url-2]         # origin URLs (Slack, Notion, GitHub, web, etc.). Always at least 1.
raw: [raw/source/file-1.md]     # optional — local raw captures backing this note
```

`sources:` is the truth: origin URLs (Slack thread, Notion page, GitHub PR, web article). Always present, at least one entry.
`raw:` is optional: local files in `raw/` that cache these sources. Only present if raw captures exist for this note.

### Links — three distinct axes

Each axis answers a different question. Don't mix.

1. **`links:` (impact/dependency)** — what does this note IMPACT?
   - Note ↔ note relation. "This decision affects this project." "This project depends on this decision."
   - Same topic ≠ link. No orphan links (target must exist).
   - `context-` notes (user's position etc.) = pure background. Never link them to projects/decisions — everything in this vault concerns the user by definition.
   - Body: plain text, no `[[links]]`. End every note with `<!-- obsidian-graph -->` section mirroring frontmatter links as `[[note-name]]` (Obsidian only, AI ignores).

2. **`sources:` (traceability, note-level)** — where does this note COME FROM?
   - Note → origin URL(s). Always present.
   - Use raw file paths in `raw:` only as an additional cache, never as a replacement for the origin URL.

3. **Inline citations `[^N]` (traceability, claim-level)** — which FACT comes from which source?
   - Only on notes aggregating 2+ sources. Atomic single-source notes don't need inline citations.
   - Footnote target = origin URL (Slack thread, Notion page, etc.), not the raw file.
   - Example:

     ```text
     Data team chose system A [^1]. Cost ~30% lower on their volume [^2].

     [^1]: slack://channel/C0ABC/p1745395200000
     [^2]: https://example.notion.so/eval-abc123
     ```

## Raw folder

`raw/` is a local cache of captures from external sources. Purpose: offload "I'm not sure yet if this deserves a note" to a space the AI can still grep, without polluting `notes/` density. **Only for volatile sources** — see rule below.

### Two raw types: full vs stub

The raw format depends on source volatility.

- **Full raw (volatile sources)**: Slack messages/threads, Discord messages, Claude conversations, web articles, GitHub open PRs/issues. Captures the **complete content** because the source can be edited, deleted, or lost. Format: full body in markdown.
- **Stub raw (stable sources)**: Notion pages (or equivalent stable wiki), GitHub commits or merged/closed PRs. Captures **only metadata + brief** (title, URL, modified date, 1-line summary of what changed). The source content stays canonical at the URL — no duplication. Marked with `stable: true` in frontmatter.
- **In doubt → full raw**. Cheap upfront, costly to recreate after source disappears.

Both types live in `raw/` and follow the same structure (`raw/<source>/YYYY-MM-DD-*.md`). Both are scannable, both have `ingested:` lifecycle. The stub is just shorter.

### Why stub raw exists

`/fetch-sources` (auto/manual) needs to surface stable sources too — otherwise a Notion page modification or new GitHub PR would go unnoticed. The stub is the trace that "this source surfaced and deserves triage", without duplicating its content.

When `/ingest <stub-raw>` runs, the skill does a **live fetch** of the source URL at that moment (not from the stub) before synthesizing the note. Stub stays as the audit trail of when the source was first detected.

### Structure

Organize by source type. The exact source list depends on the user's environment — adapt freely.

```text
raw/
  slack/    2026-04-23-<channel-or-dm>.md       (or discord/, teams/, etc.)
  notion/   2026-04-23-<page-id-or-slug>.md     (or confluence/, hackmd/, etc.)
  github/   2026-04-23-pr-<num>.md              (or gitlab/, bitbucket/, etc.)
  meetings/ 2026-04-23-<topic>.md               (transcripts or manual notes)
  web/      2026-04-23-<domain>-<slug>.md
  claude/   2026-04-23-<topic>.md               (Claude/LLM conversation captures)
```

File naming: `YYYY-MM-DD-<short-hint>.md`. One raw file = one capture = one origin.

Archiving (> 1 year old, ingested) is deferred — to be reconsidered when volume grows.

### Raw frontmatter

```yaml
type: raw
source: <origin URL>                 # singular: 1 raw = 1 source
source_id: <stable unique id>        # thread_ts, page_id, pr_number — used for dedup
date: YYYY-MM-DD
captured_at: YYYY-MM-DDTHH:MM:SSZ
modified_at: [optional]              # source's last-modified date, when known (Notion, GitHub)
title: [optional — for stub raws, helps triage at a glance]
author: [optional]
channel: [optional — slack/notion/etc. context]
stable: false                        # true if stub raw (stable source, brief only — no content duplicated)
ingested: false                      # false | true | stale | orphan
ingested_in: [decision-xyz.md]       # reverse lookup, filled when ingested
```

### Raw rules

- Append-only. Never delete a raw file. Never rewrite captured content. New content from re-fetch = appended at the end with a separator.
- Dedup by `source_id`: 1 source ID = 1 raw file across all time. Re-fetching the same source updates that file (append), never creates a duplicate.
- A raw captures the CONTENT, not the logistics. If all you have is "meeting happened", skip — nothing to cache.
- Scope = what concerns the user (same filter as notes). Not generic company data (that's what your company's general-knowledge tool covers, if any).
- `ingested:` values:
  - `false` = not yet synthesized → to triage. Triage can conclude "make a note" OR "leave as raw, consultable only".
  - `true` = synthesized in `notes/`, raw matches the version that was ingested.
  - `stale` = was ingested, but source has since evolved (new content appended). Note may be outdated → re-check before next ingest.
  - `orphan` = stub raw whose source is no longer reachable (404, page deleted). The associated note (if any) keeps its content but the source URL is dead. `/audit-vault` flags these so the user decides: leave as historical record or remove the dead link.

## Ingestion

**Before every ingestion: re-read this schema.** Not from memory — actually read the file.

One note per ingestion. For 2+ notes: spawn one agent per note (model: opus, thinking: on, effort: max). Never batch-process in a loop.

### Two entry flows

- **Flow A — from raw**: `/ingest raw/slack/2026-04-23-data-team.md` → synthesize → flip raw `ingested: true` + fill `ingested_in:`
- **Flow B — direct**: `/ingest <origin URL>` (Slack, Notion, GitHub, web, or "this conversation") → synthesize, no raw file created

Both flows converge on the same synthesis steps below.

### Steps

1. Analyze source content thoroughly → determine type (by content, not title) and links (impact/dependency only)
2. Read index.md
3. Create/update note in notes/:
   - Frontmatter: always fill `sources:` (origin URLs), fill `raw:` if flow A, set `updated:` to today
   - Body first line: `**Sources**: <short human label>, ...` (mandatory, mirrors frontmatter sources for human scan)
   - Inline citations `[^N]` if 2+ sources
4. Grep reverse links across all notes/ frontmatter
5. Read impacted notes → check coherence
6. If contradiction → add `⚠️ Contradiction: X vs Y in [[other-note]]` at top of note body, let the user decide
7. If flow A: flip raw `ingested: true`, fill `ingested_in:`
8. Update index.md
9. Append to log.md

## User's position

When the user expresses a stance on a topic, add a `My position:` section at the end of the relevant note (before obsidian-graph). If no note exists, create one first (respect ingestion flow + dependencies).

Format — each entry prefixed with date, never delete old entries:

```text
My position:
[2026-04-21] Leaning towards X because Y.
[2026-05-10] Changed to Z — new data from W invalidated previous reasoning.
```

Sources: conversation, Slack messages, GitHub discussions, PR reviews.
Do NOT invent or infer — only capture what the user actually said.

## Update vs create

Default rule: **same atomic idea = update; new atomic idea = create**. Never bundle two ideas into one note.

### When to UPDATE an existing note

- New context, clarification, or detail on the same project/decision/position → append to the note, bump `updated:`
- User expresses a new stance on the topic → append a new dated entry under `My position:` (never delete old entries)
- A linked source (raw `stale`) has evolved → re-ingest with **semantic diff** (see below)
- Sub-decision inside a tracked project → can be inline in the project note as a sub-section, or split into its own `decision-` note if it has a meaningful tradeoff. Use judgment.

### When to CREATE a new note

- New decision with its own tradeoff (X chosen over Y because Z) → new `decision-` note + `links:` to impacted notes
- New project (multi-ticket initiative with team/timeline) → new `project-` note
- New context dimension (org structure, learning area not yet covered) → new `context-` note
- Reversing a previous decision → new `decision-` note with `supersedes: [old-note]`, old note `status: superseded`. **Never modify old conclusions.**

### Semantic diff on stale raw

When `/ingest` runs on a raw flagged `stale` (full or stub):

- Read the existing note tied to that raw (`ingested_in:`)
- Read the new content (appended portion of the raw, or live fetch for stub)
- Identify which **claims** in the note are affected by the new content
- Update only those claims + add new claims for genuinely new information
- Bump `updated:`, flip raw `ingested: true`
- **Do NOT re-synthesize the whole note from scratch** — preserves nuances the user already validated

## Usage — responding as the user

When using this vault to respond on the user's behalf or inform decisions:

- "My position:" entries = the user's actual stance. Use them. Cite the date — recent > old.
- No position on a topic = say so. Never infer or fabricate a stance.
- If positions evolved over time, reflect the latest but mention the shift.
- Project notes give constraints and blast radius — use them when coding or reviewing.
- When uncertain whether the user would agree: flag it, don't guess.

## Rules

- Session start: read index.md first
- Never delete/modify core conclusions without approval
- Adding links, status updates, appending context = OK without approval
- Always log to log.md after any modification
- Use grep for reverse links, no separate index
- Do NOT silently resolve contradictions — flag and let the user decide
- `raw/` is append-only. Never delete a raw file, only flip `ingested:`
- Every note has at least one `sources:` entry (origin URL). No exception.
- AI scans both `notes/` and `raw/` by default when retrieving context.
