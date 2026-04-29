---
name: fetch-sources
description: Batch capture across all configured sources (Slack, Notion, GitHub, web, ...). Surfaces what's new since last run, deposits raws for triage. Manual at first, cron later.
---

# /fetch-sources

Sweep all enabled sources in `<vault>/.vault-config.yml`, capture what's new since the last sweep, deposit raws into `<vault>/raw/`. Does NOT synthesize — `/ingest` and triage are separate steps.

## When to use

- End of day / week — you want « what surfaced about me since I last looked »
- Before a triage session
- Cron job at 20:00 (when set up later)
- After being away — `--since 2026-04-20` to catch up a gap

## When NOT to use

- You know exactly which source you want — use `/capture <URL>` directly
- You want to ingest now — `/fetch-sources` doesn't synthesize

## Inputs

All optional:

- `--since <YYYY-MM-DD | ISO datetime>` — override the per-source high-water mark, force fetch from that point
- `--until <YYYY-MM-DD | ISO datetime>` — cap the fetch at that point (default: now)
- `--sources <comma-separated>` — limit to a subset (e.g. `--sources slack,notion`). Default: all sources with `fetch_sources.<type>: true` in config
- `--dry-run` — list what would be fetched without writing any raw

## Configuration read

From `<vault>/.vault-config.yml` (static config):
- `vault_path`
- `user_handle.<source>` — handles used in API filters
- `fetch_sources.<type>` — boolean per source type (enabled or not)
- Source-specific config (`notion.tracked_databases`, `web.feeds`, etc. — see Sources section below)

From `<vault>/.vault-state.yml` (dynamic state, gitignored):
- `last_fetch.<type>` — high-water mark ISO timestamp per source (the « since » to use if no `--since` flag)

Writes to `<vault>/.vault-state.yml` at the end of a successful run (atomic write — temp file + rename). Never writes to `.vault-config.yml`.

## Behavior — high level

```
Resolve since/until per source → for each enabled source: query API, filter what concerns the user,
delegate each new item to /capture → on full success, update last_fetch per source.
```

## Behavior — precise steps

### Step 0 — re-read schema + acquire lock

- Read `<vault>/CLAUDE.md` (raw + scope sections). Same rule as `/ingest` — never operate from memory.
- **Acquire file lock**: create `<vault>/.vault-state.yml.lock` with current PID. If lock already exists with a live PID → fail loud (« another fetch-sources is running, PID X »). If stale lock (PID dead) → take over and warn. Release lock on exit (success or failure). Prevents concurrent runs from corrupting `last_fetch` writes.

### Step 1 — resolve fetch window per source

For each enabled source `S`:
- `since[S]` = `--since` flag if provided, else `last_fetch[S]` from `<vault>/.vault-state.yml`. **No magic default**: if `last_fetch[S]` is absent (null) and `--since` is not given, fail loud and ask the user to provide `--since <date>` for that source. The whole mechanism is « pick up where we left off »; the bootstrap point is a deliberate choice, not a guess.
- `until[S]` = `--until` flag if provided, else `now`
- If `since[S] >= until[S]` → no-op for this source
- **Window safety check**: if `(until[S] - since[S]) > 45 days` (covers vacation + margin) → ask the user for confirmation before fetching. Print « window for <S> = N days, that's a lot, confirm? ». Default to abort if no confirmation. Prevents accidental massive fetches that hit rate limits.

### Step 1b — pause-resume detection

If a source was just re-enabled (`fetch_sources.<S>: true` after being `false` for a while) and `last_fetch[S]` is far in the past (more than 45 days ago), warn the user explicitly: « source <S> was paused, last_fetch is N days old. Fetching the gap may hit API rate limits or surface stale items. Pass `--since` if you want a different bootstrap point. » Same 45-day threshold as the window safety check.

### Step 2 — for each source, query and filter

