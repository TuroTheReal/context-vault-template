#!/usr/bin/env bash
#
# bootstrap.sh — initialize a context vault from this template.
#
# Turns a fresh clone of this template into a working vault: creates the local
# config/state files, fills the one deterministic value (vault_path), wires the
# skills into Claude Code, and drops the template's maintainer-only CI (the
# neutralization guard is for the public template, not your private instance).
# Personal handles and the
# source toggles stay a manual edit (a handful of one-time fields) — this script
# does the mechanical toil, not the personal choices.
#
# Usage:
#   git clone <template> ~/vaults/my-context && cd ~/vaults/my-context
#   ./bootstrap.sh                       # core init (config + skills)
#   ./bootstrap.sh --with-automation     # + launchd scheduled agents (macOS only)
#
# Options:
#   --target DIR        Vault directory to initialize (default: this script's dir)
#   --skills-dir DIR    Where to symlink skills (default: ~/.claude/skills)
#   --with-automation   Substitute + install the launchd cron agents (macOS)
#   -h, --help          Show this help
#
# Prerequisites (checked, warned if missing — not fatal):
#   - claude CLI on PATH        (to run the skills)
#   - gh CLI authenticated      (for GitHub source sweeps)
#   - MCP servers connected     (one per enabled source: Slack, Notion, Linear, ...)
#
# The skills are config-driven: they read .vault-config.yml at runtime, so no
# substitution is needed in them. Only the optional automation layer (tools/)
# hard-codes paths and therefore gets substituted by --with-automation.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# --- defaults ----------------------------------------------------------------
TARGET="$SCRIPT_DIR"
SKILLS_DIR="${HOME}/.claude/skills"
WITH_AUTOMATION=false

# --- ui helpers --------------------------------------------------------------
info ()  { printf '  %s\n' "$1"; }
ok ()    { printf '✅ %s\n' "$1"; }
warn ()  { printf '⚠️  %s\n' "$1" >&2; }
die ()   { printf '❌ %s\n' "$1" >&2; exit 1; }
step ()  { printf '\n▶ %s\n' "$1"; }

usage () {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# Replace a line in place, portably (no sed -i — BSD/GNU differ).
# yaml_set KEY VALUE FILE  → rewrites the first 'KEY: ...' line, preserving indent.
yaml_set () {
  local key="$1" val="$2" file="$3" tmp
  tmp="$(mktemp)"
  sed "s|^\([[:space:]]*${key}\):.*|\1: ${val}|" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Substitute a literal token across a file, portably.
subst () {
  local token="$1" value="$2" file="$3" tmp
  tmp="$(mktemp)"
  sed "s|${token}|${value}|g" "$file" > "$tmp" && mv "$tmp" "$file"
}

# --- arg parsing -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)      TARGET="${2:?--target needs a directory}"; shift 2 ;;
    --skills-dir)  SKILLS_DIR="${2:?--skills-dir needs a directory}"; shift 2 ;;
    --with-automation) WITH_AUTOMATION=true; shift ;;
    -h|--help)     usage 0 ;;
    *)             warn "unknown option: $1"; usage 1 ;;
  esac
done

if ! resolved="$(cd "$TARGET" 2>/dev/null && pwd)"; then
  die "target not found: $TARGET"
fi
TARGET="$resolved"
[[ -f "$TARGET/CLAUDE.md" && -f "$TARGET/.vault-config.yml.example" ]] \
  || die "not a context-vault template (missing CLAUDE.md or .vault-config.yml.example): $TARGET"

printf '🌱 Bootstrapping context vault at: %s\n' "$TARGET"

# --- 1. config + state files -------------------------------------------------
step "Config files"
if [[ -f "$TARGET/.vault-config.yml" ]]; then
  warn ".vault-config.yml already exists — left untouched"
else
  cp "$TARGET/.vault-config.yml.example" "$TARGET/.vault-config.yml"
  yaml_set "vault_path" "$TARGET" "$TARGET/.vault-config.yml"
  ok ".vault-config.yml created (vault_path auto-set)"
