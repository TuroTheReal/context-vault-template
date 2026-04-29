---
name: audit-vault
description: Health check on the vault. Surfaces stale notes, broken links, orphan stubs, schema violations, raws pending triage, and unresolved contradictions. Suggests fixes; never auto-applies.
---

# /audit-vault

Read-only health check across `<vault>/notes/`, `<vault>/raw/`, `<vault>/index.md`. Produces a report. Does NOT modify anything — every flagged item is for the user to action via `/ingest`, manual edit, or explicit decision.

## When to use

- Periodic hygiene (weekly or monthly, your call)
- Before a triage session — get the full picture of what needs attention
- After a schema change — find notes that need migration
- When the vault « feels off » — drift is silent, this surfaces it

## When NOT to use

- To **fix** anything — this skill only reports. Use `/ingest` or manual edits to act on the report.
- For one-off lookups — `grep` is faster.

## Inputs

All optional:

- `--checks <comma-separated>` — limit to a subset. Available: `stale-notes`, `broken-links`, `orphan-stubs`, `schema-violations`, `pending-raws`, `contradictions`, `dead-sources`, `orphan-notes`, `raw-note-coherence`. Default: all.
- `--output <terminal|markdown|both>` — terminal default, markdown writes to `<vault>/audit-report-YYYY-MM-DD.md` (gitignored), `both` does both.
- `--verbose` — include exact file paths and line numbers for every finding (default: summary counts + first few examples per check).

## Configuration read

From `<vault>/.vault-config.yml` (static config):
- `vault_path`
- `audit.stale_note_days` — threshold for « stale note » check (default: 90)
- `audit.pending_raw_days` — threshold for « raw pending too long » check (default: 30)

Does not read `.vault-state.yml` (audit is read-only on the vault content; high-water marks are not relevant for the checks).

## Behavior — high level

```
For each check enabled → grep/read across vault → collect findings → format report → print/write
Never modify any file. The output is action items for the user.
```

## Checks (detailed)

### 1. stale-notes

**What** — notes that claim to be active but haven't been touched in a while. « Is this still true? »

**How** — for each note in `<vault>/notes/` (including `context-` — staleness applies to all types):
- Read frontmatter
- If `status: active` AND `updated:` is older than `audit.stale_note_days` (default 90) → flag

**Why** — silent drift. A note marked active but not refreshed for 6 months is suspect. Either still true (re-confirm + bump `updated:`) or no longer true (update or supersede). `context-` notes are included because « my position » or « my onboarding state » can absolutely become outdated.

**Note — vocabulary** — « stale » here means « note unchanged for too long ». NOT to be confused with raw frontmatter `ingested: stale`, which means « source content evolved after ingest ». Same word, two distinct concepts: note-level vs raw-level.

**Output**: list `<note-path> | last updated: YYYY-MM-DD (X days ago) | title`

### 2. broken-links

**What** — `links:` entries that point to a note that doesn't exist.

**How** — for each note, read frontmatter `links:`. For each entry, check `notes/<entry>.md` exists.

**Why** — typos, deleted notes, renames not propagated. Breaks the impact graph silently.

**Output**: list `<source-note> → <broken-target>`

### 3. orphan-stubs

**What** — stub raws already flagged `ingested: orphan` (source went dead during a previous capture/ingest).

**How** — grep for `ingested: orphan` in `raw/**/*.md`. **No network calls** here — the dead-source detection happens at write-time in `/capture` and `/ingest`. The audit only surfaces what was already flagged.

**Why** — a stub flagged orphan means its source disappeared. Need to decide: leave as historical record, or remove the dead reference from any note that links to it.

**Output**: list `<raw-path> | source: <URL> | dead_at: <date>`. Suggested action: review note(s) in `ingested_in:` and decide.

### 4. schema-violations

**What** — notes or raws that don't conform to the current `CLAUDE.md` schema.

**How** — for each note:
- Has `sources:` list (not `source:` singular)? Has at least 1 entry?
- Has body line `**Sources**: ...` as first content line?
- If 2+ sources in frontmatter → has inline citations `[^N]` in body?
- Frontmatter has all required fields (`title`, `type`, `status`, `date`, `updated`, `sources`)?
- **Format checks**:
  - `date:` and `updated:` match `YYYY-MM-DD` regex
  - `type` is one of `project | decision | context`
  - `status` is one of `active | done | superseded | reversed`
- If `links:` non-empty → has `<!-- obsidian-graph -->` footer
- **Coherence**: every entry in `links:` appears as `[[entry]]` in `<!-- obsidian-graph -->` footer, and vice versa. Divergence = silent typo or oubli.

