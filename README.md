# Context Vault Template

<p align="center">
  <img src="https://img.shields.io/badge/Status-Early-yellow.svg"/>
  <img src="https://img.shields.io/badge/Updated-2026--04-blue.svg"/>
  <img src="https://img.shields.io/badge/Claude_Code-Anthropic-6B4FBB?logo=anthropic&logoColor=white"/>
  <img src="https://img.shields.io/badge/Markdown-000000?logo=markdown&logoColor=white"/>
  <img src="https://img.shields.io/badge/YAML-CB171E?logo=yaml&logoColor=white"/>
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg"/>
</p>

<p align="center">
  <i>An AI-maintained personal knowledge vault — second brain and code context layer for AI-assisted development</i>
</p>

---

## 📑 Table of Contents

- [📌 About](#-about)
- [🏗️ Architecture](#️-architecture)
- [📁 Project Structure](#-project-structure)
- [✅ Prerequisites](#-prerequisites)
- [🚀 Quick Start](#-quick-start)
- [⚙️ Configuration](#️-configuration)
- [📖 Concepts](#-concepts)
- [🛠️ Skills](#️-skills)
- [🧰 Adapting to Your Context](#-adapting-to-your-context)
- [📝 Related Articles](#-related-articles)
- [📄 License](#-license)

---

## 📌 About

A reusable skeleton for an AI-maintained personal knowledge vault, designed for use with [Claude Code](https://claude.com/claude-code) (or any agentic LLM tool with file system + MCP access).

It serves **two purposes**:

1. **Second brain** — captures the things that matter to you (decisions, tradeoffs, project context, your evolving positions) and lets the AI think, argue, and respond with that context loaded.
2. **Code context for AI-assisted development** — when you work on a codebase, the AI has the business and project context that explains *why* the code is the way it is. Blast radius awareness when refactoring, knowledge of past architectural decisions, and the constraints driving current priorities. Without this, the AI optimizes locally; with it, it aligns with the broader trajectory the team and the business are on.

It is **not** a generic encyclopedia of your company's data (use your existing knowledge tool — Notion, Confluence, Dust, Glean — for that). It is **your** second brain and **your** code context layer: scoped to what concerns you, structured for AI consumption, evolving with your work.

### Tech Stack

| Component | Technology |
|-----------|------------|
| Schema & Docs | Markdown |
| Configuration | YAML |
| AI Runtime | [Claude Code](https://claude.com/claude-code) (or any agentic LLM with file system + MCP access) |
| Source Integrations | Slack & Notion (MCP), GitHub (`gh` CLI), Web (RSS), Meetings (transcripts tool) |
| Optional | Obsidian (graph view of `links:`) |

---

## 🏗️ Architecture

The vault is built around three core concepts and three distinct link axes.

### Core Pipeline

```
   ┌────────────────┐         ┌────────────────┐         ┌────────────────┐
   │    Sources     │ capture │      Raws      │ ingest  │     Notes      │
   │   (external)   │ ──────▶ │  (local cache) │ ──────▶ │ (synthesized)  │
   ├────────────────┤         ├────────────────┤         ├────────────────┤
   │ Slack thread   │         │ Full or stub   │         │ project-       │
   │ Notion page    │         │ Append-only    │         │ decision-      │
   │ GitHub PR      │         │ Triage-pending │         │ context-       │
   │ Web article    │         │                │         │                │
   │ Claude convo   │         │                │         │                │
   └────────────────┘         └────────────────┘         └────────────────┘
                                                                  │
                                                                  ▼
                                                         ┌────────────────┐
                                                         │   index.md     │
                                                         │   (catalog)    │
                                                         └────────────────┘
```

### Three Link Axes

| Axis | Purpose | Direction |
|------|---------|-----------|
| `links:` | Impact / dependency between notes | note ↔ note |
| `sources:` | Traceability at note level | note → origin URL |
| Inline `[^N]` | Traceability at claim level | phrase → origin URL |

---

## 📁 Project Structure

```
context-vault-template/
├── CLAUDE.md                       # Vault schema (rules, frontmatter, ingestion flow)
├── .vault-config.yml.example       # Static config template
├── .vault-state.yml.example        # Dynamic state template
├── .gitignore                      # OS / Obsidian / state files excluded
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
├── audit/                          # /audit-vault reports (artifacts, gitignored)
│   └── README.md
└── skills/                         # 4 operational skills documented as SKILL.md
    ├── capture/
    ├── ingest/
    ├── fetch-sources/
    └── audit-vault/
```

---

## ✅ Prerequisites

| Requirement | Notes |
|-------------|-------|
| [Claude Code](https://claude.com/claude-code) | Or any agentic LLM with file system + MCP access |
| Git | Recommended — versioning gives PR review and rollback via `git revert` on each ingest |
| MCP servers | One per source you want to fetch (Slack, Notion, etc.) |
| Obsidian | Optional — for graph view of inter-note `links:` |

---

## 🚀 Quick Start

This template is **documentation only** — the skills are not pre-installed.

```bash
# 1. Clone or copy this directory as the base for your private vault
git clone https://github.com/TuroTheReal/context-vault-template.git my-vault
cd my-vault

# 2. Bootstrap config files
cp .vault-config.yml.example .vault-config.yml
cp .vault-state.yml.example .vault-state.yml

# 3. Edit .vault-config.yml — fill in your handles, paths, enabled sources

# 4. Make your vault repo private (it will contain personal context)
```

Then:

1. **Read** `CLAUDE.md` — the schema your AI assistant will follow.
2. **Read** the 4 SKILL.md files in `skills/` to understand each verb's behavior.
3. **Implement** the skills as logic (bash / python / your choice). The SKILL.md files are specs — they describe behavior precisely but contain no executable code.

---

## ⚙️ Configuration

Two config files at the vault root.

### `.vault-config.yml` (committed)

Static config: paths, handles, git mode, enabled sources, audit thresholds. Changes rarely.

| Field | Description |
|-------|-------------|
| `vault_path` | Absolute path to the vault directory |
| `user_handle.<source>` | Your handle per source — used in API filters |
| `git_mode.notes` | `true` recommended — opens a PR on each ingest for review and rollback |
| `fetch_sources.<source>` | Boolean per source (Slack, Notion, GitHub, web, meetings) |
| `audit.stale_note_days` | Threshold for stale-note detection (default: 90) |
| `audit.pending_raw_days` | Threshold for pending-raw detection (default: 30) |

### `.vault-state.yml` (gitignored)

Dynamic state: per-source `last_fetch` high-water marks. Auto-updated by `/fetch-sources`.

---

## 📖 Concepts

### Source > Raw > Note Pipeline

Every piece of knowledge in the vault traces back to an external source via this pipeline:

1. **Capture** — `/capture <URL>` archives a source as raw (full for volatile, stub for stable).
2. **Triage** — Decide: ingest into a note, or leave as raw (consultable only).
3. **Ingest** — `/ingest <raw | URL>` synthesizes the source into a typed atomic note.
4. **Audit** — `/audit-vault` flags drift, broken links, schema violations.

### Note Types (decided by content, not title)

| Prefix | When to use | Test |
|--------|-------------|------|
| `project-` | Multi-ticket initiative with team & timeline | "Is this tracking a delivery?" |
| `decision-` | Choice + tradeoff (X over Y because Z) | "Does this capture a WHY?" |
| `context-` | Position, learning, gotcha, org context | (everything else) |

### Raw Types

| Type | For | Behavior |
|------|-----|----------|
| **Full raw** | Volatile sources (Slack, web, Claude conversations, open GitHub PRs) | Full content captured locally, append-only |
| **Stub raw** | Stable sources (Notion, merged GitHub PRs, commits) | Metadata + brief — content stays canonical at the URL |

---

## 🛠️ Skills

Four operational skills, each documented in `skills/<name>/SKILL.md`:

| Skill | Purpose |
|-------|---------|
| [`/capture <URL>`](skills/capture/SKILL.md) | Archive a single source as raw, no synthesis |
| [`/ingest <URL \| raw>`](skills/ingest/SKILL.md) | Synthesize a source into a vault note |
| [`/fetch-sources`](skills/fetch-sources/SKILL.md) | Batch capture across configured sources (idempotent, high-water mark per source) |
| [`/audit-vault`](skills/audit-vault/SKILL.md) | Health check — stale notes, broken links, schema violations |

The `SKILL.md` files are specs (no executable code) — implement them in your stack of choice (bash / python / etc.).

---

## 🧰 Adapting to Your Context

Some opinions are baked in:

- The vault is for **one user**. It captures your perspective, your positions, your projects. Multi-user vaults are out of scope.
- Notes are **atomic** (one idea per note). Long « project README »-style notes are anti-pattern here — split them.
- Synthesis is **factual** — never invent or stylize. If a fact isn't in a source, it doesn't go in a note. The PR review on each ingest is the human safety net against drift.
- `raw/` is **append-only**. Sources of truth are the URLs; raws are local caches. Edits to raws break the audit trail.

The default source list is Slack/Notion/GitHub/web/meetings/claude — you can swap (Discord/Confluence/GitLab/etc.), add or remove sources by:
- Editing `fetch_sources:` in your `.vault-config.yml`
- Adding a `raw/<source>/` folder with `.gitkeep`
- Adding a section in `skills/fetch-sources/SKILL.md` to define the API + filter for that source

### Inspiration

- **Tiago Forte's PARA method** — rejected (too dossier-heavy for this use case)
- **Andrej Karpathy's split between captures and synthesis** — taken (`raw/` vs `notes/` boundary)
- **Zettelkasten** — taken (atomic notes, prefix-typed, flat folder, link by impact)

---

## 📝 Related Articles

- 📝 [My Learning System: Obsidian + Claude](https://arthur-portfolio.com/en/blog/obsidian-claude-learning-system) — The reflection that gave birth to this template: the limit of a generic knowledge vault (« it knows what Terraform is, not how Terraform fits with the rest of the stack »), and the vision of a second vault dedicated to project context.

---

## 📄 License

This project is open source under the **MIT License** — use it, fork it, adapt it.

---

**Last Updated**: 2026-04-29
**License**: MIT
