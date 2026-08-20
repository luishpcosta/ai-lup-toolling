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
assert_eq "config_declares_mcp_servers: objeto vazio -> sem match (não espera à toa)" \
  "1" "$(config_declares_mcp_servers '{"mcpServers":{}}'; echo $?)"
assert_eq "config_declares_mcp_servers: JSON indentado -> match" \
  "0" "$(config_declares_mcp_servers '{
  "mcpServers": {
    "foo": {}
  }
}'; echo $?)"
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

# --- format_trace_line / trace_log / trace_log_path ------------------------

assert_eq "format_trace_line: com detail" \
  "[2026-01-01T00:00:00-03:00] guard=compact-checkpoint decision=ACTION detail=commit criado" \
  "$(format_trace_line "2026-01-01T00:00:00-03:00" "compact-checkpoint" "ACTION" "commit criado")"

unset SESSION_LIFECYCLE_TRACE_LOG_PATH
assert_eq "trace_log_path: default é data/trace.log dentro da pasta" \
  "$(cd "$SCRIPT_DIR/../.." && pwd)/data/trace.log" "$(trace_log_path)"

_tmp_trace_dir="$(mktemp -d)"
SESSION_LIFECYCLE_TRACE_LOG_PATH="$_tmp_trace_dir/custom/trace.log"
assert_eq "trace_log_path: override aponta pro caminho configurado" \
  "$_tmp_trace_dir/custom/trace.log" "$(trace_log_path)"
unset SESSION_LIFECYCLE_TRACE_LOG_PATH
rm -rf "$_tmp_trace_dir"

_trace_marker="teste-run-tests-$$"
trace_log "test-probe" "ACTION" "$_trace_marker"
assert_eq "trace_log: grava uma linha em data/trace.log" \
  "1" "$(grep -c "$_trace_marker" "$(trace_log_path)" 2>/dev/null || echo 0)"
sed -i "/$_trace_marker/d" "$(trace_log_path)" 2>/dev/null || true

# --- warmup_seconds: valor inválido ------------------------------------------

assert_eq "warmup_seconds: valor não-numérico cai no default (sleep não quebra)" \
  "3" "$(SESSION_LIFECYCLE_WARMUP_SECONDS=abc warmup_seconds)"

# --- git_operation_in_progress ----------------------------------------------
# Commitar no meio de um merge/rebase conclui a operação errada.

_fake_git_dir="$(mktemp -d)"
assert_eq "git_operation_in_progress: repositório limpo -> vazio" \
  "" "$(git_operation_in_progress "$_fake_git_dir")"
touch "$_fake_git_dir/MERGE_HEAD"
assert_eq "git_operation_in_progress: MERGE_HEAD -> merge" \
  "merge" "$(git_operation_in_progress "$_fake_git_dir")"
rm -f "$_fake_git_dir/MERGE_HEAD"; mkdir -p "$_fake_git_dir/rebase-merge"
assert_eq "git_operation_in_progress: rebase-merge -> rebase" \
  "rebase" "$(git_operation_in_progress "$_fake_git_dir")"
rm -rf "$_fake_git_dir"

# --- compact-checkpoint end-to-end -------------------------------------------

_ck="$SCRIPT_DIR/../scripts/compact-checkpoint.sh"
_ck_trace="$(mktemp -d)/trace.log"

_repo="$(mktemp -d)"
(
  cd "$_repo" || exit 1
  git init -q -b feature/teste .
  echo conteudo > arquivo.txt
  SESSION_LIFECYCLE_TRACE_LOG_PATH="$_ck_trace" bash "$_ck" >/dev/null 2>&1
)
assert_eq "checkpoint: cria o commit quando há mudanças" \
  "1" "$(git -C "$_repo" rev-list --count HEAD 2>/dev/null || echo 0)"
assert_eq "checkpoint: loga ACTION com o nome real da branch (não 'HEAD')" \
  "1" "$(grep -c 'decision=ACTION.*feature/teste' "$_ck_trace")"
rm -rf "$_repo"

# Commit impossível (índice travado): não pode reportar sucesso.
_repo_travado="$(mktemp -d)"
(
  cd "$_repo_travado" || exit 1
  git init -q .
  echo conteudo > arquivo.txt
  touch .git/index.lock
  SESSION_LIFECYCLE_TRACE_LOG_PATH="$_ck_trace" bash "$_ck" >/dev/null 2>&1
)
assert_eq "checkpoint: commit que falha não vira commit" \
  "0" "$(git -C "$_repo_travado" rev-list --count HEAD 2>/dev/null || echo 0)"
assert_eq "checkpoint: commit que falha é logado como FAILED, não ACTION" \
  "1" "$(grep -c 'decision=FAILED' "$_ck_trace")"
rm -rf "$_repo_travado" "$(dirname "$_ck_trace")"

echo ""
echo "Resultado: $pass passaram, $fail falharam."
[ "$fail" -eq 0 ]
