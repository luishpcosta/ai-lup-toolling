#!/usr/bin/env bash
# Commit de checkpoint automático quando a sessão compacta o contexto —
# recuperação: "git log --oneline -5".
#
# TRIGGER: PreCompact (Claude Code) | PostCompaction (Devin CLI) — mesmo
#   script serve pros dois, compactação não altera arquivos em disco (ver
#   README > "PreCompact vs PostCompaction").
# Nunca bloqueia — sempre exit 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

HOOK="compact-checkpoint"

is_checkpoint_enabled || exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Commitar no meio de um merge/rebase/cherry-pick conclui a operação errada:
# marca conflitos como resolvidos e cria o commit da operação. Sai sem tocar
# em nada.
GIT_DIR_PATH="$(git rev-parse --git-dir 2>/dev/null)"
OPERATION="$(git_operation_in_progress "$GIT_DIR_PATH")"
if [ -n "$OPERATION" ]; then
  format_checkpoint_failure_notice "$OPERATION em andamento" >&2
  trace_log "$HOOK" SKIPPED "operação git em andamento: $OPERATION"
  exit 0
fi

PORCELAIN="$(git status --porcelain 2>/dev/null)"
COUNT="$(count_changed_files "$PORCELAIN")"
[ "$COUNT" -eq 0 ] && exit 0

TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
MESSAGE="$(format_checkpoint_commit_message "$COUNT" "$TIMESTAMP")"

# --show-current devolve vazio (não o literal "HEAD") em HEAD desanexado e
# funciona antes do 1º commit, diferente de "rev-parse --abbrev-ref HEAD".
BRANCH="$(git branch --show-current 2>/dev/null)"
[ -z "$BRANCH" ] && BRANCH="HEAD desanexado ($(git rev-parse --short HEAD 2>/dev/null || echo 'sem commits'))"

# O resultado do commit tem que ser conferido: antes, qualquer falha (índice
# travado, hook de commit recusando, sem identidade git configurada) era
# engolida e mesmo assim a sessão via "checkpoint salvo" e o trace log
# registrava um commit que não existia.
if ! ERROR_OUTPUT="$(git add -A 2>&1)"; then
  format_checkpoint_failure_notice "falha ao preparar os arquivos (git add)" >&2
  trace_log "$HOOK" FAILED "git add: $ERROR_OUTPUT"
  exit 0
fi

if ! ERROR_OUTPUT="$(git commit -m "$MESSAGE" --no-verify 2>&1)"; then
  format_checkpoint_failure_notice "git commit falhou" >&2
  trace_log "$HOOK" FAILED "git commit: $ERROR_OUTPUT"
  exit 0
fi

format_checkpoint_notice "$COUNT" "$BRANCH" >&2
trace_log "$HOOK" ACTION "commit criado ($COUNT arquivos) em $BRANCH"

exit 0
