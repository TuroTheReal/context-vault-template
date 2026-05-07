# Vault skills

Operational skills for the context vault. Each skill is documented as a self-contained `SKILL.md` in its own folder, in the native Claude Code format.

This folder is **documentation only** — no install script, no symlinks. If you want to use these skills in your own Claude Code setup, copy them to `~/.claude/skills/<name>/` (user-level) yourself.

## Documented skills

- [capture/](capture/SKILL.md) — archive a single source as raw, no synthesis
- [ingest/](ingest/SKILL.md) — synthesize a source into a vault note
- [fetch-sources/](fetch-sources/SKILL.md) — batch capture across configured sources, writes a daily summary in `digest/`
- [audit-vault/](audit-vault/SKILL.md) — flag stale notes, broken links, schema violations
- [daily-digest/](daily-digest/SKILL.md) — consume the fetch summary + chat live → produce a curated digest (Brief + Inbox) in `journal/`

## Backlog (to document later)

- **`/triage`** — interactive workflow to walk through `ingested: false` raws and decide ingest / skip / mark consultable. Standalone skill (vs flag on `audit-vault`) — to confirm at design time. Useful once raw volume justifies it; manual grep + read works fine until then.
- **`/note`** — to revisit. Likely redundant with `/ingest <conversation source>` — keep an eye on whether a separate verb is needed for source-less reflections.

## Configuration

Two files at the vault root:
- **`.vault-config.yml`** (committed) — static config: paths, handles, git mode, sources enabled, audit thresholds.
- **`.vault-state.yml`** (gitignored) — dynamic state: per-source `last_fetch` high-water marks. Only `/fetch-sources` writes to it.

## Schema reference

Skills follow the vault schema defined in `<vault>/CLAUDE.md`. Re-read it before any ingestion-related action.
