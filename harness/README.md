# Harness layer

The generic `~/.claude` configuration, version-controlled here so your setup travels with the vault. `bootstrap.sh` symlinks these into `~/.claude` (backing up any existing file first).

- **`CLAUDE.md`** — global constitution (behavioral defaults, loaded every session, all projects). Fill the `<...>` placeholders; keep it lean (deletion test). Behavioral detail lives in `feedback/`.
- **`settings.json`** — permissions / hooks / model. Ships **safe read-only defaults** (globs, not one-off literals) + vault read/edit/write. `bootstrap.sh` substitutes `<vault>` with your vault path. Extend as you go; prefer broad `Bash(<cmd>:*)` globs over per-command literals, and **never** whitelist a deletion (`rm`, `find:*`, in-place `sed`/`perl`) or `git push`.
- **`hooks/`** — mechanical guardrails (shell scripts run on tool events). Empty by default.
- **`agents/`** — custom subagents / personas. Empty by default.

Instance-specific content (your real profile, your full allowlist) lives in your vault clone, never committed back to this template.
