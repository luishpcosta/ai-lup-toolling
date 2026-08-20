#!/usr/bin/env bash
# Funções puras + leitura de stdin + log de auditoria do guard de
# recurso/orçamento (limite de subagentes ativos). Testes:
# hooks/tests/run-tests.sh.

# --- stdin JSON -----------------------------------------------------------
# Três camadas, da mais confiável para a menos: jq -> python3 -> regex (o
# Git Bash/MSYS2 não traz jq). A regex entende \" e \\ dentro do valor.

json_unescape() {
  printf '%s' "$1" | sed 's|\\\(["\\/]\)|\1|g'
}

# Args: json_text field_name
extract_json_string_field() {
  local json="$1" field="$2" raw
  raw="$(printf '%s' "$json" \
    | grep -oE "\"$field\"[[:space:]]*:[[:space:]]*\"(\\\\.|[^\"\\\\])*\"" \
    | head -1)"
  [ -z "$raw" ] && return 0
  raw="${raw#*:}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw#\"}"
  raw="${raw%\"}"
  json_unescape "$raw"
}

read_tool_name() {
  local payload="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c 'import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
value = payload.get("tool_name")
if isinstance(value, str):
    sys.stdout.write(value)
' 2>/dev/null
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

# --- Lock do tracker --------------------------------------------------------
# Ler-contar-gravar não é atômico: dois spawns em paralelo liam a mesma
# contagem e os dois passavam, estourando o limite; e a reescrita da poda
# (truncar + gravar) podia perder um append concorrente. mkdir é atômico em
# qualquer sistema de arquivos e existe no Git Bash — flock não.

_file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# Args: lock_dir [timeout_s] [stale_s] -> 0 se pegou o lock, 1 se desistiu.
acquire_lock() {
  local lock="$1" timeout="${2:-5}" stale="${3:-60}"
  local waited=0 mtime now
  while ! mkdir "$lock" 2>/dev/null; do
    now="$(date +%s)"
    mtime="$(_file_mtime "$lock")"
    # Lock abandonado (processo morto no meio da seção crítica): recupera.
    if [ "$mtime" -gt 0 ] && [ $(( now - mtime )) -gt "$stale" ]; then
      rmdir "$lock" 2>/dev/null || true
      continue
    fi
    [ "$waited" -ge "$timeout" ] && return 1
    sleep 1
    waited=$((waited + 1))
  done
  return 0
}

release_lock() {
  rmdir "$1" 2>/dev/null || true
}

# --- Config -----------------------------------------------------------------

load_config_env() {
  local config_file="$1"
  [ -f "$config_file" ] || return 0

  local vars=(RESOURCE_GUARD_ENABLED RESOURCE_GUARD_MAX_SUBAGENTS RESOURCE_GUARD_TTL_SECONDS
    RESOURCE_GUARD_TRACKER_PATH RESOURCE_GUARD_TRACE_LOG_PATH)
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

# Um valor não-numérico no config.env viraria erro de aritmética em TODO
# spawn de subagente — cai no default em vez de quebrar o guard.
# Args: value default
_positive_int_or_default() {
  case "${1:-}" in
    ''|*[!0-9]*) printf '%s' "$2" ;;
    0) printf '%s' "$2" ;;
    *) printf '%s' "$1" ;;
  esac
}

resource_guard_max_subagents() {
  _positive_int_or_default "${RESOURCE_GUARD_MAX_SUBAGENTS:-}" 5
}

resource_guard_ttl_seconds() {
  _positive_int_or_default "${RESOURCE_GUARD_TTL_SECONDS:-}" 1800
}

# Compartilhado por máquina, fora desta pasta de ferramenta.
resource_guard_tracker_path() {
  echo "${RESOURCE_GUARD_TRACKER_PATH:-$HOME/.claude/active-agents}"
}

# --- Trace log --------------------------------------------------------------
# Mesmo padrão de automate-review/hooks/lib.sh. Só BLOCKED (spawn negado por
# orçamento). Best-effort.

_data_dir() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s' "$dir"
}

# Default: data/trace.log nesta pasta. Override via
# RESOURCE_GUARD_TRACE_LOG_PATH (config.env ou env var).
trace_log_path() {
  if [ -n "${RESOURCE_GUARD_TRACE_LOG_PATH:-}" ]; then
    mkdir -p "$(dirname "$RESOURCE_GUARD_TRACE_LOG_PATH")" 2>/dev/null || true
    printf '%s' "$RESOURCE_GUARD_TRACE_LOG_PATH"
  else
    printf '%s/trace.log' "$(_data_dir)"
  fi
}

# Uma entrada do trace log é UMA linha.
sanitize_trace_detail() {
  local detail="$1"
  detail="$(printf '%s' "$detail" | tr '\n\r\t' '   ')"
  if [ "${#detail}" -gt 500 ]; then
    detail="${detail:0:500}…"
  fi
  printf '%s' "$detail"
}

# Args: timestamp_iso guard decision detail
format_trace_line() {
  local ts="$1" guard="$2" decision="$3" detail="${4:-}"
  printf '[%s] guard=%s decision=%s%s\n' "$ts" "$guard" "$decision" "${detail:+ detail=$detail}"
}

# Args: guard decision [detail]
trace_log() {
  format_trace_line "$(date -Iseconds)" "$1" "$2" "$(sanitize_trace_detail "${3:-}")" \
    >> "$(trace_log_path)" 2>/dev/null || true
}
