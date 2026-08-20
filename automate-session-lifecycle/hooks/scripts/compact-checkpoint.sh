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

is_checkpoint_enabled || exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

PORCELAIN="$(git status --porcelain 2>/dev/null)"
COUNT="$(count_changed_files "$PORCELAIN")"
[ "$COUNT" -eq 0 ] && exit 0

TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
MESSAGE="$(format_checkpoint_commit_message "$COUNT" "$TIMESTAMP")"

git add -A 2>/dev/null
git commit -m "$MESSAGE" --no-verify >/dev/null 2>&1

# Depois do commit de propósito: antes do 1º commit, "rev-parse
# --abbrev-ref HEAD" pode devolver o literal "HEAD" em vez do nome real.
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

format_checkpoint_notice "$COUNT" "$BRANCH" >&2
audit_log "compact-checkpoint" ACTION "commit criado ($COUNT arquivos) em $BRANCH"

exit 0
