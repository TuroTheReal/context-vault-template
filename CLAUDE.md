# Context Vault — Schema

AI-maintained knowledge base. The user feeds sources, AI structures and maintains.
A wrong note is WORSE than no note — false context, wasted time, compounding errors. Accuracy > speed.

**Purpose**: two objectives.

1. Second brain — AI can think, argue, and respond as the user (positions, reasoning, tradeoffs, context).
2. Code context — when coding, AI has project constraints, dependencies, and blast radius awareness from the vault.

## Detailed schema → SCHEMA.md

Frontmatter templates, the tag taxonomy, link axes, author attribution, the raw folder, ingestion steps, and update-vs-create live in `<vault>/SCHEMA.md`. Read SCHEMA.md before any capture / ingest / audit / digest.

## Skills (operational tooling)

The vault is operated via 4 user-level skills. Full SKILL.md files live in `skills/`. This is just a pointer.

- **`/capture <URL>`** — archive a source as raw (full content for volatile sources, stub for stable ones). No synthesis.
- **`/ingest <URL | raw-file | digest-summary>`** — synthesize into `notes/`. Runs `/capture` internally if given a URL. On stub raw, does a live fetch of the source. Can also synthesize a fetch-summary in `digest/` (e.g. weekly synthesis).
- **`/fetch-sources [--since DATE] [--summary brief|full|none]`** — batch capture across configured sources (Slack/Notion/GitHub/Linear/GH Discussions/...). Writes a single dated summary file to `<vault>/digest/<date>-fetch-summary.md` (append intra-day). Manual at first, cron later. Uses high-water mark per source.
- **`/daily-digest [--since DATE]`** — consume the fetch-summary in `digest/` + chat live re-pull → produce a curated digest (Brief + Inbox) in `<vault>/journal/<date>-digest.md` (append intra-day). Mechanical generation, zero meta-commentary.
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

**Notes are factual summaries. Never invent, infer beyond the source, or stylize for effect.** Every claim in a note must trace to a source (its `sources:` URL or a citation). If a fact is not in the source, it doesn't go in the note. This rule applies to all notes — `project-`, `decision-`, `context-` — not just `My position:` (which has a stricter version of this rule).

Frontmatter template, author attribution, the tag taxonomy, link axes, and inline-citation detail live in `<vault>/SCHEMA.md`.

### Prefixes — decide by CONTENT, not title

Read the source content deeply before choosing a type. Never type from title alone.

- `project-` → multi-ticket initiative (has team, timeline, deliverables). Test: "is this tracking a delivery?"
- `decision-` → choice + tradeoff (X chosen over Y, with reasons). Test: "does this capture a WHY?"
- `context-` → everything else (position, learnings, gotchas, org context)

Other prefixes (person-, area-) only when referenced in 5+ notes.

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

## Usage — responding as the user

When using this vault to respond on the user's behalf or inform decisions:

- "My position:" entries = the user's actual stance. Use them. Cite the date — recent > old.
- No position on a topic = say so. Never infer or fabricate a stance.
- If positions evolved over time, reflect the latest but mention the shift.
- Project notes give constraints and blast radius — use them when coding or reviewing.
- When uncertain whether the user would agree: flag it, don't guess.

## Rules

- Session start: read index.md first
- Before every ingestion: re-read CLAUDE.md + SCHEMA.md. Not from memory, actually read the files.
- Never delete/modify core conclusions without approval
- Adding links, status updates, appending context = OK without approval
- Always log to log.md after any modification
- Use grep for reverse links, no separate index
- Do NOT silently resolve contradictions — flag and let the user decide
- `raw/` is append-only. Never delete a raw file, only flip `ingested:`
- Every note has at least one `sources:` entry (origin URL). No exception.
- AI scans both `notes/` and `raw/` by default when retrieving context.
