#!/usr/bin/env bash
# Funções puras e testáveis dos hooks de CICLO DE VIDA DE SESSÃO — categoria
# distinta de automate-security/ e automate-resource-guards/: nenhum destes
# dois hooks BLOQUEIA nada (não são guards de PreToolUse), são notificações/
# ações de melhor esforço amarradas a eventos de ciclo de vida da sessão do
# agente (compactação de contexto, início de sessão). Por isso pasta e
# convenção própria — ver README.md > "Por que uma pasta própria".
#
# Vive em ~/development/tools/automate-session-lifecycle/hooks/, fora de
# qualquer repositório — cada repo que usa esta automação aponta seu hook
# para este local compartilhado.
#
# Origem: pre-compact-checkpoint.sh e mcp-warmup-wait.sh, portados de
# yurukusa/cc-safe-setup, com a lógica de formatação/decisão extraída em
# funções puras (I/O real — git, sleep, leitura de arquivo de config — fica
# só nos entrypoints em hooks/scripts/).

# --- compact-checkpoint (Claude Code: PreCompact / Devin CLI: PostCompaction) ---
# Ver README.md > "PreCompact (Claude Code) vs PostCompaction (Devin CLI)"
# para por que o MESMO script serve pros dois eventos apesar do nome
# diferente: a compactação não toca arquivos em disco, só o histórico de
# conversa — o snapshot git captura o mesmo estado antes ou depois dela.

# Conta quantas linhas não-vazias tem a saída de "git status --porcelain"
# (uma por arquivo alterado). Args: porcelain_output
count_changed_files() {
  local output="$1"
  [ -z "$output" ] && { echo 0; return; }
  printf '%s\n' "$output" | grep -c .
}

# Monta a mensagem do commit de checkpoint. Args: file_count timestamp_utc
format_checkpoint_commit_message() {
  local count="$1" timestamp="$2"
  printf 'checkpoint: pre-compact auto-save (%s files, %s)' "$count" "$timestamp"
}

# Monta o aviso impresso em stderr depois do checkpoint. Args: file_count branch
format_checkpoint_notice() {
  local count="$1" branch="$2"
  printf 'Checkpoint pré-compactação: %s arquivo(s) salvos em %s\n  Recupere com: git log --oneline -5' \
    "$count" "$branch"
}

# --- mcp-warmup-wait (SessionStart — mesmo nome de evento nas duas plataformas) ---

# Confere se o conteúdo de um arquivo de config declara "mcpServers" — pura,
# recebe o CONTEÚDO já lido, não o caminho (leitura de arquivo fica no
# entrypoint, que tenta uma lista de caminhos candidatos por plataforma).
# Args: config_file_content
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

  local vars=(SESSION_LIFECYCLE_CHECKPOINT_ENABLED SESSION_LIFECYCLE_WARMUP_ENABLED SESSION_LIFECYCLE_WARMUP_SECONDS)
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