The « what concerns the user » filter must be **deterministic and API-driven**, not an AI judgment. Each source's filter is a set of API query parameters (mentions, assignee, author, channel allowlist, etc.) — see Sources section. The filter is reproducible: the same window + same config gives the same set of items every time.

Iterate over enabled sources. For each:
- Query the source API for items modified/created in `[since, until]`, using the deterministic filter (e.g., Slack `mentions=@your.handle`, GitHub `author:your-github-username OR review-requested:your-github-username`)
- Apply the « content > event » filter: skip pure logistics (« meeting scheduled with no agenda », « ticket created with no description »). This is a structural filter (empty body, < N chars), not a semantic judgment.
- For each surviving item → call `/capture <URL>` (it handles dedup, full vs stub, append on update)

**Never** let the AI subjectively decide « this concerns the user » or « this is logistics ». The filter is config-driven, deterministic, replayable.

### Step 3 — collect outcomes

Per source, count: items found, items captured (new), items appended (re-capture), items skipped (logistics or empty), items failed.

### Step 4 — update high-water mark

**Only if the source's run completed without fatal error**:
- Set `last_fetch[S] = until[S]` in `<vault>/.vault-state.yml`
- Atomic write — temp file + rename to avoid partial update on crash

**Failure model**: if Slack succeeds but Notion fails halfway, only `last_fetch.slack` is updated. Next run retries Notion from its old high-water mark. Nothing is lost, no duplicate captures.

### Step 5 — append to log.md

One line per source run:
```
YYYY-MM-DD | fetch-sources <source> [<since> → <until>] | <N captured>, <M appended>, <K skipped>, <F failed>
```

If `--dry-run`: skip log.md, just print what would happen.

### Step 6 — print summary

```
fetch-sources summary (2026-04-28T20:00 → 2026-04-28T20:03):
  slack:  12 captured, 3 appended, 5 skipped (logistics), 0 failed
  notion: 4 captured (stubs), 1 appended, 2 skipped (not relevant), 0 failed
  github: 2 captured (stubs), 0 appended, 1 skipped, 0 failed
  web:    0 captured (no new RSS items), 0 failed
last_fetch updated for: slack, notion, github, web

→ 18 new items pending triage. Use /audit-vault to list, or /ingest <raw-path> to process.
```

## Sources

### Slack

**Concerns the user filter**:
- DMs to/from the user
- Mentions of `@<your-handle>` in any channel
- Messages in channels the user has actively posted in (proxy for « channels he cares about »)
- Threads where the user posted (track replies even if no @mention)

**API**: Slack MCP server. Auth check at Step 0.

**Source type**: volatile → full raw via `/capture`.

**Per-item URL**: `slack://channel/<channel_id>/p<thread_ts>`.

### Notion

**Concerns the user filter**:
- Pages where the user is mentioned
- Pages the user has edited or commented on
- Pages in spaces / databases the user explicitly tracks (config: `notion.tracked_databases: [...]`)

**API**: Notion MCP. Auth check at Step 0.

**Source type**: stable → stub raw via `/capture` (metadata + brief, no content duplication).

**Per-item URL**: `https://www.notion.so/<page_id>`.

### GitHub

**Concerns the user filter** (deterministic API queries):
- `gh search prs --author=your-github-username --state=all --updated=">=<since>"`
- `gh search prs --review-requested=your-github-username --state=all --updated=">=<since>"`
- `gh search issues --assignee=your-github-username --updated=">=<since>"`
- `gh search issues --mentions=your-github-username --updated=">=<since>"`

**API**: `gh` CLI (already authenticated via `gh auth`).

**Source type per item**:
- **Open PR / open issue** → **volatile** → full raw via `/capture` (content evolves: comments, edits, force-pushes)
- **Merged / closed PR / closed issue** → **stable** → stub raw via `/capture` (immutable from this point)
- **Commit** → stable → stub

**Per-item URL**: `https://github.com/<owner>/<repo>/pull/<num>` for PRs, etc.

### Web (RSS / explicit list)

