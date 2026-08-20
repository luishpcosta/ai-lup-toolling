#!/usr/bin/env bash
# Funções puras e testáveis dos guards de segurança PreToolUse. Sem I/O de
# rede — cada função de detecção recebe o texto do comando como argumento e
# só devolve verdadeiro/falso via exit code, testável em isolamento em
# hooks/tests/run-tests.sh, sem precisar simular stdin/JSON.
#
# Vive em ~/development/tools/automate-security/hooks/, fora de qualquer
# repositório — cada repo que usa esta automação aponta seu hook para este
# local compartilhado (ver examples/claude-settings.json e
# examples/devin-hooks.json).
#
# Origem: guards portados e adaptados de yurukusa/cc-safe-setup
# (credential-exfil-guard.sh, db-connect-guard.sh) — mesma lógica de
# detecção, reescrita em funções puras + fallback sem jq (ver
# extract_json_string_field), seguindo o padrão já usado em
# automate-review/hooks/lib.sh deste mesmo repositório.

# --- Leitura do payload do hook (stdin JSON) ---------------------------

# Extrai o valor de um campo string de um JSON via regex — fallback usado só
# quando "jq" não está disponível (ex.: Git Bash puro do Windows). Não
# entende aninhamento de verdade, só procura a CHAVE em qualquer nível —
# suficiente pros payloads reais de hook (Claude Code/Devin CLI), que não
# repetem nomes de campo como "command"/"tool_name" em níveis diferentes.
# Idêntica à função de mesmo nome em automate-review/hooks/lib.sh (mantida
# duplicada de propósito — cada pasta de ferramenta é independente e
# instalável sozinha em qualquer repositório, ver tools/README.md).
# Args: json_text field_name
extract_json_string_field() {
  local json="$1" field="$2"
  printf '%s' "$json" \
    | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/"
}

# Extrai tool_input.command do payload do evento, com jq quando disponível e
# fallback bash/grep/sed puro quando não (jq não vem por padrão no Git for
# Windows/MSYS2). Args: payload_json
read_tool_command() {
  local payload="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null
  else
    extract_json_string_field "$payload" "command"
  fi
}

# --- Detecções puras (credential-exfil-guard) ---------------------------
# Portadas de cc-safe-setup/examples/credential-exfil-guard.sh — mesmos
# padrões, mesma ordem, mesmos comentários de contexto/issue preservados.

# env/printenv/set pipado pra grep por um termo claramente secreto.
is_secret_grep_env_dump() {
  echo "$1" | grep -qiE '(env|printenv|set)\s*\|.*grep.*\b(token|secret|key|password|credential|auth|oauth|cookie|session|api.key)\b'
}

# env/printenv/set pipado pra grep por QUALQUER termo (mesmo não-secreto) —
# ainda vaza os valores que baterem (#69053: "env | grep JIRA" dumpou
# JIRA_API_TOKEN). Não é bloqueio, é aviso — não usar como guard sozinho.
is_any_grep_env_dump() {
  echo "$1" | grep -qiE '(env|printenv|set)\s*\|.*grep'
}

# find procurando arquivo de credencial pelo nome.
is_credential_file_search() {
  echo "$1" | grep -qiE 'find\s.*-name\s.*\*?(token|secret|credential|password|\.key|\.pem|\.p12|\.pfx|\.keystore|\.jks|\.env)'
}

# Leitura direta de chave/config SSH.
is_ssh_credential_read() {
  echo "$1" | grep -qE 'cat\s+(~|/home|/root)/.ssh/(id_|authorized_keys|known_hosts|config)'
}

# Leitura de arquivo de credencial do sistema.
is_system_credential_read() {
  echo "$1" | grep -qE 'cat\s+(/etc/shadow|/etc/gshadow|/etc/passwd)'
}

# Leitura de credencial de provedor de nuvem (AWS/gcloud/Azure/kube).
is_cloud_credential_read() {
  echo "$1" | grep -qE 'cat\s+(~|/home|/root)/\.(aws|gcloud|azure|kube)/(credentials|config|token)'
}

