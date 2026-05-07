---
name: fetch-sources
description: Batch capture across all configured sources (Slack, Notion, GitHub, web, ...). Surfaces what's new since last run, writes a single dated summary file in digest/ for downstream consumption (daily-digest, ingest). Manual at first, cron later.
---

# /fetch-sources

Sweep all enabled sources in `<vault>/.vault-config.yml`, capture what's new since the last sweep, write a single dated summary file in `<vault>/digest/`. Does NOT synthesize — `/ingest` and triage are separate steps.

## When to use

- End of day / week — you want « what surfaced about me since I last looked »
- Before a triage session
- Cron job (when set up later)
- After being away — `--since 2026-04-20` to catch up a gap

## When NOT to use

- You know exactly which source you want — use `/capture <URL>` directly
- You want to ingest now — `/fetch-sources` doesn't synthesize

## Inputs

All optional :

- `--since <YYYY-MM-DD | ISO datetime>` — override the per-source high-water mark, force fetch from that point
- `--until <YYYY-MM-DD | ISO datetime>` — cap the fetch at that point (default: now)
- `--sources <comma-separated>` — limit to a subset (e.g. `--sources slack,notion`). Default: all sources with `fetch_sources.<type>: true` in config
- `--except <comma-separated>` — exclude one or more sources (e.g. `--except github_discussions,web`). Combine with `--sources` or alone.
- `--min-interval <duration>` — skip a source if `last_fetch[S]` is more recent than `now - duration` (ex: `--min-interval 30m`). Avoids double-runs (cron + manual). Default: 0 (disabled).
- `--summary <brief|full|none>` — output verbosity (Step 6).
  - `brief` (default) : per-source counters (`5 captured, 2 skipped, 0 failed`).
  - `full` : factual recap with items + links, **and writes the recap to `<vault>/digest/<YYYY-MM-DD>-fetch-summary.md`** (gitignored, consumable by `/daily-digest` and other skills).
  - `none` : silent, exit code only (cron quiet mode).
- `--dry-run` — list what would be fetched without writing anything

## Configuration read

From `<vault>/.vault-config.yml` (static config) :

- `vault_path`
- `user_handle.<source>` — handles used in API filters
- `fetch_sources.<type>` — boolean per source type (enabled or not)
- Source-specific config (`notion.tracked_databases`, `web.feeds`, etc. — see Sources section below)

From `<vault>/.vault-state.yml` (dynamic state, gitignored) :

- `last_fetch.<type>` — high-water mark ISO timestamp per source (the « since » to use if no `--since` flag)

Writes to `<vault>/.vault-state.yml` at the end of a successful run (atomic write — temp file + rename). Never writes to `.vault-config.yml`.

## Behavior — high level

```
Resolve since/until per source → for each enabled source : query API, filter what concerns you,
compose per-source summary entries → write a single dated summary file in digest/ →
on full success, update last_fetch per source.
```

**No more individual raws at runtime** : `/fetch-sources` does NOT deposit N files in `raw/<source>/*.md` by default. It produces **a single** file `<vault>/digest/<YYYY-MM-DD>-fetch-summary.md` with the per-source recap. To archive a specific item long-term, use `/capture <url>` manually. To synthesize, `/ingest` accepts either a raw or the summary as a whole (e.g. weekly synthesis).

## Behavior — precise steps

### Step 0 — re-read schema + acquire lock

- Read `<vault>/CLAUDE.md` (raw + scope sections). Same rule as `/ingest` — never operate from memory.
- **Acquire file lock** : create `<vault>/.vault-state.yml.lock` with current PID. If lock exists with a live PID → fail loud (« another fetch-sources is running, PID X »). Stale lock → take over and warn. Release on exit.

### Step 1 — resolve fetch window per source

For each enabled source `S` :

- `since[S]` = `--since` flag if provided, else `last_fetch[S]` from `<vault>/.vault-state.yml`. **No magic default** : if `last_fetch[S]` is null and `--since` is not given, fail loud and ask the user to pass `--since <date>` for that source.
- `until[S]` = `--until` flag if provided, else `now`
- If `since[S] >= until[S]` → no-op for this source
- **Window safety check** : if `(until[S] - since[S]) > 45 days` → ask for confirmation before fetching. Default to abort if no confirmation.

### Step 1b — pause-resume detection

If a source was just re-enabled (`fetch_sources.<S>: true` after being `false`) and `last_fetch[S]` is far in the past (>45 days), warn explicitly : « source <S> was paused, last_fetch is N days old. Pass `--since` if you want a different bootstrap point. »