**Concerns the user filter**: only sources the user has explicitly opted into (config: `web.feeds: [<rss_url>, ...]`). No generic crawl.

**Source type**: volatile → full raw (web pages can vanish, get edited).

**Per-item URL**: the article URL.

### Meetings (transcripts tool — placeholder)

Disabled by default (`fetch_sources.meetings: false`) until the transcripts tool is set up. When enabled:
- Pull transcripts of meetings where the user was a participant
- Source type: volatile → full raw (transcripts are not durably accessible elsewhere)

### Claude conversations

NOT auto-fetched. Captured on demand via `/capture claude://current` during/after a session. `fetch-sources` doesn't sweep these.

## Configuration

Static config lives in `<vault>/.vault-config.yml` (committed). State lives in `<vault>/.vault-state.yml` (gitignored, auto-updated by this skill).

`.vault-config.yml` (relevant fields):

```yaml
user_handle:
  slack: "@your.handle"
  github: "your-github-username"
  notion: "Your Name"

fetch_sources:
  slack: true
  notion: true
  github: true
  web: false
  meetings: false

notion:
  tracked_databases: []

web:
  feeds: []
```

`.vault-state.yml` (auto-updated):

```yaml
last_fetch:
  slack: 2026-04-27T20:00:00Z
  notion: 2026-04-27T20:00:00Z
  github: 2026-04-27T20:00:00Z
  web: null
  meetings: null
```

## Edge cases

- **MCP server not authenticated** for a source → fail that source loudly, **do NOT** update its `last_fetch`. Continue with other sources. Tell the user to authenticate.
- **API rate limit hit** → stop the source mid-run, do NOT update `last_fetch`. Next run resumes. Print « partial run, last_fetch not advanced ».
- **Source returns nothing new** → not an error. Update `last_fetch` to `until`, log « 0 new items ».
- **First run, no `last_fetch[S]`, no `--since`** → fail loud with explicit message: « no high-water mark for source X, pass `--since <date>` to bootstrap ». Don't pick an arbitrary default — the bootstrap window must be the user's choice.
- **Clock skew / `since > until`** → no-op for that source, log a warning.
- **`/capture` fails on one item** → log the failure, continue with the rest of the items in that source. The source's `last_fetch` is updated only if the **majority** succeeded — partial failures are surfaced in the summary, not silently swallowed.
- **Same item already captured by manual `/capture` earlier** → `/capture` dedup by `source_id` handles it (skip or append). `fetch-sources` doesn't need special logic.
- **`--dry-run`** → never touches disk or config. Useful before an automated run to estimate volume.

## Outputs

- N raws written to `<vault>/raw/<source>/`
- `<vault>/.vault-config.yml` updated (`last_fetch` per source that ran)
- `<vault>/log.md` appended (one line per source run)
- Stdout: summary block (see Step 6)
- Exit code: 0 if all enabled sources completed; non-zero if any source failed fatally

## Does NOT

- Synthesize anything into `notes/` (that's `/ingest`)
- Decide what's note-worthy (that's triage / `/ingest`)
- Run in parallel across sources by default — sequential keeps rate limit handling and error reporting clean. Parallelize later if it becomes a bottleneck.
- Touch `index.md` (no notes change here)
- Run `git` — raw writes are direct (per `git_mode.raw: false`). The config update is also direct.

## Cron mode (later)

When ready, schedule via:
- macOS: `launchd` plist firing `claude -p "/fetch-sources"` daily at 20:00
- Or `cron` if simpler

The skill itself doesn't change — cron is just a shell-level invocation. The high-water mark mechanism makes any cadence safe (hourly, daily, weekly — pick what fits).

## Related

- [/capture](../capture/SKILL.md) — called per-item internally
- [/ingest](../ingest/SKILL.md) — consumes the raws produced here
- [/audit-vault](../audit-vault/SKILL.md) — surfaces the pile of `ingested: false` raws this skill builds up
- Vault schema: `<vault>/CLAUDE.md`
