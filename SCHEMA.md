# Context Vault Schema, detailed reference

Companion to CLAUDE.md (lean core). Read before any capture / ingest / audit / digest. Never operate from memory.

## Note format (detail)

### Author attribution — explicit only

Set `author:` in the frontmatter **only when the source explicitly identifies an owner / author**. Acceptable signals:

- Notion page property `Created by` or in-body line like `**Owner:** <Name>` / `Author: <Name>`
- Slack message: the actual `from` of the message
- GitHub PR / issue: the `Author:` field
- Meeting note: the explicit author of the prep doc (not "the meeting happened with X" — that's a participant, not an author)

**Never infer** from « X is owner of the parent project » or « X is the most-cited person in the body ». Those are guesses, not attribution. If the source doesn't say who wrote it, leave `author:` empty.

Same rule for `My position:` entries: only capture what the user actually said in a source where the user is identified as the speaker. Never attribute to the user a "we said" / "we discussed" from a page in another team's space.

Mention source(s) in the first line of the body (before TLDR / content). Format: `**Sources**: <short human label>, <short human label>`. Full URLs live in frontmatter `sources:`.

### Frontmatter template

```yaml
title: [human-readable, Obsidian graph friendly]
type: [project|decision|context]
status: [active|done|superseded|reversed]
tags: [topic/<domain>, people/<name>, ...]   # controlled taxonomy — see « Tags » below. Uncertain → omit, never guess.
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

### Tags — controlled taxonomy

`tags:` is a flat list in the frontmatter, optimized for AI retrieval + Obsidian nested-tag graph. **Closed vocabulary — never invent a tag. If a dimension is uncertain, OMIT it (or mark `TBD`), never guess.** A tag must trace to the note's real content, same faithfulness rule as every claim.

- `topic/<domain>` — the primary subject (e.g. `topic/billing`, `topic/infra`, `topic/security`). Keep a short closed list of your real domains; extend only when 3+ notes need a genuinely new one.
- `people/<name>` — people who are **actors** of the note (decider, source, position-holder), not passing mentions. Lowercase first name (e.g. `people/alex`).
- `country/<code>` — only when a country is the **subject**, not an incidental mention (e.g. `country/fr`).
- `kind/<nature>` — `position` (note carries a `My position:` stance), `onboarding` (handover / ramp-up context).

Multiple tags per axis are fine. When a note has no confident tag on an axis, leave that axis out entirely.

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
ingested: false                      # false | true | stale | orphan | rejected
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
  - `rejected` = reviewed by `/ingest`, decided NOT to promote to a note. Reason in body (`<!-- Ingest decision: ... -->`). Common cases: logistics-only meeting, generic technical learning belonging in a personal techno vault, no domain-specific decision/position/tradeoff. `/audit-vault` excludes `rejected` from pending-triage list.

## Ingestion

**Before every ingestion: re-read CLAUDE.md + SCHEMA.md.** Not from memory — actually read the files.

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
