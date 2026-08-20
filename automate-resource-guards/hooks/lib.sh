#!/usr/bin/env bash
# Funções puras e testáveis dos guards de RECURSO/ORÇAMENTO PreToolUse —
# categoria distinta de automate-security/: aqui o risco não é segurança
# (exfiltração, acesso indevido), é a agente estourar recurso/custo
# (spawnar subagentes demais em paralelo). Mesmo mecanismo de bloqueio
# (PreToolUse, exit 2), origem/propósito diferentes — por isso pasta própria,
# não misturada em automate-security/ (ver README.md > "Por que uma pasta
# própria, separada de automate-security/").
#
# Vive em ~/development/tools/automate-resource-guards/hooks/, fora de
# qualquer repositório — cada repo que usa esta automação aponta seu hook
# para este local compartilhado.
#
# Origem: subagent-budget-guard.sh, portado de yurukusa/cc-safe-setup, com
# a lógica de contagem/expiração extraída em funções puras que operam sobre
# TEXTO (conteúdo do arquivo de tracking como string), não sobre o
# filesystem diretamente — a leitura/escrita real do arquivo fica só no
# entrypoint (ver hooks/guards/subagent-budget-guard.sh), mesma separação
# usada em automate-review/hooks/lib.sh e automate-security/hooks/lib.sh.

# --- Leitura do payload do hook (stdin JSON) -----------------------------
# Idêntica a automate-security/hooks/lib.sh — duplicada de propósito (cada
# pasta de ferramenta é independente e instalável sozinha, ver
# tools/README.md).

extract_json_string_field() {
  local json="$1" field="$2"
  printf '%s' "$json" \
    | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/"
}

read_tool_name() {
  local payload="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null
  else
    extract_json_string_field "$payload" "tool_name"
  fi
}

# --- Contagem/expiração de subagentes ativos (funções puras) ------------
# O arquivo de tracking é um log append-only de "<timestamp_unix>|agent" por
# linha — uma linha por spawn. "Ativo" = spawnado há menos de ttl_seconds.

# Conta quantas linhas do tracker (texto multi-linha, uma entrada
# "<ts>|agent" por linha) ainda estão dentro do TTL. Args: tracker_content now ttl_seconds
count_active_entries() {
  local content="$1" now="$2" ttl="$3"
  local count=0 line ts age
  [ -z "$content" ] && { echo 0; return; }
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    ts="${line%%|*}"
    case "$ts" in ''|*[!0-9]*) continue ;; esac
    age=$(( now - ts ))
    [ "$age" -lt "$ttl" ] && count=$((count + 1))
  done <<< "$content"
  echo "$count"
}

# Devolve só as linhas do tracker ainda dentro do TTL (poda as expiradas) —
# usado pra reescrever o arquivo depois de cada spawn, sem deixá-lo crescer
# pra sempre. Args: tracker_content now ttl_seconds
prune_active_entries() {
  local content="$1" now="$2" ttl="$3"
  local line ts age
  [ -z "$content" ] && return 0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    ts="${line%%|*}"
    case "$ts" in ''|*[!0-9]*) continue ;; esac
    age=$(( now - ts ))
    [ "$age" -lt "$ttl" ] && printf '%s\n' "$line"
  done <<< "$content"
}

# --- Config ---------------------------------------------------------------

load_config_env() {
  local config_file="$1"
  [ -f "$config_file" ] || return 0

  local vars=(RESOURCE_GUARD_ENABLED RESOURCE_GUARD_MAX_SUBAGENTS RESOURCE_GUARD_TTL_SECONDS)
  local var
  local -A prior=()

  for var in "${vars[@]}"; do
    [ -n "${!var+x}" ] && prior["$var"]="${!var}"
  done

  # shellcheck disable=SC1090
  source "$config_file"

  for var in "${vars[@]}"; do
    [ -n "${prior[$var]+x}" ] && printf -v "$var" '%s' "${prior[$var]}"
  done
}

load_config_env "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"

is_resource_guard_enabled() {
  [ "${RESOURCE_GUARD_ENABLED:-true}" != "false" ]
}

# Máximo de subagentes ativos simultâneos (default 5, override via
# RESOURCE_GUARD_MAX_SUBAGENTS no config.env ou no ambiente).
resource_guard_max_subagents() {
  echo "${RESOURCE_GUARD_MAX_SUBAGENTS:-5}"
}

# TTL (segundos) até um subagente ser considerado "não mais ativo" pra fins
# de contagem — default 1800s (30min), igual ao cc-safe-setup original.
resource_guard_ttl_seconds() {
  echo "${RESOURCE_GUARD_TTL_SECONDS:-1800}"
}

# Caminho do arquivo de tracking — compartilhado por máquina, fora desta
# pasta de ferramenta (mesmo caminho usado pelo script original do
# cc-safe-setup, ~/.claude/active-agents, pra não perder histórico de quem
# já tinha essa automação rodando).
resource_guard_tracker_path() {
  echo "${RESOURCE_GUARD_TRACKER_PATH:-$HOME/.claude/active-agents}"
}
