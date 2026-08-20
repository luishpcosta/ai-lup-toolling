#!/usr/bin/env bash
# Bloqueia spawn de subagente quando já há MAX ativos (spawnados há menos
# de TTL_SECONDS).
#
# TRIGGER: PreToolUse | MATCHER: "Agent" (Claude Code, confirmado). Nome no
#   Devin CLI NÃO CONFIRMADO — ver README antes de usar lá.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

GUARD="subagent-budget-guard"

is_resource_guard_enabled || exit 0

INPUT="$(cat)"
TOOL="$(read_tool_name "$INPUT")"
[ "$TOOL" = "Agent" ] || exit 0

MAX="$(resource_guard_max_subagents)"
TTL="$(resource_guard_ttl_seconds)"
TRACKER="$(resource_guard_tracker_path)"
mkdir -p "$(dirname "$TRACKER")" 2>/dev/null || true
NOW="$(date +%s)"

# Contar-e-gravar precisa ser uma operação só: sem o lock, dois spawns
# simultâneos leem a mesma contagem e os dois passam. Não conseguir o lock
# NÃO bloqueia o spawn (fail-open) — travar a sessão do agente por causa de
# um lock seria pior que deixar o orçamento estourar; fica registrado.
LOCK="${TRACKER}.lock"
LOCKED=false
if acquire_lock "$LOCK" 5 60; then
  LOCKED=true
  trap 'release_lock "$LOCK"' EXIT
else
  trace_log "$GUARD" WARNING "lock do tracker indisponível ($LOCK) — contagem pode ficar imprecisa"
fi

CONTENT=""
[ -f "$TRACKER" ] && CONTENT="$(cat "$TRACKER" 2>/dev/null)"

ACTIVE="$(count_active_entries "$CONTENT" "$NOW" "$TTL")"

if [ "$ACTIVE" -ge "$MAX" ]; then
  MSG="$ACTIVE subagentes ativos (máximo: $MAX) — espere terminarem"
  echo "BLOCKED [$GUARD]: $MSG" >&2
  trace_log "$GUARD" BLOCKED "$MSG"
  exit 2
fi

# Grava a poda + o novo spawn de uma vez, via arquivo temporário e mv: sem
# isso a reescrita truncava o tracker e outro guard podia lê-lo vazio no
# meio. Sem o lock, cai no append simples (atômico, mas não poda).
PRUNED="$(prune_active_entries "$CONTENT" "$NOW" "$TTL")"
if [ "$LOCKED" = "true" ]; then
  TMP="${TRACKER}.tmp.$$"
  {
    [ -n "$PRUNED" ] && printf '%s\n' "$PRUNED"
    printf '%s|agent\n' "$NOW"
  } > "$TMP" 2>/dev/null && mv "$TMP" "$TRACKER" 2>/dev/null || {
    rm -f "$TMP" 2>/dev/null || true
    printf '%s|agent\n' "$NOW" >> "$TRACKER" 2>/dev/null || true
  }
else
  printf '%s|agent\n' "$NOW" >> "$TRACKER" 2>/dev/null || true
fi

exit 0
