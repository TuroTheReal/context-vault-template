#!/usr/bin/env bash
# run-audit.sh — lance /audit-vault une fois par semaine (vendredi 14:00-16:00), la première
# fois que le Mac est réveillé ET connecté. Déclenché par launchd (mode "auto", poll 15 min)
# ou à la main (mode "manual", bypass des gardes).
#
# Read-only : produit un rapport dans audit/ (gitignoré) + une ligne dans log.md, puis envoie
# le RÉSUMÉ (compteurs + premières trouvailles) en self-DM Slack. Ne modifie RIEN dans le vault,
# n'ouvre aucune PR. Hygiène hebdo : notes stale, liens cassés, violations de schéma, et surtout
# attributions suspectes (check anti-hallucination = garde-fou fidélité).
#
# Usage :
#   run-audit.sh            # = auto (utilisé par launchd)
#   run-audit.sh manual     # force le run maintenant, ignore les gardes

set -uo pipefail

MODE="${1:-auto}"

VAULT="<vault>"
TOOLS="$VAULT/tools"
STAMP="$TOOLS/.audit-laststamp"
TODAY="$(date +%F)"
DOW="$(date +%u)"          # 1=lundi … 7=dimanche
WEEK="$(date +%GW%V)"      # année-semaine ISO (ex 2026W25), pour ne tourner qu'1×/semaine

# launchd démarre avec un PATH minimal : on rend claude/node trouvables.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/usr/bin:/bin"
CLAUDE_BIN="$(command -v claude || true)"

notify ()  { osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true; }
logline () { echo "$TODAY | audit($MODE) | $1" >> "$TOOLS/logs/runs.log"; }

if [[ "$MODE" != "manual" ]]; then
  # 1. vendredi uniquement → stop sinon
  [[ "$DOW" -ne 5 ]] && exit 0
  # 1bis. hors fenêtre 14:00–16:00 → stop (protège aussi un job recollé tard après veille)
  NOW_HM="$(date +%H%M)"
  { [[ "$((10#$NOW_HM))" -lt 1400 ]] || [[ "$((10#$NOW_HM))" -gt 1600 ]]; } && exit 0
  # 2. OOO (vault en pause) → stop. Pas de garde jour-férié : l'hygiène tourne le vendredi.
  grep -qE '^[[:space:]]*paused:[[:space:]]*true' "$VAULT/.vault-state.yml" 2>/dev/null && exit 0
  # 3. déjà tourné cette semaine → stop
  [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$WEEK" ]] && exit 0
  # 4. hors-ligne → stop SANS marquer la semaine (réessaie au prochain tick)
  if ! curl -fsS --max-time 5 https://www.google.com -o /dev/null 2>&1; then
    exit 0
  fi
fi

if [[ -z "$CLAUDE_BIN" ]]; then
  logline "FAILED: binaire 'claude' introuvable dans le PATH"
  notify "Audit vault" "claude CLI introuvable — vérifie le PATH dans run-audit.sh"
  exit 0
fi

cd "$VAULT" || { logline "FAILED: cd vault impossible"; exit 0; }

PROMPT='/audit-vault --output markdown

Une fois le rapport écrit dans audit/, envoie un RÉSUMÉ en DM Slack à moi-même (SLACK_USER_ID <user_handle.slack_user_id>) — ENVOI réel avec slack_send_message, JAMAIS un draft (pas slack_send_message_draft), et UNIQUEMENT ce self-DM (jamais un canal ni personne d'\''autre) :
1. les compteurs par check (stale-notes, broken-links, schema-violations, suspicious-attributions, etc.) ;
2. les premières trouvailles actionnables (max ~10 lignes) ;
3. le chemin du rapport complet (audit/audit-<date>.md).
Self-DM UNIQUEMENT. Si zéro trouvaille, envoie quand même une ligne « vault clean ».'

OUT="$("$CLAUDE_BIN" -p "$PROMPT" --dangerously-skip-permissions 2>&1)"; RC=$?

if [[ $RC -ne 0 ]]; then
  printf '%s\n' "$OUT" > "$TOOLS/logs/audit.last-fail.log"
  if grep -qiE 'API Error|Stream idle|timeout|overloaded|rate.?limit' <<<"$OUT"; then
    logline "FAILED rc=$RC (API/timeout — retry au prochain tick)"
  else
    logline "FAILED rc=$RC (voir logs/audit.last-fail.log)"
  fi
  notify "Audit vault KO" "Échec (code $RC) — retry au prochain tick"
  exit 0
fi
if grep -qiE 'auth.*(expir|fail|required)|unauthenticated|not authenticated' <<<"$OUT"; then
  printf '%s\n' "$OUT" > "$TOOLS/logs/audit.last-fail.log"
  logline "auth-error MCP"
  notify "Audit vault" "Un MCP semble déconnecté — re-auth nécessaire"
  exit 0
fi

# Succès uniquement : marque la semaine (un échec ne marque rien → le poll re-tente)
echo "$WEEK" > "$STAMP"
logline "ok"
