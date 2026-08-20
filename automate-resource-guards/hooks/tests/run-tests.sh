#!/usr/bin/env bash
# Testes das funções puras de ../lib.sh. Sem rede, sem framework novo.
# Uso: bash tests/run-tests.sh (a partir de ~/development/tools/automate-resource-guards/hooks/)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

pass=0
fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FALHOU: $desc — esperado '$expected', obtido '$actual'"
  fi
}

# --- read_tool_name --------------------------------------------------------

assert_eq "read_tool_name: extrai tool_name do payload" \
  "Agent" "$(read_tool_name '{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{}}')"

assert_eq "read_tool_name: payload sem tool_name -> vazio" \
  "" "$(read_tool_name '{"tool_input":{}}')"

# --- count_active_entries ---------------------------------------------------

assert_eq "count_active_entries: tracker vazio -> 0" \
  "0" "$(count_active_entries "" 1000 1800)"

tracker="900|agent
950|agent
980|agent"
assert_eq "count_active_entries: todas as 3 entradas dentro do TTL" \
  "3" "$(count_active_entries "$tracker" 1000 1800)"

tracker_mixed="100|agent
950|agent
980|agent"
assert_eq "count_active_entries: entrada expirada (idade > TTL) não conta" \
  "2" "$(count_active_entries "$tracker_mixed" 1000 500)"

assert_eq "count_active_entries: linha malformada (timestamp não-numérico) é ignorada, não quebra" \
  "1" "$(count_active_entries "lixo-sem-timestamp
950|agent" 1000 1800)"

assert_eq "count_active_entries: linhas em branco no meio são ignoradas" \
  "2" "$(count_active_entries "900|agent

980|agent" 1000 1800)"

# --- prune_active_entries ---------------------------------------------------

assert_eq "prune_active_entries: remove só a entrada expirada" \
  "950|agent
980|agent" \
  "$(prune_active_entries "100|agent
950|agent
980|agent" 1000 500)"

assert_eq "prune_active_entries: tracker vazio -> saída vazia" \
  "" "$(prune_active_entries "" 1000 1800)"

# --- load_config_env / getters ---------------------------------------------

_tmp_config="$(mktemp)"
cat > "$_tmp_config" <<'EOF'
RESOURCE_GUARD_MAX_SUBAGENTS=10
RESOURCE_GUARD_TTL_SECONDS=60
EOF
unset RESOURCE_GUARD_MAX_SUBAGENTS RESOURCE_GUARD_TTL_SECONDS
load_config_env "$_tmp_config"
assert_eq "resource_guard_max_subagents: lido do config.env" "10" "$(resource_guard_max_subagents)"
assert_eq "resource_guard_ttl_seconds: lido do config.env" "60" "$(resource_guard_ttl_seconds)"
rm -f "$_tmp_config"
unset RESOURCE_GUARD_MAX_SUBAGENTS RESOURCE_GUARD_TTL_SECONDS

assert_eq "resource_guard_max_subagents: default 5 sem config" "5" "$(resource_guard_max_subagents)"
assert_eq "resource_guard_ttl_seconds: default 1800 sem config" "1800" "$(resource_guard_ttl_seconds)"

unset RESOURCE_GUARD_ENABLED
assert_eq "is_resource_guard_enabled: true por default" "0" "$(is_resource_guard_enabled; echo $?)"
RESOURCE_GUARD_ENABLED=false
assert_eq "is_resource_guard_enabled: false quando explicitamente desligado" "1" "$(is_resource_guard_enabled; echo $?)"
unset RESOURCE_GUARD_ENABLED

# --- format_trace_line / trace_log / trace_log_path ------------------------

assert_eq "format_trace_line: com detail" \
  "[2026-01-01T00:00:00-03:00] guard=subagent-budget-guard decision=BLOCKED detail=5 ativos" \
  "$(format_trace_line "2026-01-01T00:00:00-03:00" "subagent-budget-guard" "BLOCKED" "5 ativos")"

unset RESOURCE_GUARD_TRACE_LOG_PATH
assert_eq "trace_log_path: default é data/trace.log dentro da pasta" \
  "$(cd "$SCRIPT_DIR/../.." && pwd)/data/trace.log" "$(trace_log_path)"

_tmp_trace_dir="$(mktemp -d)"
RESOURCE_GUARD_TRACE_LOG_PATH="$_tmp_trace_dir/custom/trace.log"
assert_eq "trace_log_path: override aponta pro caminho configurado" \
  "$_tmp_trace_dir/custom/trace.log" "$(trace_log_path)"
unset RESOURCE_GUARD_TRACE_LOG_PATH
rm -rf "$_tmp_trace_dir"

_trace_marker="teste-run-tests-$$"
trace_log "test-probe" "BLOCKED" "$_trace_marker"
assert_eq "trace_log: grava uma linha em data/trace.log" \
  "1" "$(grep -c "$_trace_marker" "$(trace_log_path)" 2>/dev/null || echo 0)"
sed -i "/$_trace_marker/d" "$(trace_log_path)" 2>/dev/null || true


# --- extração JSON: aspas escapadas -----------------------------------------

assert_eq "extract_json_string_field: não trunca em aspas escapadas" \
  'Agent "x"' \
  "$(extract_json_string_field '{"tool_name":"Agent \"x\""}' tool_name)"

