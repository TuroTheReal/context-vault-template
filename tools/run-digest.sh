#!/usr/bin/env bash
# run-digest.sh — lance /daily-digest une fois par jour ouvré, la première fois
# que le Mac est réveillé ET connecté. Déclenché par launchd (mode "auto", poll 15 min
# + RunAtLoad) ou à la main (mode "manual", bypass des gardes).
#
# Usage :
#   run-digest.sh            # = auto (utilisé par launchd)
#   run-digest.sh manual     # force le run maintenant, ignore les gardes
#
# Le mécanisme de high-water mark de /fetch-sources garantit que, peu importe QUAND
# il tourne, il récupère tout depuis le dernier fetch réussi jusqu'à maintenant.

set -uo pipefail

MODE="${1:-auto}"

VAULT="<vault>"
TOOLS="$VAULT/tools"
STAMP="$TOOLS/.digest-laststamp"
HOLIDAYS="$TOOLS/fr-holidays.txt"
TODAY="$(date +%F)"      # YYYY-MM-DD
DOW="$(date +%u)"        # 1=lundi … 7=dimanche

# launchd démarre avec un PATH minimal : on rend claude/node trouvables.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/usr/bin:/bin"
CLAUDE_BIN="$(command -v claude || true)"

notify ()  { osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true; }
logline () { echo "$TODAY | daily-digest($MODE) | $1" >> "$TOOLS/logs/runs.log"; }

if [[ "$MODE" != "manual" ]]; then
  # 1. week-end → stop
  [[ "$DOW" -ge 6 ]] && exit 0
  # 1bis. hors fenêtre 08:00–09:35 → stop (fenêtre du matin, pas toute la journée ;
  #       protège aussi contre un job launchd recollé tard après une veille)
  NOW_HM="$(date +%H%M)"
  { [[ "$((10#$NOW_HM))" -lt 800 ]] || [[ "$((10#$NOW_HM))" -gt 935 ]]; } && exit 0
  # 2. jour férié FR → stop
  [[ -f "$HOLIDAYS" ]] && grep -qx "$TODAY" "$HOLIDAYS" && exit 0
  # 2bis. OOO (vault en pause) → stop
  grep -qE '^[[:space:]]*paused:[[:space:]]*true' "$VAULT/.vault-state.yml" 2>/dev/null && exit 0
  # 3. déjà tourné aujourd'hui → stop
  [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$TODAY" ]] && exit 0
  # 4. hors-ligne → stop SANS marquer le jour (réessaie au prochain tick)
  if ! ping -c1 -t3 1.1.1.1 >/dev/null 2>&1 && ! curl -fsS --max-time 4 https://slack.com -o /dev/null 2>&1; then
    exit 0
  fi
fi

if [[ -z "$CLAUDE_BIN" ]]; then
  logline "FAILED: binaire 'claude' introuvable dans le PATH"
  notify "Daily digest" "claude CLI introuvable — vérifie le PATH dans run-digest.sh"
  exit 0
fi

cd "$VAULT" || { logline "FAILED: cd vault impossible"; exit 0; }

PROMPT='/daily-digest

Une fois le digest persisté sur disque, envoie le markdown complet du digest en DM Slack à moi-même (SLACK_USER_ID <user_handle.slack_user_id>) — ENVOI réel avec slack_send_message, JAMAIS un draft (pas slack_send_message_draft), et UNIQUEMENT ce self-DM (jamais un canal ni personne d'\''autre). Self-DM UNIQUEMENT — ne l'\''envoie à personne d'\''autre ni dans un canal.'

OUT="$("$CLAUDE_BIN" -p "$PROMPT" --dangerously-skip-permissions 2>&1)"; RC=$?

if [[ $RC -ne 0 ]]; then
  printf '%s\n' "$OUT" > "$TOOLS/logs/daily-digest.last-fail.log"
  if grep -qiE 'API Error|Stream idle|timeout|overloaded|rate.?limit' <<<"$OUT"; then
    logline "FAILED rc=$RC (API/timeout — retry au prochain tick)"
  else
    logline "FAILED rc=$RC (voir logs/daily-digest.last-fail.log)"
  fi
  notify "Daily digest KO" "Échec (code $RC) — retry au prochain tick"
  exit 0
fi
if grep -qiE 'auth.*(expir|fail|required)|unauthenticated|not authenticated' <<<"$OUT"; then
  printf '%s\n' "$OUT" > "$TOOLS/logs/daily-digest.last-fail.log"
  logline "auth-error MCP"
  notify "Daily digest" "Un MCP semble déconnecté — re-auth nécessaire"
  exit 0
fi

# Succès uniquement : marque le jour (un échec ne marque rien → le poll re-tente dans la fenêtre)
echo "$TODAY" > "$STAMP"
logline "ok"
