#!/usr/bin/env bash
# mcp-warmup-wait.sh — espera um curto período no início da sessão pra dar
# tempo dos servidores MCP configurados subirem, evitando erro de
# "ferramenta indisponível" no primeiro turno (comum em sessões disparadas
# via trigger remoto/cron, onde a primeira mensagem chega antes do MCP
# estar pronto). Portado de yurukusa/cc-safe-setup
# (examples/mcp-warmup-wait.sh).
#
# TRIGGER: SessionStart — mesmo nome de evento confirmado nas duas
#   plataformas (docs.devin.ai/cli/extensibility/hooks/lifecycle-hooks).
# MATCHER: nenhum.
#
# Só espera se algum arquivo de config candidato realmente declarar
# "mcpServers" — sessão sem MCP configurado não paga o custo do warmup.
# Verifica múltiplos caminhos candidatos (Claude Code E Devin CLI, ver
# README.md > "Onde procurar mcpServers") porque, diferente do
# cc-safe-setup original (que só olhava ~/.claude/settings.json), esta
# versão também roda sob Devin CLI, que pode ter a config em outro lugar.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

is_warmup_enabled || exit 0

SECONDS_TO_WAIT="$(warmup_seconds)"

# Caminhos candidatos de config MCP: Claude Code (global e por-projeto) +
# Devin CLI (global e por-projeto, conforme "Configuration Locations" da
# doc oficial). O primeiro que existir E declarar "mcpServers" já basta.
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

exit 0
