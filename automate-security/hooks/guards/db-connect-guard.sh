#!/usr/bin/env bash
# db-connect-guard.sh — bloqueia conexão direta com banco de dados remoto
# (mysql/psql/mongo/redis-cli com -h/--host) e operações destrutivas do
# Prisma (db push, migrate deploy/reset). Portado de yurukusa/cc-safe-setup
# (examples/db-connect-guard.sh) — mesma lógica de detecção, extraída em
# funções puras testáveis (ver ../lib.sh).
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"/"PowerShell" no Claude Code, "exec" no Devin CLI — ver
#   ../../examples/{claude-settings,devin-hooks}.json e a nota no README
#   sobre o matcher de PowerShell não ter equivalente confirmado no Devin.
#
# NÃO bloqueia: mysql/psql locais (sem -h), prisma generate (não muda
# dados) — mesmo comportamento do script original.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

is_security_guard_enabled || exit 0

INPUT="$(cat)"
COMMAND="$(read_tool_command "$INPUT")"
[ -z "$COMMAND" ] && exit 0

if is_remote_sql_connect "$COMMAND"; then
  echo "BLOCKED [db-connect-guard]: conexão direta com banco de dados remoto detectada." >&2
  echo "  Conexões remotas de DB deveriam passar por código de aplicação, não CLI direto." >&2
  echo "  Comando: $COMMAND" >&2
  exit 2
fi

if is_remote_redis_connect "$COMMAND"; then
  echo "BLOCKED [db-connect-guard]: conexão direta com Redis remoto detectada." >&2
  exit 2
fi

if is_prisma_destructive_command "$COMMAND"; then
  echo "BLOCKED [db-connect-guard]: operação destrutiva do Prisma detectada." >&2
  echo "  prisma db push/migrate pode destruir dados de produção." >&2
  echo "  Confirme se DATABASE_URL aponta pro ambiente correto." >&2
  exit 2
fi

exit 0
