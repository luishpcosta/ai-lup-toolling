#!/usr/bin/env bash
# subagent-budget-guard.sh — bloqueia spawn de subagente quando já há
# MAX_SUBAGENTS ativos (spawnados há menos de TTL_SECONDS). Portado de
# yurukusa/cc-safe-setup (examples/subagent-budget-guard.sh) — mesma lógica
# de contagem/expiração, extraída em funções puras testáveis (ver ../lib.sh).
#
# TRIGGER: PreToolUse
# MATCHER: "Agent" no Claude Code (nome confirmado — é a ferramenta usada
#   nesta própria sessão pra spawnar subagentes). NÃO CONFIRMADO no Devin
#   CLI: a documentação pública consultada (docs.devin.ai/cli/extensibility/
#   hooks/{overview,lifecycle-hooks}) não lista um nome de ferramenta
#   distinto para spawn de subagente — ver README.md > "O que não está
#   confirmado" antes de confiar no matcher do examples/devin-hooks.json.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

is_resource_guard_enabled || exit 0

INPUT="$(cat)"
TOOL="$(read_tool_name "$INPUT")"
# Nome exato confirmado só para o Claude Code ("Agent"). Ver nota de matcher
# acima — se o Devin CLI expuser outro nome de ferramenta pra spawn de
# subagente, ajuste esta comparação (ou generalize para um match parcial)
# depois de confirmar via "/hooks" no Devin.
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
  echo "BLOCKED [subagent-budget-guard]: $ACTIVE subagentes ativos (máximo: $MAX)." >&2
  echo "Espere os agentes existentes terminarem antes de spawnar mais." >&2
  echo "Override: RESOURCE_GUARD_MAX_SUBAGENTS=10 em config.env" >&2
  exit 2
fi

printf '%s|agent\n' "$NOW" >> "$TRACKER"
PRUNED="$(prune_active_entries "$(cat "$TRACKER")" "$NOW" "$TTL")"
printf '%s\n' "$PRUNED" > "$TRACKER"

exit 0
