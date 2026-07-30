# Memory layer · schema

The always-loaded **summary** layer of the vault. `bootstrap.sh` symlinks this directory to `~/.claude/projects/<project>/memory/` so Claude Code auto-loads it every session.

Portable by design: plain markdown in git. It is the cheap always-on cache; the DETAIL lives elsewhere.

## What it is

- Compressed, **atomic** summary notes (one fact per file) + `MEMORY.md`, a thin index (one line per memory) loaded every session.
- The retrieval ladder: load the summaries by default, **follow the pointer** to the full note when a task needs the detail. Keeps a large memory cheap to read.

## Relationship to the other layers

- `notes/` = domain/context DETAIL (project / context / decision). `meta/` = harness DETAIL (how your setup works). `feedback/` = behavioral rules.
- `memory/` holds SUMMARIES that **point into** those (`voir [[note-name]]`). Never duplicate a full note here; summarize + link.

## Two kinds of memory

- **`feedback_*`** — a **regenerable projection** of the `feedback/` pillars, owned by `/learn-feedback`. **Never hand-edited**; reconcile is one-directional `feedback/` → memory.
- **`project_*` / `reference_*`** — hand-curated **pointer-summaries** into `notes/` and `meta/`.

## File format

```yaml
name: <short-kebab-slug>
description: <one line — used for relevance-based retrieval>
metadata:
  type: project | reference | feedback
```

Body = the summary (a few lines) + a `[[link]]` to the detail note/doc.

## MEMORY.md

One line per memory: `- [Title](file.md) — hook`. The always-loaded index; never put memory content in it.
