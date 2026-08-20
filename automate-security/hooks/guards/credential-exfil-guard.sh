#!/usr/bin/env bash
# credential-exfil-guard.sh — bloqueia comandos que caçam/exfiltram
# credenciais. Portado de yurukusa/cc-safe-setup (examples/
# credential-exfil-guard.sh) para este pacote, com as detecções extraídas
# em funções puras testáveis (ver ../lib.sh) e leitura de stdin sem
# dependência obrigatória de jq (fallback bash/grep/sed, mesmo padrão de
# automate-review/hooks/lib.sh — jq não vem por padrão no Git for
# Windows/MSYS2).
#
# TRIGGER: PreToolUse
# MATCHER: "Bash" no Claude Code, "exec" no Devin CLI (ver
#   ../../examples/{claude-settings,devin-hooks}.json)
#
# Compatível com Claude Code e Devin CLI: os dois bloqueiam a ferramenta
# com exit code 2 num hook PreToolUse (confirmado em
# docs.devin.ai/cli/extensibility/hooks/{overview,lifecycle-hooks}) e os
# dois entregam o payload do evento via stdin JSON com o mesmo campo
# tool_input.command.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

is_security_guard_enabled || exit 0

INPUT="$(cat)"
COMMAND="$(read_tool_command "$INPUT")"
[ -z "$COMMAND" ] && exit 0

if is_secret_grep_env_dump "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: caça de credencial via variáveis de ambiente" >&2
  exit 2
fi

# Não é bloqueio — mesmo um termo não-secreto pipado de env/printenv/set pra
# grep imprime o VALOR que bater (#69053: "env | grep JIRA" vazou
# JIRA_API_TOKEN). Aviso, não bloqueio, pra não travar "env | grep PATH".
if is_any_grep_env_dump "$COMMAND"; then
  echo "WARNING [credential-exfil-guard]: despejar o ambiente pra dentro de um grep imprime os valores que baterem no transcript/API; se a variável casada guardar um token, ele fica exposto. Pra achar ONDE uma credencial está configurada, faça grep no NOME da variável em arquivos de config, não no dump do ambiente." >&2
  exit 0
fi

if is_credential_file_search "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: caça de credencial via busca no sistema de arquivos" >&2
  exit 2
fi

if is_ssh_credential_read "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: acesso direto a credencial SSH" >&2
  exit 2
fi

if is_system_credential_read "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: acesso a arquivo de credencial do sistema" >&2
  exit 2
fi

if is_cloud_credential_read "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: acesso a credencial de provedor de nuvem" >&2
  exit 2
fi

if is_browser_credential_hunt "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: caça de credencial de navegador" >&2
  exit 2
fi

if is_bare_env_dump "$COMMAND"; then
  echo "WARNING [credential-exfil-guard]: despejar todas as variáveis de ambiente pode expor segredos" >&2
  exit 0
fi

if is_credential_file_upload "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: exfiltração de arquivo de credencial via upload HTTP" >&2
  exit 2
fi

if is_credential_file_piped_to_network "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: arquivo de credencial pipado pra cliente HTTP" >&2
  exit 2
fi

if is_macos_keychain_secret_extraction "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: extração de token secreto do keychain do macOS" >&2
  exit 2
fi

if is_keychain_piped_to_network "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: segredo do keychain pipado pra cliente de rede (possível exfiltração)" >&2
  exit 2
fi

if is_secret_env_piped_to_network "$COMMAND"; then
  echo "BLOCKED [credential-exfil-guard]: variável de ambiente secreta pipada pra cliente de rede (possível exfiltração)" >&2
  exit 2
fi

exit 0