For each raw:
- Has `type: raw`, `source`, `source_id`, `date`, `captured_at`, `stable`, `ingested`?
- **Format checks**:
  - `date:` and `captured_at:` match expected formats (YYYY-MM-DD, ISO 8601 respectively)
  - `ingested` is one of `false | true | stale | orphan`
  - `stable` is bool
- If `ingested: true` → `ingested_in:` non-empty?
- If `ingested: orphan` → `dead_at:` set?

**Why** — schema evolves; old notes must catch up. Silent violations break tooling assumptions downstream.

**Output**: list `<file> | violation: <description>`. Suggested action: `/ingest --note <file>` (which auto-migrates per current ingest spec) or manual edit for raws.

### 5. pending-raws

**What** — raws sitting in `ingested: false` for too long.

**How** — for each `raw/*/*.md`:
- If `ingested: false` AND `captured_at:` older than `audit.pending_raw_days` (default 30) → flag

**Why** — raws that linger un-triaged are signal that something's off in the workflow (no triage cadence, raws not relevant after all). Forces a decision: ingest or accept-as-consultable-only (still `false`, but a deliberate choice).

**Output**: list `<raw-path> | captured: YYYY-MM-DD (X days ago) | source: <URL>`. Suggested action: triage decision.

### 6. contradictions

**What** — notes that have a `⚠️ Contradiction:` flag in their body.

**How** — grep `^⚠️ Contradiction:` in `notes/*.md`. Report each occurrence with the note path and the contradiction line.

**Why** — these were flagged at ingest time for the user to resolve. They shouldn't linger. Surfacing them keeps the resolution backlog visible.

**Output**: list `<note-path> | <contradiction line>`.

### 7. dead-sources

**What** — notes whose `sources:` URLs were flagged dead by a previous capture/ingest (visible via raws in `raw:` field with `ingested: orphan` and `dead_at:`).

**How** — for each note with `raw:` references → check if any pointed raw is `ingested: orphan`. Flag the note as having a dead source. **No network calls** — dead sources are detected at write-time in `/capture` and `/ingest`, the audit only reads flags.

**Why** — a note whose source is dead loses its truth pointer. Decide: replace source (find an equivalent live one), archive the note, or accept-historical.

**Output**: list `<note-path> | dead source(s): <URL list>`. Suggested action: open the note, decide based on whether the content still holds.

**Note** — sources without an associated raw (e.g., notes ingested before `raw/` existed) are not network-checked. Their staleness can only be detected if the user re-ingests via `/ingest --note <path>` (which will fail loud if the source is dead).

### 8. orphan-notes

**What** — notes that no other note links to AND that don't link to any other note (zero in/out edges in the impact graph).

**How** — for each note: count incoming `links:` references (grep frontmatter) + count outgoing `links:`. If both are 0 → flag. **Excludes `context-` notes** (orphan by design per schema).

**Why** — could be a sign that the note is too isolated / mis-scoped / forgotten. Worth a look.

**Output**: list `<note-path> | type: <type> | title: <title>`.

### 9. raw-note-coherence

**What** — broken cross-references between notes and raws.

