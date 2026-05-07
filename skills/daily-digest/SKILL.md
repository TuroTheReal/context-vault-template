---
name: daily-digest
description: Generate a daily digest — a single markdown artifact combining a brief (passive recap by source with status emoji annotations) and an actionable inbox (ball in your court). Output goes to stdout AND <vault>/journal/<YYYY-MM-DD>-digest.md (append intra-day). No DM (manual copy until a cron is added).
---

# /daily-digest

Generate your daily digest. Single markdown artifact, locally archived in the vault, no auto-send. Manually triggered (no cron yet).

## When to use

- Morning routine before any synchronous standup / daily ritual.
- À tout moment de la journée si tu veux un consolidated view (post-réunion, post-pause, etc. — d'où le nom `daily-digest`).
- Manual trigger — no cron yet. Run `/daily-digest` whenever you want a consolidated view.
- After being away (weekend, vacation) — covers the gap automatically via fetch-sources high-water mark.

## When NOT to use

- You only want raws archived → `/fetch-sources` is enough.
- You're off and don't need a digest → don't trigger.

## Inputs

All optional :

- `--since <YYYY-MM-DD | ISO datetime>` — override the fetch-sources `--since` (rare ; default = `last_fetch` per source via fetch-sources mechanism).

## Pipeline (precise steps)

### Step 0 — re-read schema, identity check

- Read `<vault>/CLAUDE.md` (raw + scope sections). Same rule as `/ingest` and `/fetch-sources` — never operate from memory.
- Verify the MCP servers consumed (Slack, Linear, GitHub via `gh`, Notion, Gmail, etc.) are authenticated. If not, abort loud with auth instructions.
- Resolve identity from `<vault>/.vault-config.yml` (`user_handle.*` keys). Skill MUST NOT hard-code your handles. Required keys :
  - `user_handle.slack`
  - `user_handle.slack_user_id` (DM target if you ever wire a self-DM)
  - `user_handle.github`
  - `user_handle.linear`
  - `user_handle.linear_user_id`
  - `user_handle.notion`
  - `user_handle.notion_user_id`
  - `user_handle.email`

### Step 1 — ensure fresh fetch-summary

- Read `<vault>/digest/<TODAY>-fetch-summary.md` if exists.
- If absent OR file mtime older than 6h → invoke `/fetch-sources --summary full` and wait for completion.
- If `/fetch-sources` itself fails fatally (auth, network) → abort the digest with a loud error. Don't produce a half-broken digest.

### Step 2 — parse fetch-summary

Extract per-source from `digest/<TODAY>-fetch-summary.md` :

- Counts (captured, skipped, failed) → for the brief section + warnings detection.
- Item lists (titles, URLs, context) → input for inbox classification.
- Failed sources → flag for ⚠️ markers in the brief.

### Step 3 — Slack live re-pull (freshness)

The fetch-summary may be 0-6h stale. For the inbox section, re-pull Slack live to capture the last hour :

- Mentions of you in the last 1h not yet in the summary.
- DMs received in the last 1h.
- Threads where you posted with a new reply since the summary.

Merge with summary items, dedup by `thread_ts`.

> Adapt to your stack : if you use Discord / Teams / Mattermost instead of Slack, replace this step accordingly. Same logic, different MCP.

### Step 4 — classify items per source ("ball in your court" algorithm)

For each item, determine state. The classification is **deterministic** : same fetch-summary + same live state ⇒ same digest. No "AI subjectively decides what's important". The reasoning is on **state**, not **content**.

#### Ball in your court (inbox)

- **Slack thread** : last message author ≠ you AND you have posted earlier in the thread → you owe a reply.
- **Slack DM** : last message from your contact, no reply from you.
- **Slack mention** : you mentioned in any channel, no reply from you after the mention.
- **GitHub PR** : `review-requested:<your-username>` (manual ping) AND not yet reviewed ; OR your PR with new comments from others, no reply.
- **GitHub Discussions** : you tagged or last comment from someone else in a thread you posted.
- **Linear issue** : assigned to you AND status `triage`/`backlog` (not yet started) ; OR comment mentioning you with no reply.
- **Gmail** : unread thread where you are in `to` ; OR thread where last message is not from you and you replied earlier.
- **Notion** : page where you are mentioned in a comment with no reply from you.

#### Follow-up / "ball with others" (annotation in the Brief, not a separate section)

These items go in the Brief of their respective source with status emoji (⏳ waiting / ✅ done / 💬 closed), NOT in a dedicated Follow-up section.

- **Slack thread / DM** : last message from you, no reply from contact since N hours → ⏳ in Brief Slack.
- **GitHub PR** : your PR awaiting review (no review yet) → ⏳ in Brief GitHub. Merged PR → ✅ in Brief GitHub.
- **Linear issue** : assigned to you, status `started`, blocked by waiting comment from someone else → ⏳ in Brief Linear.

#### Passive (info only, in the Brief)

- Everything else that surfaced in the summary but is neither ball-in-your-court nor follow-up. Annotated with the appropriate status emoji.

### Step 5 — compose the digest markdown

**Fixed source order** in the Brief : `Slack > GitHub PRs/Issues > Linear > Notion > GitHub Discussions > Gmail > Web`. If a source has 0 captures, **omit its section** (no empty section), but don't reorder. Stable reading habit.

> Adapt the order to your stack and reading priorities. The point is : the order MUST be fixed (not data-dependent), to build muscle memory.

**Minimalist output rules** (KISS, avoid noise) :

- **Empty sections → don't display** (Inbox empty, 🤖 Auto-tagged PRs empty, GH Discussions 0 captured, etc.). Better than displaying "0 items".
- **No circular auto-reference** in the brief (no "details in Inbox" placeholder pointing further down — either list items in the brief, or omit, but no placeholder).
- **No "Validations" / "Limitations" / "Info / Skips" sections** in the daily output. These metadata live in `digest/<date>-fetch-summary.md`. The digest is a readable artifact, not a debug report.
- **No separate "Follow-up" section**. Items "ball with others / closed / done / merged" annotated **directly in the Brief** by item, via status emoji. Avoids Brief↔Follow-up duplication for the same PR/thread.
- **No duplication** between Brief and Inbox. If an item is in Inbox (ball-in-your-court actionable), it does NOT appear in the Brief. Brief = passive/info items only.
- **Bots/apps Slack auto** (Slackbot OoO notifs on colleagues, integration bots, app webhooks) → do not mention. Not in Brief, not in Inbox. Filter upstream (in `/fetch-sources`).
- **Slack mention format** : use `@username` (readable) rather than `<@USER_ID|username>` (Slack native format). **Exception** : in the `:linear-todo:` / `:linear-done:` block of any recurrent task draft section (which will be copy-pasted to Slack), keep `<@USER_ID|username>` for Slack to resolve the mention as clickable.

#### Status emoji in the Brief (per-item annotations)

When an item is mentioned in the Brief, the agent prepends the emoji that reflects its state :

- ✅ done / merged / closed (no action expected, info)
- 💬 closed conversation (the other replied, conversation done)
- ⏳ waiting on others (I posted, I wait)
- 🔍 review needed (open PR awaiting action — usually moved to Inbox)
- ➕ new item (created by me recently, info)
- 📝 edited / commented by me (info)

Example :

```markdown
**GitHub** :
- ✅ [#90617](url) — fix(clinic) merged 2026-05-05
- ⏳ [#90801](url) — pushed yesterday, no review yet

**Slack** :
- 💬 [DM Person A](url) — "No problem!" (replied, closed)
- ⏳ [DM Person B](url) — silence for 6h on topic Y
```

The Inbox contains only items 🔍 / ⏳-action-mine. The Brief contains everything else, annotated.

### Philosophy : mechanical generation, zero meta-commentary

The agent executing the skill does NOT reason about context beyond the deterministic algorithm. It never says :

- ❌ « You already posted your standup today, content consistent, no need to re-post »
- ❌ « The digest is partially stale, be careful »
- ❌ « This PR is probably not for you, to judge »
- ❌ « Note : false positive possible, to verify »

It just outputs the result of the algorithm. If the mechanism produces output identical to something already done by the user → **emit it as-is**, no annotation. The user judges on read whether to use it.

The only acceptable annotations in the digest :

- ⚠️ source-level fail (e.g. "Notion ⚠️ FETCH FAILED auth expired") — that's data, not reasoning.
- Clickable links to items.
- 1-line context per item (extract from source, not interpretation).

**Underlying logic** : another agent invoking `/daily-digest` with just the SKILL.md (no conversation context) must produce 100% predictable, useful output. No layers of "I think" / "you should" / "to judge".

### Top-down structure

```markdown
# Daily digest — <YYYY-MM-DD>

---

## Run <ISO timestamp>

### 🔔 Brief

**Slack** :
- ✅/⏳/💬/➕ [link](url) — short context
- ...

**GitHub** :
- ✅/🔍/⏳ [#N](url) — title
- ...

[other sources in fixed order, sections with content only]

### 📥 Inbox — ball in your court (action required)

**Slack** :
- [Person/channel](url) — what they need from you
- ...

**GitHub PRs review-requested** :
| PR | Author | Title |
| --- | --- | --- |
| [#N](url) | @username | title |

[other sources with ball-in-your-court items]

### 🤖 Auto-tagged PRs (to check yourself)

[Only displayed if non-empty. PRs where the user was tagged review-requested at user-level BUT the actor was a CODEOWNERS bot / app, not a human. Not a legitimate manual ping, but not a team-only skip either. The user judges if it's worth review.]

- [Repo#N](url) — title (tagged via CODEOWNERS auto-resolution to user level)
- ...
```

> Recurrent task / ritual draft : the template doesn't include a draft section for any organisation-specific recurrent task (daily standup, weekly check-in, sprint summary, etc.). If your environment provides a draft generator command supporting an `--embed` mode, extend this skill with an additional step that invokes it and appends the returned markdown under a `## 📋 Recurrent task draft` section. Kept out of the template because rituals are organisation-specific.

#### Warning formatting in the brief

- **Item-level fail** (one item failed but source globally OK) : append inline ` — ⚠️ N item(s) not retrieved (<reason>)` to the section heading. Discreet, in-context.
- **Source-level fail** (entire source failed) : replace the section content with `### <Source> — ⚠️ FETCH FAILED (<reason>)` and a 1-line hint (e.g. "auth expired ?", "rate limit", "MCP timeout").

Examples :

```
**Slack** — ⚠️ 1 thread not retrieved (timeout)
**Notion** — ⚠️ FETCH FAILED (auth expired ?)
```

### Step 6 — write outputs

- Print the full digest markdown to stdout.
- Write to `<vault>/journal/<YYYY-MM-DD>-digest.md` (**append intra-day** : multi-runs/day = successive sections separated by `---`). If file exists → append `---\n\n## Run <ISO timestamp>\n...` at the end with full sections (Brief / Inbox, empty sections omitted) of the new run. Otherwise → create with header `# Daily digest — <date>` + first section. Ensure `<vault>/journal/` directory exists, create if not.
- Append a single line to `<vault>/log.md` :

  ```
  <YYYY-MM-DD> | daily-digest | brief: N items, inbox: N | warnings: <count>
  ```

### Step 7 — exit

- Exit code 0 if everything succeeded (warnings are not errors — failed sources still produce a digest with ⚠️ markers).
- Exit code non-zero only if `/fetch-sources` failed fatally in Step 1 OR digest write failed.

## Sources consumed

- `<vault>/digest/<TODAY>-fetch-summary.md` (primary, generated by `/fetch-sources --summary full`).
- Slack MCP (live re-pull for the last hour, freshness — adapt if you use a different chat platform).

## Outputs

- Stdout : full digest markdown.
- `<vault>/journal/<YYYY-MM-DD>-digest.md` : same content, append intra-day, gitignored. Clickable links (Obsidian / VS Code / GitHub).
- `<vault>/log.md` : single line appended.

## Does NOT

- Send a DM (deferred until cron is added).
- Modify `<vault>/raw/` or `<vault>/notes/` (read-only on those).
- Decide for you what's important — only classifies on **state** (ball in your court vs not), never on subjective content judgment.
- Run if the consumed MCPs are unauthenticated.
- Generate any recurrent task / ritual draft (organisation-specific, see note above to wire your own).
- Add meta-commentary (« you already did X », « to judge », etc.) — pure mechanical output.

## Edge cases

- **Run twice same day** → `journal/<date>-digest.md` appended (successive Run sections separated by `---`). Historical context preserved in-file + in `<vault>/log.md` (append-only).
- **Empty fetch-summary** (nothing captured) → produce a minimal digest with sections marked "(nothing captured in window)" or omit sections entirely. Don't abort.
- **All sources failed** → digest still produced, but each section says ⚠️ FETCH FAILED. You know to debug your MCPs.
- **Slack live re-pull fails** → digest still produced, inbox built from fetch-summary only (potentially up to 6h stale). Add a soft warning in the inbox header.
- **`<vault>/journal/` doesn't exist** → create it (`mkdir -p`). No need for explicit setup.

## Cron mode (later, deferred)

When ready :

- Trigger `claude -p "/daily-digest"` daily at your preferred time (e.g. 8h30 weekdays).
- At that point, add an auto-DM step at Step 6 : send the digest content to your self-DM (`user_handle.slack_user_id` from `.vault-config.yml`).
- Skip cron on weekends + your country's bank holidays. Manual trigger always available.
- For OOO : flag in `.vault-state.yml` `paused: true` checked at Step 0 to abort cleanly.

The skill itself doesn't change — cron is just shell-level invocation + a one-line DM addition.

## Related

- [/fetch-sources](../fetch-sources/SKILL.md) — invoked at Step 1 if fetch-summary stale or absent.
- [/ingest](../ingest/SKILL.md) — independent ; the digest doesn't synthesize into `notes/`, that's manual triage.
- Vault schema : `<vault>/CLAUDE.md`.