### Step 2 — for each source, query and filter

The « what concerns me » filter must be **deterministic and API-driven**, not an AI judgment. Each source's filter is a set of API query parameters (mentions, assignee, author, etc.) — see Sources section.

Iterate over enabled sources. For each :

- Query the source API for items modified/created in `[since, until]`, using the deterministic filter.
- Apply the « content > event » filter : skip pure logistics (« meeting scheduled with no agenda », « ticket created with no description »). Structural filter (empty body, < N chars), not semantic.
- Compose **summary entries** in memory : `{source, item_url, title, one_line_context, date, state}`. No individual raw writes.

**Never** let the AI subjectively decide « this concerns me » or « this is logistics ». The filter is config-driven, deterministic, replayable.

### Step 3 — collect outcomes + write summary file

Per source, count : items found, items kept (post-logistics filter), items skipped, items failed.

**Write `<vault>/digest/<YYYY-MM-DD>-fetch-summary.md`** : one file per day, **append intra-day** (multiple runs/day = successive sections separated by `---`). Format :

```markdown
# fetch-sources summary — <YYYY-MM-DD>

---

## Run <ISO timestamp> (since: <prev last_fetch>, until: <now>)

### Slack — N captured
- ...

### GitHub PRs/Issues — N captured
- ...

[other sources in fixed order : Linear > Notion > GitHub Discussions > Web > Meetings]
```

**Append behavior** :

- If file exists for the day → append `---\n\n## Run <ISO>...` at the end (preserves previous runs).
- Otherwise → create with header `# fetch-sources summary — <date>` + first section.

**Fixed source order** : `Slack > GitHub PRs/Issues > Linear > Notion > GitHub Discussions > Web > Meetings`. Empty sources omitted in the run, but order stable. Disabled sources (`fetch_sources.<S>: false`) not in the list.

**URL formats** (clickable browser) :

- Slack : `https://<your-workspace>.slack.com/archives/<channel_id>/p<thread_ts_no_dot>` (strip the dot from thread_ts)
- GitHub : `https://github.com/<owner>/<repo>/pull/<num>` or `/issues/<num>`
- Linear : `https://linear.app/<your-workspace>/issue/<identifier>`
- Notion : `https://www.notion.so/<page_id>`

> Adapt URL prefixes to your stack/workspace. The point is : produce HTTPS clickable URLs (no `slack://` proprietary scheme that only works in the desktop app).

### Step 4 — update high-water mark

**Only if the source's run completed without fatal error** :

- Set `last_fetch[S] = until[S]` in `<vault>/.vault-state.yml`
- Atomic write — temp file + rename.

**Failure model** : if Slack succeeds but Notion fails halfway, only `last_fetch.slack` is updated. Next run retries Notion from its old high-water mark. Nothing is lost, no duplicate captures.

### Step 5 — append to log.md

One line per source run :

```
YYYY-MM-DD | fetch-sources <source> [<since> → <until>] | <N captured>, <K skipped>, <F failed>
```

If `--dry-run` : skip log.md.

### Step 6 — print summary

Format depends on `--summary` (default `brief`).

#### `--summary brief` (default)

```
fetch-sources summary (2026-04-28T20:00 → 2026-04-28T20:03):
  slack:              12 captured, 5 skipped (logistics), 0 failed
  notion:              4 captured, 2 skipped, 0 failed
  github:              2 captured, 1 skipped, 0 failed
  github_discussions:  1 captured, 0 failed
  linear:              0 captured (nothing assigned), 0 failed
  web:                 0 captured (no new RSS items), 0 failed
last_fetch updated for: slack, notion, github, github_discussions, linear, web

→ 19 new items pending triage. Run /audit-vault for the actionable list.
```

#### `--summary full`

Stdout = factual recap with items + links. **And** writes the same content to `<vault>/digest/<YYYY-MM-DD>-fetch-summary.md`. See Step 3 format.

#### `--summary none`

No stdout. Exit code only (cron quiet : `claude -p "/fetch-sources --summary none"`). `log.md` is still appended.

## Sources

### Slack

**Concerns me filter** (deterministic, API-driven, **2 separate queries + client-side dedup**) :

The combination `to:me OR @me` does NOT work as expected in Slack search (limited boolean OR). Split into 2 separate queries :

```
Query A (DMs to me)            : to:<@USER_ID> after:<since>
Query B (mentions in channels) : <@USER_ID> after:<since> -from:<@USER_ID>
```

