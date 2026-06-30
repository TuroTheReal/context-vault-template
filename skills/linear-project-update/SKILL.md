---
name: linear-project-update
description: Generate a weekly project status update for a Linear project you lead, in your team's existing Highlights / Lowlights / Focus format. Cross-references Linear milestones + issues, git activity, PRs (gh), and the context vault, then double-checks every claim. Outputs a DRAFT to the vault and stdout — never auto-posts to Linear (confirm first, or pass --post). Triggers on "project update", "linear update", "weekly update for <project>", "status update for <project>", "génère mon update projet".
---

# /linear-project-update

Generate your weekly **project** status update for a Linear project you lead. Mirrors the format of the project's existing status updates. Locally archived in the vault, no auto-send. Manually triggered, or fired by a weekly routine in draft mode.

This is a **project** update (posted on a single project), not the aggregated **initiative** update (your lead owns that, it rolls several projects into one). Don't confuse the two.

## Tracker — Linear is the example

This skill uses **Linear** as the example project tracker, but the logic is **tracker-agnostic**: cross-reference your tracker (milestones + issues) + git + PRs + the vault → a status draft. To adapt, swap the Linear MCP calls (`get_project` / `list_issues` / `save_status_update`) for your tracker's equivalent (Jira, GitHub Projects, Asana, …). The skill name keeps `linear` as the concrete example.

## When to use

- Weekly, before your team's weekly reporting cadence.
- Any time you want a consolidated "what moved on project X since the last update".
- Fired by the `linear-project-update` weekly routine (draft mode → Slack DM / vault).

## When NOT to use

- You want the aggregated initiative update across all infra projects → that's <colleague>'s, not this.
- You only want a daily personal recap → `/daily-digest`.
- The project has had zero activity since the last update → don't post noise.

## Inputs

- `<project>` (positional, optional) — Linear project name, slug, URL, or ID. If omitted: list projects where `lead = me` and ask which one. Never guess silently.
- `--since <YYYY-MM-DD | ISO>` — override the time window. Default = `createdAt` of the project's latest status update; if none exists, last 7 days.
- `--post` — after the draft + double-check, post the update to Linear via `save_status_update`. **Off by default.** Without it, the skill stops at the draft and asks for confirmation (no-action-without-ask).
- `--lang <auto|en|fr>` — output language. Default `auto` = match the language of the latest existing status update (your team writes these in English).

## Pipeline (precise steps)

### Step 0 — identity, auth, schema

- Verify the Linear MCP is authenticated. If not, abort loud with auth instructions.
- Resolve identity once:
  - `LINEAR_USER_ID = <user_handle.linear_user_id>`
  - `GH_USERNAME = <user_handle.github>`
  - `EMAIL = <user_handle.email>`
  - `WORK_REPO = <work-repo>`
  - `VAULT = <vault>`
- If the project maps to a vault note (search `<VAULT>/notes/` for the project), read it + grep recent memories in `~/.claude/projects/<cc-project-dir>/memory/` for the project slug. Never operate from memory alone.

### Step 1 — resolve project + window + reference format

- `get_project(query=<project>, includeMilestones=true)` → name, milestones (name / progress / targetDate), `targetDate`, initiatives, `lead`. Confirm `lead` is you; if not, warn (you're reporting on someone else's project).
- `get_status_updates(type=project, user=me, orderBy=createdAt, limit=5)` then **filter client-side** to `project.id == <id>`. ⚠️ Filtering `get_status_updates` by `project` directly returns `[]` (MCP limitation, verified 2026-06-17) — always query by `user=me` and filter on `project.id`. Take the latest matching update:
  - Latest update's `createdAt` = the time window's lower bound (unless `--since`).
  - Latest update's `body` = the **reference** for section headers, language, and emoji style. For bullet style always use the compact one-tag-per-bullet format below (even if an older update grouped bullets under `*Shipped:*` / `*Learnt:*` sub-headers — that grouping is deprecated). If no prior update, use the default format below.

### Step 2 — collect activity since the bound

Gather raw signal, then synthesize. Pull from all three sources:

