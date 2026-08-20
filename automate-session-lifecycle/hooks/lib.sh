#!/usr/bin/env bash
# Funções puras + log de auditoria dos hooks de ciclo de vida de sessão
# (checkpoint de compactação, warmup de MCP). Nenhum bloqueia nada — são
# ações de melhor esforço. Testes: hooks/tests/run-tests.sh.

# --- compact-checkpoint -----------------------------------------------------

# Conta linhas não-vazias de "git status --porcelain".
count_changed_files() {
  local output="$1"
  [ -z "$output" ] && { echo 0; return; }
  printf '%s\n' "$output" | grep -c .
}

# Args: file_count timestamp_utc
format_checkpoint_commit_message() {
  local count="$1" timestamp="$2"
  printf 'checkpoint: pre-compact auto-save (%s files, %s)' "$count" "$timestamp"
}

# Args: file_count branch
format_checkpoint_notice() {
  local count="$1" branch="$2"
  printf 'Checkpoint pré-compactação: %s arquivo(s) salvos em %s\n  Recupere com: git log --oneline -5' \
    "$count" "$branch"
}

# --- mcp-warmup-wait ---------------------------------------------------------

config_declares_mcp_servers() {
  printf '%s' "$1" | grep -q '"mcpServers"'
}

format_warmup_notice() {
  local seconds="$1"
  printf 'MCP warmup: aguardou %ds para inicialização do servidor' "$seconds"
}

# --- Config -----------------------------------------------------------------

load_config_env() {
  local config_file="$1"
  [ -f "$config_file" ] || return 0

  local vars=(SESSION_LIFECYCLE_CHECKPOINT_ENABLED SESSION_LIFECYCLE_WARMUP_ENABLED
    SESSION_LIFECYCLE_WARMUP_SECONDS SESSION_LIFECYCLE_TRACE_LOG_PATH)
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

is_checkpoint_enabled() {
  [ "${SESSION_LIFECYCLE_CHECKPOINT_ENABLED:-true}" != "false" ]
}

is_warmup_enabled() {
  [ "${SESSION_LIFECYCLE_WARMUP_ENABLED:-true}" != "false" ]
}

warmup_seconds() {
  echo "${SESSION_LIFECYCLE_WARMUP_SECONDS:-3}"
}

# --- Trace log --------------------------------------------------------------
# Mesmo padrão de automate-review/hooks/lib.sh. Registra cada ação real
# tomada (commit criado, warmup esperado). Best-effort.

_data_dir() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s' "$dir"
}

# Default: data/trace.log nesta pasta. Override via
# SESSION_LIFECYCLE_TRACE_LOG_PATH (config.env ou env var).
trace_log_path() {
  if [ -n "${SESSION_LIFECYCLE_TRACE_LOG_PATH:-}" ]; then
    mkdir -p "$(dirname "$SESSION_LIFECYCLE_TRACE_LOG_PATH")" 2>/dev/null || true
    printf '%s' "$SESSION_LIFECYCLE_TRACE_LOG_PATH"
  else
    printf '%s/trace.log' "$(_data_dir)"
  fi
}

# Args: timestamp_iso guard decision detail
format_trace_line() {
  local ts="$1" guard="$2" decision="$3" detail="${4:-}"
  printf '[%s] guard=%s decision=%s%s\n' "$ts" "$guard" "$decision" "${detail:+ detail=$detail}"
}

# Args: guard decision [detail]
trace_log() {
  format_trace_line "$(date -Iseconds)" "$1" "$2" "${3:-}" >> "$(trace_log_path)" 2>/dev/null || true
}
