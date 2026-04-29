# Context Vault Template

A second-brain template for solo knowledge workers, designed for use with [Claude Code](https://claude.com/claude-code) (or any agentic LLM tool with file system + MCP access).

## What this is

A reusable skeleton for an AI-maintained personal knowledge vault. It serves **two purposes**:

1. **Second brain** — captures the things that matter to you (decisions, tradeoffs, project context, your evolving positions) and lets the AI think, argue, and respond with that context loaded.
2. **Code context for AI-assisted development** — when you work on a codebase, the AI has the business and project context that explains *why* the code is the way it is. Blast radius awareness when refactoring, knowledge of past architectural decisions, and the constraints driving current priorities. Without this, the AI optimizes locally; with it, it aligns with the broader trajectory the team and the business are on.

It is **not** a generic encyclopedia of your company's data (use your existing knowledge tool — Notion, Confluence, Dust, Glean — for that). It is **your** second brain and **your** code context layer: scoped to what concerns you, structured for AI consumption, evolving with your work.

## What's inside

```text
context-vault-template/
├── CLAUDE.md                       # Vault schema (rules, frontmatter, ingestion flow)
├── .vault-config.yml.example       # Static config template
├── .vault-state.yml.example        # Dynamic state template
├── .gitignore                      # OS/Obsidian/state files excluded
├── index.md                        # Catalog of notes (empty at bootstrap)
├── log.md                          # Append-only audit trail (empty at bootstrap)
├── notes/                          # Synthesized notes (atomic, typed, sourced)
├── raw/                            # Captured raw sources (full or stub)
│   ├── slack/
│   ├── notion/
│   ├── github/
│   ├── meetings/
│   ├── web/
│   └── claude/                     # Claude conversation captures
└── skills/                         # 4 operational skills documented as SKILL.md
    ├── capture/
    ├── ingest/
    ├── fetch-sources/
    └── audit-vault/
```

## Concepts

The vault has three core concepts. Read `CLAUDE.md` for the full schema.

1. **Sources** are external (Slack threads, Notion pages, GitHub PRs, web articles, Claude conversations). Every note traces back to at least one source URL. No source = no note.

2. **Raws** are local caches of sources. Two flavors:
   - **Full raw** for volatile sources (Slack, web, Claude conversations) — content captured locally, append-only.
   - **Stub raw** for stable sources (Notion, merged GitHub PRs) — metadata + brief, content stays canonical at the URL.

3. **Notes** are atomic, factual summaries with three types: `project-` (initiatives), `decision-` (choice + tradeoff), `context-` (everything else). Strict rule: notes are factual summaries, never invent.

The vault uses **three axes of links**:

- `links:` — impact / dependency (note ↔ note)
- `sources:` — traceability at note level (note → origin URL)
- inline `[^N]` citations — traceability at claim level (phrase → origin URL)

## Skills

Four operational skills, each documented in `skills/<name>/SKILL.md`:

- `/capture <URL>` — archive a single source
- `/ingest <URL | raw>` — synthesize into a note
- `/fetch-sources` — batch capture across configured sources, idempotent (high-water mark per source)
- `/audit-vault` — health check (stale notes, broken links, schema violations)

## How to bootstrap

This template is documentation only — the skills are not pre-installed. To use:

1. **Clone or copy this directory** as the base for your private vault repo.
2. **Copy** `.vault-config.yml.example` → `.vault-config.yml`. Fill in your handles, paths, and which sources you actually use.
3. **Copy** `.vault-state.yml.example` → `.vault-state.yml`. Leave the `last_fetch` values as `null` for the first run.
4. **Read** `CLAUDE.md` — this is the schema your AI assistant will follow.
5. **Read** the 4 SKILL.md files in `skills/` to understand each verb's behavior. They are designed for the Claude Code native skill format.
6. **Implement** the skills as logic (bash / python / your choice). The SKILL.md files are specs — they describe behavior precisely but contain no executable code.
7. **Adapt the source list** to your stack. The default is Slack/Notion/GitHub/web/meetings/claude — you can swap (Discord/Confluence/GitLab/etc.), add, or remove sources by:
   - Editing `fetch_sources:` in your `.vault-config.yml`
   - Adding a `raw/<source>/` folder with `.gitkeep`
   - Adding a section in `skills/fetch-sources/SKILL.md` Sources to define the API + filter for that source
8. **Make your vault repo private** — it contains your personal context, not for sharing.
9. **Decide** on git mode (`git_mode.notes: true` recommended) — gives you PR review before each ingestion lands and rollback via git revert.

## Adapting to your context

Some opinions are baked in:

- The vault is for **one user**. It captures your perspective, your positions, your projects. Multi-user vaults are out of scope.
- Notes are **atomic** (one idea per note). Long « project README »-style notes are anti-pattern here — split them.
- Synthesis is **factual** — never invent or stylize. If a fact isn't in a source, it doesn't go in a note. The PR review on each ingest is the human safety net against drift.
- `raw/` is **append-only**. Sources of truth are the URLs; raws are local caches. Edits to raws break the audit trail.

Feel free to fork the schema if your needs diverge. The template is a starting point, not a constraint.

## Status

This is an early template. It will evolve. Open issues / PRs welcome if you find a structural problem or have a refinement to suggest.

## Inspiration

- Tiago Forte's PARA method (rejected — too dossier-heavy for this use case)
- Andrej Karpathy's split between captures and synthesis (taken — `raw/` vs `notes/` boundary)
- Zettelkasten (taken — atomic notes, prefix-typed, flat folder, link by impact)
