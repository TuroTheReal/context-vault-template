#!/usr/bin/env bash
# run-daily-ingest.sh — lance /daily-ingest une fois par cycle (~24h), jours ouvrés, sur une
# LARGE fenêtre soir→matin 18:00→10:00 (au cas où le Mac n'est pas réveillé entre 20-21h).
# Déclenché par launchd (mode "auto", poll 30 min) ou à la main (mode "manual", bypass gardes).
#
# Produit UNE PR vault-sync/<date>-daily (notes atomiques du jour, sources + reasoning),
# puis DM le lien + un résumé. Review humaine via la PR. Fidélité stricte (cf. SKILL.md).
#
# Priorité SOIR : le run du jour se fait le soir (18:00-23:59, soirée = aujourd'hui). Le matin
# (00:00-10:00) ne RATTRAPE que la soirée d'HIER si elle a été ratée (Mac fermé le soir). Le stamp
# = date de la dernière soirée traitée → pas de doublon soir/matin, rythme calé sur le soir.
# Le curseur last_ingest (dans /daily-ingest) garantit qu'aucun contenu n'est perdu.
#
# Usage :
#   run-daily-ingest.sh            # = auto (launchd)
#   run-daily-ingest.sh manual     # force le run maintenant, ignore les gardes

set -uo pipefail

MODE="${1:-auto}"

VAULT="<vault>"
TOOLS="$VAULT/tools"
STAMP="$TOOLS/.daily-ingest-laststamp"   # date (YYYY-MM-DD) de la dernière soirée traitée
HOLIDAYS="$TOOLS/fr-holidays.txt"
TODAY="$(date +%F)"
DOW="$(date +%u)"          # 1=lundi … 7=dimanche
TARGET="$TODAY"            # soirée cible (réassignée en auto: soir=aujourd'hui, matin=hier)

# launchd démarre avec un PATH minimal : on rend claude/node trouvables.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/usr/bin:/bin"
CLAUDE_BIN="$(command -v claude || true)"

notify ()  { osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true; }
logline () { echo "$TODAY | daily-ingest($MODE) | $1" >> "$TOOLS/logs/runs.log"; }

if [[ "$MODE" != "manual" ]]; then
  # 1. week-end → stop (bilan des jours ouvrés)
  [[ "$DOW" -ge 6 ]] && exit 0
  # 1bis. soirée-cible (priorité soir). soir 18:00-23:59 → soirée d'aujourd'hui ;
  #       matin 00:00-10:00 → rattrapage de la soirée d'HIER (seulement si elle a été ratée) ;
  #       09:01-17:59 → hors fenêtre, stop.
  NOW="$((10#$(date +%H%M)))"
  if   [[ "$NOW" -ge 1800 ]]; then TARGET="$TODAY"
  elif [[ "$NOW" -le 1000 ]];  then TARGET="$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)"
  else exit 0
  fi
  # 2. jour férié FR (sur la soirée cible) → stop
  [[ -f "$HOLIDAYS" ]] && grep -qx "$TARGET" "$HOLIDAYS" && exit 0
  # 2bis. OOO (vault en pause) → stop
  grep -qE '^[[:space:]]*paused:[[:space:]]*true' "$VAULT/.vault-state.yml" 2>/dev/null && exit 0
  # 3. soirée cible déjà traitée → stop (le soir prime ; le matin ne rattrape que si le soir a été raté)
  [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$TARGET" ]] && exit 0
  # 4. hors-ligne → stop SANS marquer (réessaie au prochain tick)
  if ! curl -fsS --max-time 5 https://www.google.com -o /dev/null 2>&1; then
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

Une fois la PR vault-sync créée, envoie en DM Slack à moi-même (SLACK_USER_ID <user_handle.slack_user_id>) — ENVOI réel avec slack_send_message, JAMAIS un draft (pas slack_send_message_draft), et UNIQUEMENT ce self-DM (jamais un canal ni personne d'\''autre) :
1. le lien de la PR ;
2. un résumé : nombre de notes créées / mises à jour, puis une ligne par note au format « ✏️ created|updated <note-name> — <résumé 1 ligne> ».
Self-DM UNIQUEMENT. Si rien de neuf à ingérer, ne crée pas de PR et ne DM rien.'

OUT="$("$CLAUDE_BIN" -p "$PROMPT" --dangerously-skip-permissions 2>&1)"; RC=$?

# Filet : /ingest a pu laisser le repo sur une branche vault-sync → revenir sur main.
git -C "$VAULT" checkout main >/dev/null 2>&1 || true

if [[ $RC -ne 0 ]]; then
  printf '%s\n' "$OUT" > "$TOOLS/logs/daily-ingest.last-fail.log"
  if grep -qiE 'API Error|Stream idle|timeout|overloaded|rate.?limit' <<<"$OUT"; then
    logline "FAILED rc=$RC (API/timeout — retry au prochain tick)"
  else
    logline "FAILED rc=$RC (voir logs/daily-ingest.last-fail.log)"
  fi
  notify "Daily ingest KO" "Échec (code $RC) — retry au prochain tick"
  exit 0
fi
if grep -qiE 'auth.*(expir|fail|required)|unauthenticated|not authenticated' <<<"$OUT"; then
  printf '%s\n' "$OUT" > "$TOOLS/logs/daily-ingest.last-fail.log"
  logline "auth-error MCP"
  notify "Daily ingest" "Un MCP semble déconnecté — re-auth nécessaire"
  exit 0
fi

# Succès uniquement : marque la soirée cible (un échec ne marque rien → le poll re-tente)
echo "$TARGET" > "$STAMP"
logline "ok"
