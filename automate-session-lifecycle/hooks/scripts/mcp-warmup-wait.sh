#!/usr/bin/env bash
# Espera um curto período no início da sessão pros servidores MCP subirem,
# evitando erro de "ferramenta indisponível" no primeiro turno.
#
# TRIGGER: SessionStart (mesmo nome nas duas plataformas). Só espera se
#   algum arquivo de config candidato declarar "mcpServers" (ver README >
#   "Onde procurar mcpServers" pra lista de caminhos, Claude Code + Devin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

is_warmup_enabled || exit 0

SECONDS_TO_WAIT="$(warmup_seconds)"

CANDIDATES=(
  "$HOME/.claude/settings.json"
  "$HOME/.claude/settings.local.json"
  "$HOME/.claude.json"
  "$HOME/.config/devin/config.json"
  "${DEVIN_PROJECT_DIR:-}/.devin/config.json"
  "${DEVIN_PROJECT_DIR:-}/.devin/config.local.json"
  "$PWD/.claude/settings.json"
  "$PWD/.claude/settings.local.json"
  "$PWD/.devin/config.json"
)

FOUND=0
for candidate in "${CANDIDATES[@]}"; do
  [ -z "$candidate" ] && continue
  [ -f "$candidate" ] || continue
  if config_declares_mcp_servers "$(cat "$candidate" 2>/dev/null)"; then
    FOUND=1
    break
  fi
done

[ "$FOUND" -eq 1 ] || exit 0

sleep "$SECONDS_TO_WAIT"
format_warmup_notice "$SECONDS_TO_WAIT" >&2
trace_log "mcp-warmup-wait" ACTION "esperou ${SECONDS_TO_WAIT}s (config: $candidate)"

exit 0