# find em diretório de credencial de navegador.
is_browser_credential_hunt() {
  echo "$1" | grep -qiE 'find\s.*\.(chrome|firefox|mozilla|safari).*\b(login|password|cookie|token)\b'
}

# env/printenv/set sem filtro nenhum — dump completo.
is_bare_env_dump() {
  echo "$1" | grep -qE '^\s*(env|printenv|set)\s*$'
}

# curl/wget fazendo upload de arquivo de credencial (POST de arquivo).
is_credential_file_upload() {
  echo "$1" | grep -qiE 'curl[[:space:]].*-d[[:space:]]+@[^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)|wget[[:space:]].*--post-file[= ][^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)'
}

# cat de arquivo de credencial pipado direto pra curl/wget.
is_credential_file_piped_to_network() {
  echo "$1" | grep -qiE 'cat[[:space:]]+[^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)[^[:space:]]*[[:space:]]*\|.*curl|cat[[:space:]]+[^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)[^[:space:]]*[[:space:]]*\|.*wget'
}

# Extração de token de serviço conhecido do keychain do macOS
# (security find-generic/internet-password -w + nome de serviço secreto).
is_macos_keychain_secret_extraction() {
  echo "$1" | grep -qiE 'security\s+find-(generic|internet)-password' \
    && echo "$1" | grep -qE '(^|[[:space:]])-w([[:space:]]|$)' \
    && echo "$1" | grep -qiE 'ANTHROPIC|OPENAI|AUTH[_-]?TOKEN|API[_-]?KEY|ACCESS[_-]?TOKEN|[_-]SECRET|OAUTH|GITHUB[_-]?TOKEN|(^|[^a-z])secret([^a-z]|$)'
}

# Segredo do keychain pipado direto pra um cliente de rede.
is_keychain_piped_to_network() {
  echo "$1" | grep -qiE 'security\s+find-(generic|internet)-password' \
    && echo "$1" | grep -qiE '\|[[:space:]]*(curl|wget|nc|ncat|telnet)([[:space:]]|$)'
}

# Variável de ambiente com nome de segredo pipada direto pra um cliente de
# rede como dado (não como header — Authorization: Bearer $TOKEN não bate
# aqui porque não há pipe pro cliente de rede).
is_secret_env_piped_to_network() {
  echo "$1" | grep -qE '\$\{?[A-Za-z_]*(TOKEN|SECRET|API[_-]?KEY|PASSWORD|CREDENTIAL|AUTH)[A-Za-z_]*' \
    && echo "$1" | grep -qiE '\|[[:space:]]*(curl|wget|nc|ncat|telnet)([[:space:]]|$)'
}

# --- Detecções puras (db-connect-guard) ---------------------------------
# Portadas de cc-safe-setup/examples/db-connect-guard.sh.

# mysql/psql/mongo(sh) com -h/--host — conexão remota direta.
is_remote_sql_connect() {
  echo "$1" | grep -qE '\b(mysql|psql|mongo(sh)?)\s+.*(-h\s+|--host[= ])'
}

# redis-cli com -h/--host — conexão remota direta.
is_remote_redis_connect() {
  echo "$1" | grep -qE '\bredis-cli\s+.*(-h\s+|--host)'
}

# prisma db push / migrate deploy / migrate reset — modificação destrutiva.
is_prisma_destructive_command() {
  echo "$1" | grep -qE '\bprisma\s+(db\s+push|migrate\s+deploy|migrate\s+reset)'
}

# --- Config -------------------------------------------------------------

# Carrega KEY=value de um config.env, preservando qualquer variável já
# exportada no ambiente ANTES da chamada — env var explícita sempre vence
# sobre o arquivo. Mesma convenção de automate-review/hooks/lib.sh.
load_config_env() {
  local config_file="$1"
  [ -f "$config_file" ] || return 0

  local vars=(SECURITY_GUARD_ENABLED)
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

# Auto-carrega automate-security/config.env (um nível acima de hooks/)
# sempre que lib.sh é sourced.
load_config_env "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"

# true (exit 0) se os guards estão habilitados, false caso contrário.
is_security_guard_enabled() {
  [ "${SECURITY_GUARD_ENABLED:-true}" != "false" ]
}
