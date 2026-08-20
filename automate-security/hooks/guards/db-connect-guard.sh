#!/usr/bin/env bash
# Bloqueia conexão direta com DB remoto e operações destrutivas do Prisma.
#
# TRIGGER: PreToolUse | MATCHER: "Bash"/"PowerShell" (Claude Code), "exec"
#   (Devin CLI — "PowerShell" sem equivalente confirmado, ver README).
# NÃO bloqueia: mysql/psql local (sem -h), prisma generate.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

is_security_guard_enabled || exit 0

INPUT="$(cat)"
COMMAND="$(read_tool_command "$INPUT")"
[ -z "$COMMAND" ] && exit 0

GUARD="db-connect-guard"

block_if() {
  "$1" "$COMMAND" || return 0
  echo "BLOCKED [$GUARD]: $2" >&2
  audit_log "$GUARD" BLOCKED "$2 | cmd=$COMMAND"
  exit 2
}

block_if is_remote_sql_connect            "conexão direta com SQL remoto — use código de aplicação, não CLI"
block_if is_remote_redis_connect          "conexão direta com Redis remoto"
block_if is_prisma_destructive_command    "operação destrutiva do Prisma — confirme DATABASE_URL antes"

exit 0