assert_eq "json_unescape: \\\" \\\\ e \\/ numa passada só" \
  'a"b\c/d' "$(json_unescape 'a\"b\\c\/d')"

# --- _positive_int_or_default -----------------------------------------------
# Valor inválido no config.env viraria erro de aritmética em todo spawn.

assert_eq "max_subagents: valor não-numérico cai no default" \
  "5" "$(RESOURCE_GUARD_MAX_SUBAGENTS=abc resource_guard_max_subagents)"
assert_eq "max_subagents: zero cai no default (bloquearia tudo por engano)" \
  "5" "$(RESOURCE_GUARD_MAX_SUBAGENTS=0 resource_guard_max_subagents)"
assert_eq "ttl_seconds: valor inválido cai no default" \
  "1800" "$(RESOURCE_GUARD_TTL_SECONDS=-1 resource_guard_ttl_seconds)"

# --- acquire_lock / release_lock --------------------------------------------

_lock_dir="$(mktemp -d)/lock"
assert_eq "acquire_lock: pega o lock livre" "0" "$(acquire_lock "$_lock_dir" 1 60; echo $?)"
mkdir -p "$_lock_dir"
assert_eq "acquire_lock: desiste no timeout se o lock está tomado" \
  "1" "$(acquire_lock "$_lock_dir" 1 60; echo $?)"
assert_eq "acquire_lock: recupera lock abandonado (mais velho que stale)" \
  "0" "$(acquire_lock "$_lock_dir" 2 0; echo $?)"
release_lock "$_lock_dir"
assert_eq "release_lock: remove o diretório de lock" \
  "1" "$([ -d "$_lock_dir" ]; echo $?)"

# --- sanitize_trace_detail --------------------------------------------------

assert_eq "sanitize_trace_detail: achata quebra de linha (1 evento = 1 linha)" \
  "a b" "$(sanitize_trace_detail "a
b")"

# --- guard end-to-end: limite respeitado ------------------------------------

_guard="$SCRIPT_DIR/../guards/subagent-budget-guard.sh"
_tracker="$(mktemp -d)/active-agents"

_spawn() {
  echo '{"tool_name":"Agent"}' \
    | RESOURCE_GUARD_TRACKER_PATH="$_tracker" RESOURCE_GUARD_MAX_SUBAGENTS=2 "$_guard" >/dev/null 2>&1
  echo $?
}

assert_eq "guard: 1º spawn passa"  "0" "$(_spawn)"
assert_eq "guard: 2º spawn passa"  "0" "$(_spawn)"
assert_eq "guard: 3º spawn bloqueia (exit 2)" "2" "$(_spawn)"
assert_eq "guard: tracker tem exatamente 2 entradas" "2" "$(grep -c . "$_tracker")"

assert_eq "guard: ferramenta diferente de Agent é ignorada" \
  "0" "$(echo '{"tool_name":"Bash"}' | RESOURCE_GUARD_TRACKER_PATH="$_tracker" RESOURCE_GUARD_MAX_SUBAGENTS=2 "$_guard" >/dev/null 2>&1; echo $?)"
assert_eq "guard: tracker não cresceu com ferramenta ignorada" "2" "$(grep -c . "$_tracker")"
rm -rf "$(dirname "$_tracker")"
echo ""
echo "Resultado: $pass passaram, $fail falharam."
[ "$fail" -eq 0 ]