Then dedup client-side by `thread_ts` (a message can surface in both queries).

**Not included** :

- Messages **from me** (`from:<@USER_ID>`) — output, not inbound. Reserved for Follow-up annotation in Brief if you want to track "I'm waiting for a reply" (separate optional query).
- Threads where I posted WITHOUT being tagged — detection requires reading the thread (expensive), handled by digest live re-pull if needed.
- **Bot / app messages** : Slackbot (OoO notifs on colleagues, other auto notifs), webhooks from apps, integration bots, etc. Detection : `From: ... [BOT]` field in `detailed` Slack search format. Filter upstream, do NOT mention in the summary (noise, not signal).
- **Empty messages** : `text: ""` or whitespace only. No signal, silent skip.

**Channel ID resolution** : Slack search APIs return `channel_id` (e.g. `D03ABCDEF`, `C04ABCDEF`). To make them clickable in the summary, call `slack_search_users` or cache the mapping in `.vault-state.yml` on first run.

**API** : Slack MCP server. Auth check at Step 0.

**Per-item URL** (clickable browser) : `https://<your-workspace>.slack.com/archives/<channel_id>/p<thread_ts_no_dot>` (the thread_ts has format `1234567890.123456` ; for the URL, strip the dot → `p1234567890123456`).

> Adapt to your stack : if you use Discord / Teams / Mattermost instead of Slack, replace this section with the equivalent. Same logic, different MCP.

### Notion

**Concerns me filter** (deterministic, API-driven) :

- Pages where I am the **owner** (Notion `Created by` filter, via `notion-search filters.created_by_user_ids: [<user_handle.notion_user_id>]`).
- Pages in spaces / databases I explicitly track (config : `notion.tracked_databases: [...]`).

**Known API limitation** : Notion search does NOT expose `mentioned_user_ids` nor `commented_by_user_ids` filters. Pages where I am mentioned in a comment OR edited by others are **NOT covered by automatic sweep**. Name-based search (e.g. searching for a first name) is **explicitly excluded** as a deterministic filter — it produces noise from homonyms in any non-trivial workspace. Fallback for these cases : `/capture <notion_url>` manually when you know a page concerns you without being its creator.

**API** : Notion MCP. Auth check at Step 0. Identity resolved via `user_handle.notion_user_id` in `.vault-config.yml` (resolved once via `notion-search query_type=user`, cached).

**Per-item URL** : `https://www.notion.so/<page_id>`.

### GitHub (PRs + Issues)

**Concerns me filter** (deterministic API queries, scope `--owner=<user_handle.github_org>` to exclude personal repos) :

- `gh search prs --author=<user_handle.github> --owner=<user_handle.github_org> --state=all --updated=">=<since>" --limit=100`
- `gh search prs --review-requested=<user_handle.github> --owner=<user_handle.github_org> --state=all --updated=">=<since>" --limit=100`
- `gh search issues --assignee=<user_handle.github> --owner=<user_handle.github_org> --updated=">=<since>" --limit=100`
- `gh search issues --mentions=<user_handle.github> --owner=<user_handle.github_org> --updated=">=<since>" --limit=100`

**Explicit exclusions** (config `user_handle.github_repo_exclude`) : any listed repo is filtered client-side after pull. E.g. personal portfolio repos out of work scope.

**Pagination** : `--limit=100` (vs default 20) reduces miss risk. Paginate via `--page` if `hasNextPage`.

**Manual vs auto filter for `--review-requested`** (deterministic, not AI judgment) : `gh search prs --review-requested=<user>` returns PRs where the user AND teams the user belongs to are tagged. Classify into 3 categories via GraphQL timeline `REVIEW_REQUESTED_EVENT` (with `actor` + `requestedReviewer`) :

```graphql
query($owner: String!, $repo: String!, $num: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $num) {
      author { login }
      timelineItems(first: 50, itemTypes: [REVIEW_REQUESTED_EVENT]) {
        nodes {
          ... on ReviewRequestedEvent {
            actor { login }
            requestedReviewer {
              ... on User { login }
              ... on Team { slug }
            }
          }
        }
      }
    }
  }
}
```

**Classification per PR** :

