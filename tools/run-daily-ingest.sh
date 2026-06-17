#!/usr/bin/env bash
# run-daily-ingest.sh — lance /daily-ingest une fois par cycle (~24h), jours ouvrés, sur une
# LARGE fenêtre soir→matin 18:00→09:00 (au cas où le Mac n'est pas réveillé entre 20-21h).
# Déclenché par launchd (mode "auto", poll 30 min) ou à la main (mode "manual", bypass gardes).
#
# Produit UNE PR vault-sync/<date>-daily (notes atomiques du jour, sources + reasoning),
# puis DM le lien + un résumé. Review humaine via la PR. Fidélité stricte (cf. SKILL.md).
#
# Anti-doublon : la fenêtre traverse minuit, donc on ne se base PAS sur un stamp "jour" (qui
# relancerait le matin J+1 après un run le soir J). On utilise un MIN-INTERVAL de 16h : tant
# que le dernier run date de moins de 16h, on skip. → 1 run par cycle ~24h, zéro doublon.
# Le curseur last_ingest (dans /daily-ingest) garantit qu'aucun contenu n'est perdu, quelle
# que soit l'heure réelle du run.
#
# Usage :
#   run-daily-ingest.sh            # = auto (launchd)
#   run-daily-ingest.sh manual     # force le run maintenant, ignore les gardes

set -uo pipefail

MODE="${1:-auto}"

VAULT="<vault>"
TOOLS="$VAULT/tools"
LOG="$VAULT/log.md"
STAMP="$TOOLS/.daily-ingest-laststamp"   # epoch (date +%s) du dernier run
HOLIDAYS="$TOOLS/fr-holidays.txt"
TODAY="$(date +%F)"
DOW="$(date +%u)"          # 1=lundi … 7=dimanche
MIN_GAP=57600             # 16h en secondes — anti-doublon sur la fenêtre traversant minuit

# launchd démarre avec un PATH minimal : on rend claude/node trouvables.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/usr/bin:/bin"
CLAUDE_BIN="$(command -v claude || true)"

notify ()  { osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true; }
logline () { echo "$TODAY | daily-ingest($MODE) | $1" >> "$LOG"; }

if [[ "$MODE" != "manual" ]]; then
  # 1. week-end → stop (bilan des jours ouvrés)
  [[ "$DOW" -ge 6 ]] && exit 0
  # 1bis. fenêtre 18:00→09:00 (traverse minuit). Hors fenêtre = entre 09:00 et 18:00 → stop.
  NOW="$((10#$(date +%H%M)))"
  { [[ "$NOW" -ge 900 ]] && [[ "$NOW" -lt 1800 ]]; } && exit 0
  # 2. jour férié FR → stop
  [[ -f "$HOLIDAYS" ]] && grep -qx "$TODAY" "$HOLIDAYS" && exit 0
  # 2bis. OOO (vault en pause) → stop
  grep -qE '^[[:space:]]*paused:[[:space:]]*true' "$VAULT/.vault-state.yml" 2>/dev/null && exit 0
  # 3. déjà tourné dans les 16h → stop (anti-doublon soir/matin)
  if [[ -f "$STAMP" ]]; then
    gap=$(( $(date +%s) - $(cat "$STAMP" 2>/dev/null || echo 0) ))
    [[ "$gap" -lt "$MIN_GAP" ]] && exit 0
  fi
  # 4. hors-ligne → stop SANS marquer (réessaie au prochain tick)
  if ! ping -c1 -t3 1.1.1.1 >/dev/null 2>&1 && ! curl -fsS --max-time 4 https://slack.com -o /dev/null 2>&1; then
    exit 0
  fi
fi

if [[ -z "$CLAUDE_BIN" ]]; then
  logline "FAILED: binaire 'claude' introuvable dans le PATH"
  notify "Daily ingest" "claude CLI introuvable — vérifie le PATH dans run-daily-ingest.sh"
  exit 0
fi

cd "$VAULT" || { logline "FAILED: cd vault impossible"; exit 0; }

PROMPT='/daily-ingest

Une fois la PR vault-sync créée, envoie en DM Slack à moi-même (SLACK_USER_ID <user_handle.slack_user_id>) :
1. le lien de la PR ;
2. un résumé : nombre de notes créées / mises à jour, puis une ligne par note au format « ✏️ created|updated <note-name> — <résumé 1 ligne> ».
Self-DM UNIQUEMENT. Si rien de neuf à ingérer, ne crée pas de PR et ne DM rien.'

OUT="$("$CLAUDE_BIN" -p "$PROMPT" --dangerously-skip-permissions 2>&1)"; RC=$?

# Marque l'epoch du run (anti-doublon 16h + « déjà fait »).
date +%s > "$STAMP"

if [[ $RC -ne 0 ]]; then
  logline "FAILED rc=$RC"
  notify "Daily ingest KO" "Échec du run (code $RC) — voir the-vault/log.md"
  exit 0
fi
if grep -qiE 'auth.*(expir|fail|required)|unauthenticated|not authenticated' <<<"$OUT"; then
  logline "auth-error MCP"
  notify "Daily ingest" "Un MCP semble déconnecté — re-auth nécessaire"
  exit 0
fi

logline "ok"
