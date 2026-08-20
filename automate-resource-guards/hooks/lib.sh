#!/usr/bin/env bash
# Funções puras + leitura de stdin + log de auditoria do guard de
# recurso/orçamento (limite de subagentes ativos). Testes:
# hooks/tests/run-tests.sh.

# --- stdin JSON -----------------------------------------------------------

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

# --- Contagem/expiração de subagentes ---------------------------------------
# Tracker: log append-only "<timestamp_unix>|agent" por linha, 1 por spawn.
# "Ativo" = spawnado há menos de ttl_seconds.

# Args: tracker_content now ttl_seconds -> quantas entradas ainda dentro do TTL
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

# Args: tracker_content now ttl_seconds -> só as linhas ainda dentro do TTL (poda)
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

# --- Config -----------------------------------------------------------------

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

resource_guard_max_subagents() {
  echo "${RESOURCE_GUARD_MAX_SUBAGENTS:-5}"
}

resource_guard_ttl_seconds() {
  echo "${RESOURCE_GUARD_TTL_SECONDS:-1800}"
}

# Compartilhado por máquina, fora desta pasta de ferramenta.
resource_guard_tracker_path() {
  echo "${RESOURCE_GUARD_TRACKER_PATH:-$HOME/.claude/active-agents}"
}

# --- Log de auditoria -------------------------------------------------------
# data/audit.log — só BLOCKED (spawn negado por orçamento). Best-effort.

_data_dir() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s' "$dir"
}

audit_log_path() {
  printf '%s/audit.log' "$(_data_dir)"
}

# Args: timestamp_iso guard decision detail
format_audit_line() {
  local ts="$1" guard="$2" decision="$3" detail="${4:-}"
  printf '[%s] guard=%s decision=%s%s\n' "$ts" "$guard" "$decision" "${detail:+ detail=$detail}"
}

# Args: guard decision [detail]
audit_log() {
  format_audit_line "$(date -Iseconds)" "$1" "$2" "${3:-}" >> "$(audit_log_path)" 2>/dev/null || true
}
