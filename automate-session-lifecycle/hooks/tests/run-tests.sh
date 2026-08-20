#!/usr/bin/env bash
# Testes das funções puras de ../lib.sh. Sem rede, sem framework novo.
# Uso: bash tests/run-tests.sh (a partir de ~/development/tools/automate-session-lifecycle/hooks/)
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

# --- count_changed_files -----------------------------------------------

assert_eq "count_changed_files: saída vazia -> 0" "0" "$(count_changed_files "")"
assert_eq "count_changed_files: 1 arquivo" "1" "$(count_changed_files " M foo.txt")"
assert_eq "count_changed_files: 3 arquivos" "3" "$(count_changed_files " M foo.txt
?? bar.txt
 D baz.txt")"

# --- format_checkpoint_commit_message ------------------------------------

assert_eq "format_checkpoint_commit_message: formata contagem + timestamp" \
  "checkpoint: pre-compact auto-save (3 files, 20260101-120000)" \
  "$(format_checkpoint_commit_message 3 20260101-120000)"

# --- format_checkpoint_notice --------------------------------------------

assert_eq "format_checkpoint_notice: formata contagem + branch" \
  "Checkpoint pré-compactação: 2 arquivo(s) salvos em feature/x
  Recupere com: git log --oneline -5" \
  "$(format_checkpoint_notice 2 feature/x)"

# --- config_declares_mcp_servers -----------------------------------------

assert_eq "config_declares_mcp_servers: presente -> match" \
  "0" "$(config_declares_mcp_servers '{"mcpServers":{"foo":{}}}'; echo $?)"
assert_eq "config_declares_mcp_servers: ausente -> sem match" \
  "1" "$(config_declares_mcp_servers '{"permissions":{}}'; echo $?)"
assert_eq "config_declares_mcp_servers: conteúdo vazio -> sem match" \
  "1" "$(config_declares_mcp_servers ''; echo $?)"

# --- format_warmup_notice -------------------------------------------------

assert_eq "format_warmup_notice: formata segundos" \
  "MCP warmup: aguardou 3s para inicialização do servidor" \
  "$(format_warmup_notice 3)"

# --- config / getters ------------------------------------------------------

unset SESSION_LIFECYCLE_CHECKPOINT_ENABLED SESSION_LIFECYCLE_WARMUP_ENABLED SESSION_LIFECYCLE_WARMUP_SECONDS
assert_eq "is_checkpoint_enabled: true por default" "0" "$(is_checkpoint_enabled; echo $?)"
assert_eq "is_warmup_enabled: true por default" "0" "$(is_warmup_enabled; echo $?)"
assert_eq "warmup_seconds: default 3" "3" "$(warmup_seconds)"

_tmp_config="$(mktemp)"
cat > "$_tmp_config" <<'EOF'
SESSION_LIFECYCLE_CHECKPOINT_ENABLED=false
SESSION_LIFECYCLE_WARMUP_SECONDS=7
EOF
unset SESSION_LIFECYCLE_CHECKPOINT_ENABLED SESSION_LIFECYCLE_WARMUP_SECONDS
load_config_env "$_tmp_config"
assert_eq "is_checkpoint_enabled: false via config.env" "1" "$(is_checkpoint_enabled; echo $?)"
assert_eq "warmup_seconds: lido do config.env" "7" "$(warmup_seconds)"
rm -f "$_tmp_config"
unset SESSION_LIFECYCLE_CHECKPOINT_ENABLED SESSION_LIFECYCLE_WARMUP_SECONDS

echo ""
echo "Resultado: $pass passaram, $fail falharam."
[ "$fail" -eq 0 ]