- **MANUAL ping** (include in classic inbox) : ≥1 event where `requestedReviewer.login == <user>` AND `actor.login` is a human (PR author or colleague, non-bot). Ex : a colleague adds you explicitly.
- **AUTO User-level** (separate flag "to check yourself") : ≥1 event where `requestedReviewer.login == <user>` BUT `actor.login` is a CODEOWNERS bot / app (suffix `[bot]`, or login in known-bots config). Tagged user-level via auto-resolution from a CODEOWNERS team.
- **AUTO Team-only** (silent skip) : no event with `requestedReviewer.login == <user>` ; only `requestedReviewer.slug == <team>`. You're in the team but no one pinged you personally.

**Special digest section** : PRs in **AUTO User-level** category go in a `## 🤖 Auto-tagged PRs (to check yourself)` section, separate from the classic inbox. You decide if it's worth your review (do not include mechanically as manual).

Cost : ~1 GraphQL call per review-requested PR (~5s runtime for ~24 PRs/run typical). Acceptable for 1 fetch/day.

⚠️ **Known limitation** : the "MANUAL" classification via timeline events can be a false positive. GitHub GUI sometimes shows "assigned automatically" on PRs where the API shows `actor.login == <human>` (PR author or colleague). Possible causes :

- Repo config auto-assign reviewer (`.github/auto-assign.yml` or similar) — human pushes, bot auto-assigns but the event is attributed to the human.
- GitHub resolves a team request into user-level members → GUI label "assigned automatically" but event remains attributed to the requester.
- Round-robin extension that flies under the radar.

**TODO** : investigate `.github/auto-assign.yml` or other repo config, and adapt classification (e.g. add a 4th category "AUTO via repo config" if detectable). For now, keep API classification and accept some false positive MANUAL.

**For `--assignee` and `--mentions`** : already user-direct filters server-side, no manual-only post-filter needed.

**API** : `gh` CLI + `gh api graphql` for the manual-only filter (auth via `gh auth`).

**Per-item URL** : `https://github.com/<owner>/<repo>/pull/<num>` for PRs, `/issues/<num>` for issues.

### GitHub Discussions

**Concerns me filter** (single GraphQL query — `involves:` covers author + commenter + mentioned in one shot) :

```bash
gh api graphql -f query='
  query($q: String!) {
    search(query: $q, type: DISCUSSION, first: 50) {
      nodes {
        ... on Discussion {
          id title url repository { nameWithOwner }
          author { login } updatedAt body
        }
      }
    }
  }
' -f q="involves:<user_handle.github> updated:>=<since>"
```

**API** : `gh api graphql` (the CLI `gh search` does NOT expose discussions). Auth via standard `gh auth`.

**Per-item URL** : `https://github.com/<owner>/<repo>/discussions/<num>`.

**Why separate from `github`** : independent last_fetch, different lifecycle (long async vs fast PR), can be skipped via `--except github_discussions` without breaking PR/issue sweep.

### Linear

**Scope** : issues assigned to me. Deterministic native filter, no AI judgment.

**Procedure** :

- `list_issues assignee=me updatedAt>=<since> limit=250` (workspace-wide, paginate if `hasNextPage`).
- The `assignee=me` filter also covers issues you created and auto-assigned (most common case).

**API** : Linear MCP (`list_issues`, `get_issue`). Auth check at Step 0.

**Logistics filter** : apply the « content > event » filter from Step 2 (empty description or < 30 chars → skip).

**Per-item URL** : `https://linear.app/<your-workspace>/issue/<identifier>`.

**Cases not covered by automatic sweep** (fallback `/capture <linear_url>` manual) :

- Issue created without auto-assignment (rare — Linear auto-assigns by default).
- Issue where I commented/participated without being assigned. Linear MCP API does not expose `commenter=` filter, nor a global query on comments (`list_comments` requires `issueId`). A workspace fan-out would be too costly for a cron.

**Native filters NOT supported by Linear MCP** (verified against the schema, to avoid retrying) :

- `creator` / `createdById`, `mentions`, `commenter` / `participant` — absent.

### Web (RSS / explicit list)

**Concerns me filter** : only sources I explicitly opted into (config : `web.feeds: [<rss_url>, ...]`). No generic crawl.

**Per-item URL** : the article URL.

### Meetings (transcripts placeholder)

Disabled by default (`fetch_sources.meetings: false`) until a transcripts tool is set up. When enabled :

- Pull transcripts of meetings where the user was a participant.
- Type : volatile (transcripts not durably accessible elsewhere).

> Adapt to your stack : Otter, Granola, Fireflies, Quill, etc.

### Direct AI conversations

NOT auto-fetched. Captured on demand via `/capture <conversation-url>` during/after a session. `fetch-sources` does not sweep these.

## Configuration

