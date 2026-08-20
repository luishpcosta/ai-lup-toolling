#!/usr/bin/env bash
# compact-checkpoint.sh — cria um commit de checkpoint automático quando a
# sessão do agente compacta o contexto, pra garantir que mudanças não
# commitadas sobrevivam mesmo que a compactação faça a agente perder noção
# de edições recentes. Recuperação trivial: "git log --oneline -5". Portado
# de yurukusa/cc-safe-setup (examples/pre-compact-checkpoint.sh).
#
# TRIGGER: PreCompact no Claude Code (fecha bem antes da compactação
#   acontecer) / PostCompaction no Devin CLI (fecha logo depois). Mesmo
#   script serve pros dois — ver README.md > "PreCompact vs PostCompaction"
#   pra por que isso é seguro (a compactação não toca arquivos em disco).
# MATCHER: nenhum suporte a matcher documentado em nenhuma plataforma —
#   sempre dispara no evento.
#
# DECISÃO/BLOQUEIO: nenhum — hook de notificação/melhor esforço, nunca
# bloqueia a sessão (sempre "exit 0", mesmo em erro do git).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

is_checkpoint_enabled || exit 0

# Não é repositório git — nada a fazer.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

PORCELAIN="$(git status --porcelain 2>/dev/null)"
COUNT="$(count_changed_files "$PORCELAIN")"
[ "$COUNT" -eq 0 ] && exit 0

TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
MESSAGE="$(format_checkpoint_commit_message "$COUNT" "$TIMESTAMP")"

git add -A 2>/dev/null
git commit -m "$MESSAGE" --no-verify >/dev/null 2>&1

# Lida depois do commit de propósito: num repositório sem nenhum commit
# ainda, "git rev-parse --abbrev-ref HEAD" antes do primeiro commit pode
# devolver o literal "HEAD" em vez do nome real da branch (achado testando
# manualmente esta versão) — depois do commit acima, sempre resolve certo.
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

format_checkpoint_notice "$COUNT" "$BRANCH" >&2

exit 0