1. **Linear issues** — `list_issues(project=<UUID>, team=<key>, limit=200)` (use the project **UUID** from `get_project.id`, NOT the slug — the slug returns `[]`). The MCP can blow the token cap; if it errors, it saves the result to a file — read it and parse with `jq` (`.issues[] | {identifier, statusType, status, completedAt, startedAt, canceledAt, projectMilestone, gitBranchName, url}`). Bucket by:
   - `completedAt >= bound` → **Shipped** candidates.
   - `statusType == "started"` (and not completed) → in-flight / **Focus** candidates.
   - `canceledAt >= bound` → scope changes worth a one-liner.
   - Milestone `progress` jumps → Linear auto-generates the progress diff on save (`diffMarkdown`), so **do NOT hand-write "X% → Y%"** in the body; it's redundant.
2. **Git** — in `<WORK_REPO>`: `git log --since=<bound> --author="<EMAIL>" --date=short --all`. Filter to the project by matching commit subjects/branches against (a) issue identifiers + `gitBranchName` from step 1, and (b) keywords derived from the project name. Use commits as ground truth for "what actually shipped in code".
3. **PRs** — extract `#NNNNN` from commits and issue branches; `gh pr view <n> --json number,title,state,url` for each. Use real state: OPEN → "in review", MERGED → "shipped to main". Never report a PR as merged without checking.
4. **Vault** — the project note + recent memories often hold decisions/answers not yet in Linear (e.g. a sync's outcomes). Fold these into **Learnt**.

### Step 3 — synthesize in the reference format

Write the body mirroring Step 1's reference. Default format (team standard) if no prior update:

One short bold tag per bullet, no sub-bucket grouping:

```
**✨ Highlights**

* **Shipped** - <closed milestone, merged PR, completed issue — past tense, biggest impact first>
* **Learnt** - <gotcha or technical finding worth sharing>
* **Decided** - <decision settled, answer from a sync (name who)>

**🤕 Lowlights**

* **Delayed** / **Blocked** / **Paused** - <slipped/blocked/paused work + the cause>

**🎯 Focus for this week**

* **Ship** - <next concrete step, tied to the current milestone>
```

Rules:
- Concise, factual, your voice (short, technical, no fluff, no AI polish). Keep technical terms in English.
- **One short bold tag per bullet**, no `*Shipped:*` sub-headers. Reuse the prior update's tags (Shipped / Learnt / Decided / Delayed / Blocked / Paused / Ship / Frame / Monitor / Follow-up...); invent one if it fits.
- **Short + impact-first**: 1-2 lines per bullet, biggest ship leads Highlights. 3+ chained clauses → split or cut.
- **No em dash.** Use commas, colons, periods. (When mirroring a prior update that used em dashes, still drop them.)
- Reference issues/PRs inline (e.g. `<org>/<repo>#96919` linkifies on Linear).
- Don't restate the milestone % diff (Linear adds it).
- Set `health`: `onTrack` by default; `atRisk` if a sub-100% milestone's `targetDate` is within ~3 days or passed; `offTrack` if a milestone is clearly blocked. State the reasoning to you, let you override.

### Step 4 — double-check (mandatory)

Before presenting, verify every claim against the sources collected:
- Each PR number → state matches what `gh` returned (OPEN vs MERGED).
- Each "milestone closed" → progress is actually 100% in `get_project`.
- No invented numbers, no claim without a source. Fix typos / broken English.
- Flag any tension (e.g. milestone shows 100% but PRs still OPEN → say "in review", not "closed").

### Step 5 — output (draft, no auto-post)

- Write the draft to `<VAULT>/journal/<YYYY-MM-DD>-<project-slug>-linear-update.md` (frontmatter: project, window, health) AND print to stdout.
- Print the proposed `health` + a one-line "sources" trailer (milestones, issues, commits window, PRs checked, vault).
- **Stop here unless `--post`.** Ask: "post to Linear as a `<health>` status update? (y / adjust)". Only on explicit yes → `save_status_update(type=project, project=<id>, health=<health>, body=<final>)`.

## Notes

- Token cap: `list_issues` and `get_project` can exceed the MCP output limit. They auto-save to a file on overflow — read + `jq` it; don't retry blindly.
- Generic by design: works for any project you lead.
- Routine: a weekly cron fires this in **draft** mode and DMs/deposits the result for review. It does **not** pass `--post`. See the project's reporting routine.
