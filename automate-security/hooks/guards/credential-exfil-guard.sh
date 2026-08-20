#!/usr/bin/env bash
# Bloqueia comandos que caçam/exfiltram credenciais.
#
# TRIGGER: PreToolUse | MATCHER: "Bash" (Claude Code), "exec" (Devin CLI)
# Bloqueia via exit 2, igual nas duas plataformas.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

is_security_guard_enabled || exit 0

INPUT="$(cat)"
COMMAND="$(read_tool_command "$INPUT")"
[ -z "$COMMAND" ] && exit 0

GUARD="credential-exfil-guard"

# Bate no padrão de $1 -> imprime BLOCKED, loga e sai com exit 2.
block_if() {
  "$1" "$COMMAND" || return 0
  echo "BLOCKED [$GUARD]: $2" >&2
  audit_log "$GUARD" BLOCKED "$2 | cmd=$COMMAND"
  exit 2
}

# Bate no padrão de $1 -> imprime WARNING, loga e sai com exit 0 (não bloqueia).
warn_if() {
  "$1" "$COMMAND" || return 0
  echo "WARNING [$GUARD]: $2" >&2
  audit_log "$GUARD" WARNING "$2 | cmd=$COMMAND"
  exit 0
}

block_if is_secret_grep_env_dump  "caça de credencial via variável de ambiente"
warn_if  is_any_grep_env_dump     "grep sobre dump de ambiente vaza valor mesmo sem termo óbvio (#69053)"
block_if is_credential_file_search             "caça de credencial via busca de arquivo"
block_if is_ssh_credential_read                "acesso direto a credencial SSH"
block_if is_system_credential_read             "acesso a credencial do sistema (/etc/shadow etc.)"
block_if is_cloud_credential_read              "acesso a credencial de nuvem (aws/gcloud/kube)"
block_if is_browser_credential_hunt            "caça de credencial de navegador"
warn_if  is_bare_env_dump                      "dump completo do ambiente pode expor segredos"
block_if is_credential_file_upload             "upload de arquivo de credencial via HTTP"
block_if is_credential_file_piped_to_network   "arquivo de credencial pipado pra cliente de rede"
block_if is_macos_keychain_secret_extraction   "extração de segredo do keychain macOS"
block_if is_keychain_piped_to_network          "segredo do keychain pipado pra cliente de rede"
block_if is_secret_env_piped_to_network        "variável de ambiente secreta pipada pra cliente de rede"

exit 0
