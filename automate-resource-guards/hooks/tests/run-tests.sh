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

echo ""
echo "Resultado: $pass passaram, $fail falharam."
[ "$fail" -eq 0 ]
