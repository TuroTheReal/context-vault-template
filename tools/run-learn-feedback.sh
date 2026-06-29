#!/usr/bin/env bash
# run-learn-feedback.sh — lance /learn-feedback ~1x/semaine, calé sur le JEUDI. MEME fonctionnement
# que daily-ingest : large fenêtre soir+matin, priorité soir + rattrapage matin. Distille tes
# préférences depuis la boucle propose→react des transcripts Claude Code, dans UNE PR
# vault-sync/<date>-feedback (couche feedback/, source de vérité), puis DM le lien. Review via la PR.
# Au merge, /learn-feedback --sync projette dans la memory. Fidélité stricte : mots/actions réels.
#
# Cible (TARGET) = le jeudi traité. Jeudi 17:00-23:59 → soir = aujourd'hui ; vendredi 00:00-10:00 →
# rattrapage du jeudi d'hier (seulement s'il a été raté, ex Mac fermé jeudi soir) ; sinon hors
# fenêtre → stop. Le stamp = date du jeudi traité → pas de doublon soir/matin, 1 seul run/semaine.
# (Jeudi pour éviter une grosse review le lundi matin.)
#
# Usage :
#   run-learn-feedback.sh            # = auto (launchd)
#   run-learn-feedback.sh manual     # force le run maintenant, ignore les gardes

set -uo pipefail

MODE="${1:-auto}"

VAULT="<vault>"
TOOLS="$VAULT/tools"
STAMP="$TOOLS/.learn-feedback-laststamp"   # date (YYYY-MM-DD) du dernier JEUDI traité
HOLIDAYS="$TOOLS/fr-holidays.txt"
TODAY="$(date +%F)"
DOW="$(date +%u)"          # 1=lundi … 7=dimanche (jeudi=4, vendredi=5)
TARGET="$TODAY"            # jeudi cible (réassigné en auto : soir=aujourd'hui, vendredi matin=hier)

# launchd démarre avec un PATH minimal : on rend claude/node trouvables.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/usr/bin:/bin"
CLAUDE_BIN="$(command -v claude || true)"

notify ()  { osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true; }
logline () { echo "$TODAY | learn-feedback($MODE) | $1" >> "$TOOLS/logs/runs.log"; }

if [[ "$MODE" != "manual" ]]; then
  # 1. fenêtre + cible (priorité soir, comme daily-ingest). Jeudi 17:00-23:59 → cible = aujourd'hui ;
  #    vendredi 00:00-10:00 → rattrapage du jeudi d'hier (seulement si raté) ; sinon hors fenêtre.
  NOW="$((10#$(date +%H%M)))"
  if   [[ "$DOW" -eq 4 && "$NOW" -ge 1700 ]]; then TARGET="$TODAY"
  elif [[ "$DOW" -eq 5 && "$NOW" -le 1000 ]]; then TARGET="$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)"
  else exit 0
  fi
  # 2. jour férié FR (sur le jeudi cible) → stop
  [[ -f "$HOLIDAYS" ]] && grep -qx "$TARGET" "$HOLIDAYS" && exit 0
  # 3. OOO (vault en pause) → stop
  grep -qE '^[[:space:]]*paused:[[:space:]]*true' "$VAULT/.vault-state.yml" 2>/dev/null && exit 0
  # 4. jeudi cible déjà traité → stop (le soir prime ; le matin ne rattrape que si le soir a été raté)
  [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$TARGET" ]] && exit 0
  # 5. hors-ligne → stop SANS marquer (réessaie au prochain tick)
  if ! curl -fsS --max-time 5 https://www.google.com -o /dev/null 2>&1; then
    exit 0
  fi
fi

if [[ -z "$CLAUDE_BIN" ]]; then
  logline "FAILED: binaire 'claude' introuvable dans le PATH"
  notify "Learn feedback" "claude CLI introuvable — vérifie le PATH dans run-learn-feedback.sh"
  exit 0
fi

cd "$VAULT" || { logline "FAILED: cd vault impossible"; exit 0; }

PROMPT='/learn-feedback

Une fois la PR feedback créée, envoie en DM Slack à moi-même (SLACK_USER_ID <user_handle.slack_user_id>) — ENVOI réel avec slack_send_message, JAMAIS un draft (pas slack_send_message_draft), et UNIQUEMENT ce self-DM (jamais un canal ni personne d'\''autre) :
1. le lien de la PR ;
2. un résumé : nombre de leçons créées / mises à jour, puis une ligne par leçon au format « <kind> · <scope> · <confidence>, <hook> ».
Self-DM UNIQUEMENT. Si rien de neuf à apprendre, ne crée pas de PR et ne DM rien.'

OUT="$("$CLAUDE_BIN" -p "$PROMPT" --dangerously-skip-permissions 2>&1)"; RC=$?

# Filet : la skill a pu laisser le repo sur une branche vault-sync → revenir sur main.
git -C "$VAULT" checkout main >/dev/null 2>&1 || true

if [[ $RC -ne 0 ]]; then
  printf '%s\n' "$OUT" > "$TOOLS/logs/learn-feedback.last-fail.log"
  if grep -qiE 'API Error|Stream idle|timeout|overloaded|rate.?limit' <<<"$OUT"; then
    logline "FAILED rc=$RC (API/timeout — retry au prochain tick)"
  else
    logline "FAILED rc=$RC (voir logs/learn-feedback.last-fail.log)"
  fi
  notify "Learn feedback KO" "Échec (code $RC) — retry au prochain tick"
  exit 0
fi
if grep -qiE 'auth.*(expir|fail|required)|unauthenticated|not authenticated' <<<"$OUT"; then
  printf '%s\n' "$OUT" > "$TOOLS/logs/learn-feedback.last-fail.log"
  logline "auth-error MCP"
  notify "Learn feedback" "Un MCP semble déconnecté — re-auth nécessaire"
  exit 0
fi

# Succès uniquement : marque le jeudi cible (un échec ne marque rien → re-tente au prochain tick)
echo "$TARGET" > "$STAMP"
logline "ok ($TARGET)"
