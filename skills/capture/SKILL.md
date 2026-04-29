---
name: capture
description: Archive a single source as a raw file in the vault. No synthesis, no note created. Use when you want to keep a source available for later triage.
---

# /capture

Archives one source into `<vault>/raw/<source-type>/`. Pure archival — does not create or touch any note.

## When to use

- You want to save a source for triage later (« j'archive maintenant, je décide après »)
- You're called by `/fetch-sources` (batch passive capture)
- A volatile source might disappear (Slack thread, web article) and you want a snapshot now

## When NOT to use

- You already know the source deserves a note → use `/ingest` directly (it captures internally)
- The source is generic company-wide data not specific to the user → out of scope (covered by your general knowledge tool, e.g. Confluence, Dust, Glean, etc.)
- The source is « an event with no content » (« meeting happened ») → no value to capture

## Inputs

- `<URL>` (mandatory) — origin URL of the source. Examples:
  - `https://app.slack.com/client/T0/C0ABC/p1745395200000`
  - `https://www.notion.so/abc123`
  - `https://github.com/your-org/repo/pull/234`
  - `https://blog.example.com/article`
  - `claude://current` (special: capture the active Claude session). Future-compatible: `claude://session/<id>` to capture a specific past session.
- `--type <slack|notion|github|web|claude|meetings>` (optional) — override auto-detection if URL ambiguous

## Configuration read

From `<vault>/.vault-config.yml` (static config):
- `vault_path` — where to write raw
- `fetch_sources.<type>` — must be `true` for the source type to be enabled

Does not read `.vault-state.yml` (no high-water mark needed for single-source capture).

## Behavior

1. **Read schema** — `<vault>/CLAUDE.md` (raw section). Never operate from memory.
2. **Detect source type** from URL (slack/notion/github/web/claude/meetings). If ambiguous → use `--type` or fail.
3. **Determine volatility**:
   - **Volatile** (full raw): Slack, Claude conversations, web articles, **GitHub open PRs / open issues** (still mutable, comments and edits keep coming)
   - **Stable** (stub raw): Notion (internal company wiki), GitHub merged/closed PRs, GitHub commits (immutable once closed)
   - In doubt → full raw
4. **Compute `source_id`** — stable unique id for dedup:
   - Slack: `<channel_id>-<thread_ts>` (or `<message_ts>` if not in thread)
   - Notion: `<page_id>` (UUID)
   - GitHub: `<owner>/<repo>/<pr_number>` or `<owner>/<repo>/<commit_sha>`
   - Web: `<domain-slug>-<title-slug>` (e.g. `cncf-io-kubernetes-1-30-release`). Human-readable, dedup-safe enough for the volume expected.
   - Claude: `<session_id>` or `<timestamp>` if no session id
5. **Lookup existing raw** by `source_id` across `<vault>/raw/<type>/*.md`:
   - **Not found** → create new raw (step 6)
   - **Found, content identical** → skip silently, exit 0
   - **Found, content evolved** → append new content + update `captured_at` (step 7)

   **How to detect « content evolved » vs « identical »**:
   - **Sources with API `modified_at`** (Notion, GitHub) → compare current API `modified_at` vs frontmatter `modified_at`. Different → evolved. Same → identical. Most reliable: reflects authorial intent.
   - **Sources without `modified_at`** (Slack threads, web articles, Claude conversations) → compute SHA-256 of captured content, store in frontmatter `content_hash:`. On re-capture, hash the new content, compare to stored. Different → evolved.
   - Always prefer `modified_at` when available; hash is the fallback.
6. **Create new raw**:
   - Path: `<vault>/raw/<type>/YYYY-MM-DD-<short-hint>.md`
   - `<short-hint>` = sluggified channel/title/topic (15 chars max)
   - Write frontmatter (see below) + body
   - For full raw: full content as markdown (cleaned: no expired AWS URLs, no auth-tokened links)
   - For stub raw: 1-line brief about what the source is + what changed (if known)
7. **Append on existing raw** (re-fetch detected new content):
   - Append a separator line (`---`) + new content at end of body
   - Update `captured_at` to now
   - **Append-only** — never rewrite previous content
   - If raw was `ingested: true` → flip to `ingested: stale` (note may be outdated)
   - If raw was `ingested: false` → leave as-is (still pending triage)
   - If raw was `ingested: stale` → leave as-is
   - If raw was `ingested: orphan` → not applicable (source disappeared, can't have re-fetched it)
8. **Output** — print the absolute path of the raw file created or updated, and its status (`created`, `appended`, `skipped`).

## Frontmatter to write

### Full raw

```yaml
---
type: raw
source: <origin URL>
source_id: <computed unique id>
date: 2026-04-27
captured_at: 2026-04-27T15:30:00Z
modified_at: <API last-modified if available>   # optional, used for evolution detection
content_hash: <sha256 of body content>          # used when modified_at is absent
author: <author handle if known>                # optional
channel: <channel/page/repo name>               # optional
stable: false
ingested: false
ingested_in: []
dead_at: <date if source went 404>              # optional, set when source disappears
---
```

### Stub raw

```yaml
---
type: raw
source: <origin URL>
source_id: <computed unique id>
date: 2026-04-27
captured_at: 2026-04-27T15:30:00Z
modified_at: <source last-modified date>  # always set for stubs (Notion/GitHub provide this)
title: <source title>                     # for fast triage scan
author: <author if known>                 # optional
stable: true
ingested: false
ingested_in: []
dead_at: <date if source went 404>        # optional, set when source disappears
---
```

## Body format

### Full raw body

```
**Source**: <human label of the source — channel name, page title, etc.>

<full captured content, in markdown>
```

### Stub raw body

```
**Stub raw** — stable source, content remains canonical at the URL above.

Brief: <1-line summary of what this source is and what changed (if re-capture)>
```

## Edge cases

- **URL not reachable / 404** → fail loudly, do not create raw. Print the error. If a raw with this `source_id` already existed (re-capture scenario where source disappeared), flip the existing raw to `ingested: orphan` and append a frontmatter `dead_at: <today>` so the dead status is dated. Don't append to body. Tell the user.
- **MCP not authenticated for the source type** (Slack/Notion/GitHub) → fail with explicit message: « run `/mcp` to authenticate ».
- **Source content empty** (e.g., empty Notion page) → still create raw with empty body + a frontmatter flag `empty: true`. Triage later will decide.
- **Image-only source** (e.g., a Notion page that's only screenshots) → capture image URLs in a list at top of body. Note: image URLs may expire (AWS signed) → mention in body for clarity.
- **Source larger than fetch limit** (e.g. > 30k chars in one fetch call) → fetch in chunks, concatenate, write the **full** content. No silent truncation — the raw is the source of truth, fidelity matters. If chunking still doesn't suffice (extreme cases > ~1M chars), fail loud and ask the user explicitly: split into multiple raws / skip / accept truncation with `truncated: true` flag. Never decide silently.
- **`claude://current`** — capture the entire active conversation as markdown. Resolved at capture time to `claude://session/<session-id>`. `source_id` = session id (stable across re-captures of the same session).

## Outputs

- One raw file written to `<vault>/raw/<type>/`
- Stdout: `<path> | <status: created|appended|skipped>`
- Exit code: 0 success, non-zero on failure

## Does NOT

- Touch `<vault>/notes/`
- Touch `<vault>/index.md`
- Touch `<vault>/log.md` (logging is the job of `/ingest`, not `/capture`)
- Run `git` — `raw/` is direct-write per `.vault-config.yml` `git_mode.raw: false`
- Decide whether the source deserves a note — that's `/ingest`'s job (or yours, via triage)

## Related

- [/ingest](../ingest/SKILL.md) — calls `/capture` internally if given a URL, then synthesizes
- [/fetch-sources](../fetch-sources/SKILL.md) — calls `/capture` in batch for all enabled sources
- Vault schema: `<vault>/CLAUDE.md` — re-read before each invocation
