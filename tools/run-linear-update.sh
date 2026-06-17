#!/usr/bin/env bash
# run-linear-update.sh — lance /linear-project-update une fois par semaine (mardi 13:30-14:30),
# la première fois que le Mac est réveillé ET connecté. Déclenché par launchd (mode "auto",
# poll 15 min) ou à la main (mode "manual", bypass des gardes).
#
# Usage :
#   run-linear-update.sh            # = auto (utilisé par launchd)
#   run-linear-update.sh manual     # force le run maintenant, ignore les gardes
#
# Produit un DRAFT et l'envoie en self-DM Slack. NE PUBLIE PAS sur Linear (relecture humaine).

set -uo pipefail

MODE="${1:-auto}"

VAULT="<vault>"
TOOLS="$VAULT/tools"
LOG="$VAULT/log.md"
STAMP="$TOOLS/.linear-update-laststamp"
HOLIDAYS="$TOOLS/fr-holidays.txt"
TODAY="$(date +%F)"        # YYYY-MM-DD
DOW="$(date +%u)"          # 1=lundi … 7=dimanche
WEEK="$(date +%GW%V)"      # année-semaine ISO (ex 2026W25), pour ne tourner qu'1×/semaine

# launchd démarre avec un PATH minimal : on rend claude/node trouvables.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/usr/bin:/bin"
CLAUDE_BIN="$(command -v claude || true)"

notify ()  { osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true; }
logline () { echo "$TODAY | linear-update($MODE) | $1" >> "$LOG"; }

if [[ "$MODE" != "manual" ]]; then
  # 1. mardi uniquement → stop sinon
  [[ "$DOW" -ne 2 ]] && exit 0
  # 1bis. hors fenêtre 13:30–14:30 → stop (protège aussi un job recollé tard après veille)
  NOW_HM="$(date +%H%M)"
  { [[ "$((10#$NOW_HM))" -lt 1330 ]] || [[ "$((10#$NOW_HM))" -gt 1430 ]]; } && exit 0
  # 2. jour férié FR → stop (si mardi férié, l'update saute cette semaine)
  [[ -f "$HOLIDAYS" ]] && grep -qx "$TODAY" "$HOLIDAYS" && exit 0
  # 2bis. OOO (vault en pause) → stop
  grep -qE '^[[:space:]]*paused:[[:space:]]*true' "$VAULT/.vault-state.yml" 2>/dev/null && exit 0
  # 3. déjà tourné cette semaine → stop
  [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$WEEK" ]] && exit 0
  # 4. hors-ligne → stop SANS marquer la semaine (réessaie au prochain tick)
  if ! ping -c1 -t3 1.1.1.1 >/dev/null 2>&1 && ! curl -fsS --max-time 4 https://slack.com -o /dev/null 2>&1; then
    exit 0
  fi
fi

if [[ -z "$CLAUDE_BIN" ]]; then
  logline "FAILED: binaire 'claude' introuvable dans le PATH"
  notify "Linear update" "claude CLI introuvable — vérifie le PATH dans run-linear-update.sh"
  exit 0
fi

cd "$VAULT" || { logline "FAILED: cd vault impossible"; exit 0; }

PROMPT='/linear-project-update <example-project-slug>

NE PUBLIE PAS sur Linear (aucun save_status_update). Génère uniquement le DRAFT, puis envoie le markdown complet du draft en DM Slack à moi-même (SLACK_USER_ID <user_handle.slack_user_id>). Self-DM UNIQUEMENT — ne l'\''envoie à personne d'\''autre ni dans un canal.'

OUT="$("$CLAUDE_BIN" -p "$PROMPT" --dangerously-skip-permissions 2>&1)"; RC=$?

# Marque la semaine comme faite (évite que le poll relance après un run réussi).
echo "$WEEK" > "$STAMP"

if [[ $RC -ne 0 ]]; then
  logline "FAILED rc=$RC"
  notify "Linear update KO" "Échec du run (code $RC) — voir the-vault/log.md"
  exit 0
fi
if grep -qiE 'auth.*(expir|fail|required)|unauthenticated|not authenticated' <<<"$OUT"; then
  logline "auth-error MCP"
  notify "Linear update" "Un MCP semble déconnecté — re-auth nécessaire"
  exit 0
fi

logline "ok"