Static config in `<vault>/.vault-config.yml` (committed). State in `<vault>/.vault-state.yml` (gitignored, auto-updated by this skill).

`.vault-config.yml` (relevant fields) :

```yaml
user_handle:
  slack: "@your.handle"
  slack_user_id: "U00000000"
  github: "your-github-username"
  github_org: "your-org"               # --owner scope for gh search (excludes personal repos)
  github_repo_exclude:                 # additional client-side filter after pull
    - "your-username/personal-repo"
  notion: "Your Name"                  # display name (do NOT use as filter, noisy)
  notion_user_id: ""                   # resolved once via notion-search query_type=user
  linear: "you@example.com"
  linear_user_id: ""                   # resolved once via list_users
  email: "you@example.com"

fetch_sources:
  slack: true
  notion: true
  github: true
  github_discussions: true
  linear: true
  web: false
  meetings: false

notion:
  tracked_databases: []

# No linear: section — assignee=me is sufficient, no extra config.

web:
  feeds: []
```

`.vault-state.yml` (auto-updated) :

```yaml
last_fetch:
  slack: 2026-04-27T20:00:00Z
  notion: 2026-04-27T20:00:00Z
  github: 2026-04-27T20:00:00Z
  github_discussions: 2026-04-27T20:00:00Z
  linear: 2026-04-27T20:00:00Z
  web: null
  meetings: null
```

## Edge cases

- **MCP server not authenticated** for a source → fail that source loudly, do NOT update its `last_fetch`. Continue with other sources.
- **API rate limit hit** → stop the source mid-run, do NOT update `last_fetch`. Next run resumes.
- **Source returns nothing new** → not an error. Update `last_fetch` to `until`.
- **First run, no `last_fetch[S]`, no `--since`** → fail loud : « no high-water mark for source X, pass `--since <date>` to bootstrap ».
- **Clock skew / `since > until`** → no-op for that source, log warning.
- **`--dry-run`** → never touches disk or config.
- **`--dry-run` + `--summary full`** → produces the recap on stdout but does NOT write to `digest/<date>-fetch-summary.md` (consistency : dry-run = zero disk write).
- **Multiple runs `--summary full` same day** → file `digest/<YYYY-MM-DD>-fetch-summary.md` is appended (intra-day successive sections). For history, also see `<vault>/log.md` (append-only, 1 line per source per run).
- **`--except <S>`** → excludes S from the resolved list. If S not in the starting list, no-op (soft warning).
- **`--min-interval <duration>`** → if `last_fetch[S]` is more recent than `now - duration`, skip that source with explicit warning (« skipped: last fetch <X minutes ago < min-interval ») and do NOT advance `last_fetch`.

## Outputs

- **`<vault>/digest/<YYYY-MM-DD>-fetch-summary.md`** written/appended (gitignored). Single source for `/daily-digest` and other consumer skills. Multiple runs/day = appended sections. For history, `<vault>/log.md` (append-only).
- `<vault>/.vault-state.yml` updated (`last_fetch` per source that ran — atomic write).
- `<vault>/log.md` appended (one line per source run).
- Stdout : summary block (format per `--summary brief|full|none`, see Step 6).
- **No individual raws** by default. Old behavior (one raw per item via `/capture`) abandoned — too many files, low value. To archive a specific item long-term : `/capture <url>` manually.
- Exit code : 0 if all enabled sources completed ; non-zero if a source failed fatally.

## Does NOT

- Synthesize anything into `notes/` (that's `/ingest`)
- Decide what's note-worthy (that's triage / `/ingest`)
- Run sources in parallel by default — sequential keeps rate limit handling and error reporting clean.
- Touch `index.md` (no notes change here)
- Run `git` — direct writes (per `git_mode.raw: false`).

## Cron mode (later)

When ready, schedule via :

- macOS : `launchd` plist firing `claude -p "/fetch-sources"` daily at your preferred time.
- Or `cron` if simpler.

The skill itself doesn't change — cron is just a shell-level invocation. The high-water mark mechanism makes any cadence safe.

## Related

- [/capture](../capture/SKILL.md) — manual single-item archive (replaces the per-item raw deposit that fetch-sources used to do)
- [/ingest](../ingest/SKILL.md) — consumes a raw OR the dated summary in `digest/`
- [/audit-vault](../audit-vault/SKILL.md) — health check
- [/daily-digest](../daily-digest/SKILL.md) — consumes the dated summary in `digest/`, produces a curated digest in `journal/`
- Vault schema : `<vault>/CLAUDE.md`