fi
if [[ -f "$TARGET/.vault-state.yml" ]]; then
  warn ".vault-state.yml already exists — left untouched"
else
  cp "$TARGET/.vault-state.yml.example" "$TARGET/.vault-state.yml"
  ok ".vault-state.yml created"
fi

# --- 2. wire skills into Claude Code -----------------------------------------
step "Skills → $SKILLS_DIR"
mkdir -p "$SKILLS_DIR"
linked=0
for skill_dir in "$TARGET"/skills/*/; do
  [[ -f "${skill_dir}SKILL.md" ]] || continue
  name="$(basename "$skill_dir")"
  link="$SKILLS_DIR/$name"
  if [[ -e "$link" || -L "$link" ]]; then
    warn "$name → already present, skipped"
  else
    ln -s "${skill_dir%/}" "$link"
    info "$name → linked"
    linked=$((linked + 1))
  fi
done
ok "$linked skill(s) linked"

# --- 2b. drop template-maintainer tooling (this is a private instance now) ---
step "Template tooling"
if [[ -d "$TARGET/.github" ]]; then
  rm -rf "$TARGET/.github"
  ok "removed .github/ (neutralization guard + template CI are maintainer-only)"
else
  info ".github/ already absent"
fi

# --- 3. optional automation layer (macOS launchd) ----------------------------
if [[ "$WITH_AUTOMATION" == true ]]; then
  step "Automation (launchd)"
  if [[ "$(uname)" != "Darwin" ]]; then
    warn "automation is macOS-only (launchd) — skipped on $(uname)"
  else
    read -r -p "  Slack user id for self-DM (e.g. U0XXXXXXX): " slack_id
    read -r -p "  launchd label user [$(id -un)]: " label_user
    label_user="${label_user:-$(id -un)}"
    agents_dir="$HOME/Library/LaunchAgents"
    mkdir -p "$agents_dir" "$TARGET/tools/logs"

    for sh in "$TARGET"/tools/run-*.sh; do
      [[ -f "$sh" ]] || continue
      subst "<vault>" "$TARGET" "$sh"
      subst "<user_handle.slack_user_id>" "$slack_id" "$sh"
      chmod +x "$sh"
    done
    ok "run scripts substituted"

    for plist in "$TARGET"/tools/com.user.*.plist; do
      [[ -f "$plist" ]] || continue
      base="$(basename "$plist")"                       # com.user.<x>.plist
      dest="$agents_dir/${base/com.user./com.${label_user}.}"
      subst "<vault>" "$TARGET" "$plist"
      subst "<user>" "$label_user" "$plist"
      cp "$plist" "$dest"
      launchctl unload "$dest" >/dev/null 2>&1 || true
      launchctl load "$dest" && info "loaded $(basename "$dest")"
    done
    ok "launchd agents installed"
  fi
fi

# --- 4. prerequisite hints ---------------------------------------------------
step "Prerequisites"
if command -v claude >/dev/null 2>&1; then info "claude CLI: found"; else warn "claude CLI: NOT on PATH"; fi
if command -v gh     >/dev/null 2>&1; then info "gh CLI: found";     else warn "gh CLI: NOT on PATH (GitHub sweep needs it)"; fi

# --- next steps --------------------------------------------------------------
cat <<EOF

🎯 Next steps (manual, one-time):
  1. Edit $TARGET/.vault-config.yml
       • user_handle.*  → your Slack / GitHub / Notion / Linear / email handles
       • fetch_sources  → set true only for the sources you actually use
       • git_remote     → "<owner>/<repo>" once you create the private repo
       (notion_user_id / linear_user_id resolve themselves on the first fetch)
  2. Make the repo private (it will hold personal context).
  3. Connect the MCP server for each enabled source.
  4. Try it:  cd $TARGET && claude   then  /fetch-sources  ·  /ingest <url>

Done. The vault is wired; fill the config and you're live.
EOF
