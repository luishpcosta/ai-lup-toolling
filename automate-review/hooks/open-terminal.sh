#!/usr/bin/env bash
# Abre a janela final rodando um ARQUIVO de script (nunca uma string de
# comando inline — ver README.md > "Trocar o terminal"). Uso:
#   open-terminal.sh <wsl2|gitbash> "<título>" "<script>"
#
# O interpretador vem de AGENT_PR_REVIEW_TERMINAL_CMD (array, config.env) —
# hoje precisa ser compatível com bash, porque o script gerado é sempre bash
# (ver README.md > "Trocar o terminal" para o porquê e as alternativas).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

environment="$1"
title="$2"
script="$3"

if [ "$environment" != "wsl2" ] && [ "$environment" != "gitbash" ]; then
  echo "ERRO: ambiente '$environment' não suportado para abertura de terminal." >&2
  exit 1
fi

# `--`: separa as opções do wt.exe do comando a executar.
if command -v wt.exe >/dev/null 2>&1; then
  wt.exe --title "$title" -- "${AGENT_PR_REVIEW_TERMINAL_CMD[@]}" "$script" &
  exit 0
fi
if command -v cmd.exe >/dev/null 2>&1; then
  cmd.exe /c start "$title" "${AGENT_PR_REVIEW_TERMINAL_CMD[@]}" "$script" &
  exit 0
fi
echo "ERRO: nem wt.exe nem cmd.exe disponíveis — não foi possível abrir o terminal." >&2
exit 1
