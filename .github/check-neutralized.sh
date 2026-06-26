#!/usr/bin/env bash
#
# check-neutralized.sh — fail if the PUBLIC template leaks real identifiers.
#
# The template is fed by a manual neutralization step (real vault -> placeholders).
# This guard asserts that the OPERATIONAL files contain only placeholders, so a
# missed find/replace never reaches the public repo.
#
# Scope: skills/, tools/, config/schema. README.md, LICENSE and .github/ are
# EXCLUDED on purpose — that is author metadata where the maintainer's name,
# handle and blog links are intentional, not a leak.
#
# Exit 0 = clean, 1 = leak found (prints file:line:match per hit).
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# Operational files only (keep existing paths).
CANDIDATES=(skills tools CLAUDE.md .vault-config.yml.example .vault-state.yml.example index.md log.md bootstrap.sh)
SCOPE=()
for p in "${CANDIDATES[@]}"; do [[ -e "$p" ]] && SCOPE+=("$p"); done

fail=0
report () { printf '❌ %s\n' "$1"; printf '%s\n' "$2" | sed 's/^/    /'; fail=1; }

# 1. Absolute home paths (a leaked vault_path / hard-coded local path).
hits="$(grep -rEn '/Users/[A-Za-z0-9._-]+' "${SCOPE[@]}" || true)"
[[ -n "$hits" ]] && report "absolute /Users/ path" "$hits"

# 2. Real e-mail addresses (the placeholder domain example.com is allowed).
hits="$(grep -rEon '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "${SCOPE[@]}" | grep -v '@example\.com' || true)"
[[ -n "$hits" ]] && report "real e-mail (non example.com)" "$hits"

# 3. Slack user/DM id leaked in a slack-id CONTEXT (config field or automation prompt).
#    Real ids look like U0.../D0... (a digit right after the prefix); the placeholders are
#    U00000000 / D00000000. ALLCAPS words (UNIQUEMENT, DISCUSSION) have no digit there, and
#    channel-id doc examples live outside any slack-id keyword line, so both are tolerated.
hits="$(grep -rEin 'slack_user_id|slack_dm_id|SLACK_USER_ID' "${SCOPE[@]}" \
        | grep -E '[UD][0-9][A-Z0-9]{6,}' | grep -vE '[UD]0{8}' || true)"
[[ -n "$hits" ]] && report "Slack id (non-placeholder, in slack-id context)" "$hits"

# 4. UUIDs (a leaked Notion / Linear user id — the placeholders are empty strings).
hits="$(grep -rEon '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' "${SCOPE[@]}" || true)"
[[ -n "$hits" ]] && report "UUID (possible Notion/Linear id)" "$hits"

# 5. Optional PRIVATE extension (gitignored, NOT committed): a maintainer lists
#    their own company / name markers here (one grep -E pattern per line) so the
#    public template stays neutral while local / pre-commit runs still catch them.
#    Absent in public CI by design — keep this file in your private vault.
EXTRA="$ROOT/.github/neutralize-extra.txt"
if [[ -f "$EXTRA" ]]; then
  while IFS= read -r pat; do
    [[ -z "$pat" || "$pat" == \#* ]] && continue
    hits="$(grep -rEin -- "$pat" "${SCOPE[@]}" || true)"
    [[ -n "$hits" ]] && report "private marker /$pat/" "$hits"
  done < "$EXTRA"
fi

if [[ "$fail" -eq 0 ]]; then
  echo "✅ template neutralized — no real identifiers in operational files"
fi
exit "$fail"