**How**:
- For each note's `raw:` entries → verify each path exists in `<vault>/raw/`. Missing → flag (« note X references raw Y which doesn't exist »).
- For each raw with `ingested: true` → verify each entry in `ingested_in:` exists in `<vault>/notes/`. Missing → flag (« raw X claims to be ingested in note Y which doesn't exist »).
- Bidirectional consistency: if note X has `raw: [Y]`, then raw Y should have X in its `ingested_in:`. And vice versa. Asymmetry = stale link.

**Why** — renames, deletions, or manual edits can break the link between a note and its raw cache. The traceability chain breaks silently.

**Output**: list `<file> | broken-ref: <target> | direction: note→raw | raw→note | asymmetric`.

**Suggested action**: re-ingest the note (which rebuilds the link) or manual fix in frontmatter.

## Report format

### Terminal (default) — info-only, scan-quick

The terminal output is a **summary** for fast triage. Counts per check + first 3 examples per finding category. No suggested actions, no exhaustive detail.

```
🔍 Vault audit — 2026-04-28T20:00 — <vault-path>

📊 Summary
  10 notes, 0 raws, 9 sources unique

🚨 Findings
  stale-notes:        2 notes flagged (>= 90 days no update)
  broken-links:       0
  orphan-stubs:       skipped (network)
  schema-violations:  0
  pending-raws:       0
  contradictions:     0
  dead-sources:       skipped (network)
  orphan-notes:       1 note (excl. context-)

📋 First findings (use --output markdown for full report + suggested actions)
  stale-notes:
    - notes/project-cloudflare-migration.md (97 days ago)
    - notes/project-iac-drift.md (97 days ago)
  orphan-notes:
    - notes/project-finops-automation.md
```

### Markdown (`--output markdown`) — info + actions, deep dive

Written to `<vault>/audit/audit-YYYY-MM-DD.md`. The `audit/` folder is committed (so the path is known to anyone who clones), but the `audit-*.md` files inside are gitignored — they're artefacts, not vault content. The compact summary of each run is appended to `log.md` (see "Log entry" below) so git-tracked history exists without keeping the detailed reports.

The markdown report contains:

- Same summary as terminal
- **All** findings (not just first 3 per category)
- **Suggested action** for every finding, with the exact command or decision needed

Example markdown excerpt:

```markdown
## stale-notes (2 findings)

### notes/project-cloudflare-migration.md
- Last updated: 2026-04-21 (97 days ago)
- Status: active
- **Suggested action**: `/ingest --note notes/project-cloudflare-migration.md` to refresh from current source, or update `status:` to `done` / supersede if outdated.

### notes/project-iac-drift.md
- Last updated: 2026-04-21 (97 days ago)
- Status: active
- **Suggested action**: same as above. Cross-check with linked notes (project-cloudflare-migration) for consistency.
```

Usage:
- Run `--output markdown` (or `--output both`) for a full review session
- `--output terminal` (default) when you just want a quick health pulse
- The dated file lets you track audit history: are issues being resolved, or piling up?

## Edge cases

- **Empty vault** (0 notes, 0 raws) → quick run, all checks return 0 findings, no error.
- **No network calls** in this skill — orphan-stubs and dead-sources checks read flags posted by `/capture` and `/ingest`. So no transient-network handling needed.
- **Custom `audit.stale_note_days` set very low** (e.g., 7) → most notes flagged. Not a bug — just adjust threshold or run with explicit `--checks` exclusion.
- **Schema check finds violation in a `superseded` note** → flag but lower priority. Superseded notes are frozen by design; migration is optional.
- **Very large vault** (1000+ notes) → some checks become slow. Reco: run nightly via cron, write markdown report, review in the morning. Or limit with `--checks`.
- **Asymmetric raw↔note refs** (raw-note-coherence check) → most often caused by renames or manual edits. Don't auto-fix — the user decides whether to re-ingest, manually patch, or ignore (e.g., if the raw was deliberately dropped).

## Outputs

- Terminal report (default)
- Optional markdown report at `<vault>/audit/audit-YYYY-MM-DD.md` (gitignored)
- One-line summary appended to `<vault>/log.md` (always, regardless of `--output`)
- Exit code: 0 if no findings, non-zero if any check found issues. Useful for cron/CI integration.

## Log entry

Always append one compact line to `<vault>/log.md` per run, even though this skill is read-only on note/raw content. Logging the audit run itself is meta-history (« audit ran on date X with Y findings ») which is useful for tracking vault hygiene over time without keeping every detailed report.

Format:

```text
YYYY-MM-DD | audit-vault | <N total findings>: stale-notes=X broken-links=X orphan-stubs=X schema-violations=X pending-raws=X contradictions=X dead-sources=X orphan-notes=X raw-note-coherence=X
```

If `--dry-run` (no real audit, no markdown report): also skip the log line. The log captures real runs only.

## Does NOT

- Modify any note or raw file in the vault
- Open PRs (read-only operation on content, no commits)
- Decide what to do with findings — the user decides
- Fetch new content (it's an audit, not a refresh — use `/fetch-sources` for that)
- Run all checks if `--checks` is specified — only the listed ones

The skill DOES write its own report to `audit/` and one line to `log.md` — these are audit-trail outputs, not vault-content modifications.

## Cron mode (later)

When ready, schedule weekly via:
- macOS `launchd`: fire `claude -p "/audit-vault --output markdown"` on Sunday morning
- Read the markdown report over coffee, action items in mind for the week

The high-water mark from `/fetch-sources` and the audit report from `/audit-vault` are the two main signal sources for keeping the vault healthy on autopilot.

## Related

- [/ingest](../ingest/SKILL.md) — used to act on stale notes / schema violations
- [/capture](../capture/SKILL.md) — used to refresh dead sources
- [/fetch-sources](../fetch-sources/SKILL.md) — feeds raws that this audit then surfaces as `pending-raws`
- Vault schema: `<vault>/CLAUDE.md`
