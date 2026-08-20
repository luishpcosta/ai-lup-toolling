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

is_resource_guard_enabled || exit 0

INPUT="$(cat)"
TOOL="$(read_tool_name "$INPUT")"
[ "$TOOL" = "Agent" ] || exit 0

MAX="$(resource_guard_max_subagents)"
TTL="$(resource_guard_ttl_seconds)"
TRACKER="$(resource_guard_tracker_path)"
mkdir -p "$(dirname "$TRACKER")" 2>/dev/null || true
NOW="$(date +%s)"

CONTENT=""
[ -f "$TRACKER" ] && CONTENT="$(cat "$TRACKER")"

ACTIVE="$(count_active_entries "$CONTENT" "$NOW" "$TTL")"

if [ "$ACTIVE" -ge "$MAX" ]; then
  MSG="$ACTIVE subagentes ativos (máximo: $MAX) — espere terminarem"
  echo "BLOCKED [subagent-budget-guard]: $MSG" >&2
  audit_log "subagent-budget-guard" BLOCKED "$MSG"
  exit 2
fi

printf '%s|agent\n' "$NOW" >> "$TRACKER"
PRUNED="$(prune_active_entries "$(cat "$TRACKER")" "$NOW" "$TTL")"
printf '%s\n' "$PRUNED" > "$TRACKER"

exit 0
