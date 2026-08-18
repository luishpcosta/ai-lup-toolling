#!/usr/bin/env bash
# Entrypoint do hook PostToolUse (Bash/exec) que reage a "git push". Rápido de
# propósito: só faz o gate (comando é git push? branch feature/*? automação
# habilitada?) e dispara o poller pesado em background. Nunca bloqueia a
# sessão do agente. Compatível com Claude Code e Devin CLI (ver README.md >
# "Compatibilidade com outras plataformas agênticas") — nenhuma das duas
# lógicas de gate depende de sintaxe específica de uma plataforma.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# O hook recebe o payload do evento via stdin (JSON) — formato compartilhado
# por Claude Code e Devin CLI (hook_event_name, tool_name, tool_input.command,
# cwd/session_id). branch/sha/remoto são resolvidos via git, não via parsing
# do JSON — mais robusto a variações de sintaxe do comando interceptado.
payload="$(cat)"
if command -v jq >/dev/null 2>&1; then
  command_text="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
else
  # jq não vem por padrão no Git for Windows/MSYS2 — fallback sem dependência
  # externa, só bash/grep/sed (ver extract_json_string_field em lib.sh).
  command_text="$(extract_json_string_field "$payload" "command")"
  cwd="$(extract_json_string_field "$payload" "cwd")"
fi
cwd="${cwd:-$PWD}"

# Defesa extra: alguns filtros de hook de plataforma só permitem filtrar por
# NOME da ferramenta (ex.: matcher "exec" no Devin CLI), não pelo conteúdo do
# comando (o "if": "Bash(git push *)" é um recurso específico do Claude Code).
# Sem essa checagem aqui, um hook registrado sem filtro de conteúdo dispararia
# este script a cada comando de shell, não só em pushes.
if [ -n "$command_text" ] && ! is_git_push_command "$command_text"; then
  exit 0
fi

branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

if [ -z "$branch" ] || ! is_feature_branch "$branch"; then
  # Não é push numa branch feature/* — não reage de forma alguma (nem log,
  # nem cria diretórios).
  exit 0
fi

feature_name="${branch#feature/}"
# Sanitiza para uso em nome de arquivo (branches feature/foo/bar têm "/" no meio).
feature_name_safe="${feature_name//\//-}"
log_dir="$cwd/.claude/logs"
mkdir -p "$log_dir" 2>/dev/null || true
discreet_log="$log_dir/pr-review-${feature_name_safe}.log"

if ! is_automation_enabled; then
  # Desligado por padrão: log discreto em arquivo, nada visível na sessão.
  printf '[%s] push detectado em %s — automação desligada (AGENT_PR_REVIEW_ENABLED != true)\n' \
    "$(date -Iseconds)" "$branch" >> "$discreet_log" 2>/dev/null || true
  exit 0
fi

# Dispara o poller pesado em background e devolve o controle imediatamente.
nohup "$SCRIPT_DIR/poll-and-review.sh" "$cwd" "$branch" "$feature_name" "$discreet_log" \
  >> "$discreet_log" 2>&1 < /dev/null &
disown

exit 0
