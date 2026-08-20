#!/usr/bin/env bash
# Funções puras + leitura de stdin + log de auditoria dos guards de
# segurança PreToolUse. Testes: hooks/tests/run-tests.sh.

# --- stdin JSON -----------------------------------------------------------

# Extrai um campo string de JSON via regex (fallback sem jq).
# Args: json_text field_name
extract_json_string_field() {
  local json="$1" field="$2"
  printf '%s' "$json" \
    | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/"
}

# tool_input.command do payload. jq quando disponível, fallback quando não.
read_tool_command() {
  local payload="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null
  else
    extract_json_string_field "$payload" "command"
  fi
}

# --- Detecções: credential-exfil-guard -------------------------------------

is_secret_grep_env_dump() {
  echo "$1" | grep -qiE '(env|printenv|set)\s*\|.*grep.*\b(token|secret|key|password|credential|auth|oauth|cookie|session|api.key)\b'
}

# grep sobre dump de ambiente por QUALQUER termo — vaza valor mesmo se o
# termo não for óbvio (#69053: "env | grep JIRA" vazou JIRA_API_TOKEN).
is_any_grep_env_dump() {
  echo "$1" | grep -qiE '(env|printenv|set)\s*\|.*grep'
}

is_credential_file_search() {
  echo "$1" | grep -qiE 'find\s.*-name\s.*\*?(token|secret|credential|password|\.key|\.pem|\.p12|\.pfx|\.keystore|\.jks|\.env)'
}

is_ssh_credential_read() {
  echo "$1" | grep -qE 'cat\s+(~|/home|/root)/.ssh/(id_|authorized_keys|known_hosts|config)'
}

is_system_credential_read() {
  echo "$1" | grep -qE 'cat\s+(/etc/shadow|/etc/gshadow|/etc/passwd)'
}

is_cloud_credential_read() {
  echo "$1" | grep -qE 'cat\s+(~|/home|/root)/\.(aws|gcloud|azure|kube)/(credentials|config|token)'
}

is_browser_credential_hunt() {
  echo "$1" | grep -qiE 'find\s.*\.(chrome|firefox|mozilla|safari).*\b(login|password|cookie|token)\b'
}

is_bare_env_dump() {
  echo "$1" | grep -qE '^\s*(env|printenv|set)\s*$'
}

is_credential_file_upload() {
  echo "$1" | grep -qiE 'curl[[:space:]].*-d[[:space:]]+@[^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)|wget[[:space:]].*--post-file[= ][^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)'
}

is_credential_file_piped_to_network() {
  echo "$1" | grep -qiE 'cat[[:space:]]+[^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)[^[:space:]]*[[:space:]]*\|.*curl|cat[[:space:]]+[^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)[^[:space:]]*[[:space:]]*\|.*wget'
}

# security find-generic/internet-password -w de um serviço com nome de segredo.
is_macos_keychain_secret_extraction() {
  echo "$1" | grep -qiE 'security\s+find-(generic|internet)-password' \
    && echo "$1" | grep -qE '(^|[[:space:]])-w([[:space:]]|$)' \
    && echo "$1" | grep -qiE 'ANTHROPIC|OPENAI|AUTH[_-]?TOKEN|API[_-]?KEY|ACCESS[_-]?TOKEN|[_-]SECRET|OAUTH|GITHUB[_-]?TOKEN|(^|[^a-z])secret([^a-z]|$)'
}

is_keychain_piped_to_network() {
  echo "$1" | grep -qiE 'security\s+find-(generic|internet)-password' \
    && echo "$1" | grep -qiE '\|[[:space:]]*(curl|wget|nc|ncat|telnet)([[:space:]]|$)'
}

# $TOKEN/$SECRET/etc pipado direto pra um cliente de rede (não header).
is_secret_env_piped_to_network() {
  echo "$1" | grep -qE '\$\{?[A-Za-z_]*(TOKEN|SECRET|API[_-]?KEY|PASSWORD|CREDENTIAL|AUTH)[A-Za-z_]*' \
    && echo "$1" | grep -qiE '\|[[:space:]]*(curl|wget|nc|ncat|telnet)([[:space:]]|$)'
}

# --- Detecções: db-connect-guard -------------------------------------------

is_remote_sql_connect() {
  echo "$1" | grep -qE '\b(mysql|psql|mongo(sh)?)\s+.*(-h\s+|--host[= ])'
}

is_remote_redis_connect() {
  echo "$1" | grep -qE '\bredis-cli\s+.*(-h\s+|--host)'
}

is_prisma_destructive_command() {
  echo "$1" | grep -qE '\bprisma\s+(db\s+push|migrate\s+deploy|migrate\s+reset)'
}

# --- Config -----------------------------------------------------------------

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

load_config_env "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"

is_security_guard_enabled() {
  [ "${SECURITY_GUARD_ENABLED:-true}" != "false" ]
}

# --- Log de auditoria -------------------------------------------------------
# data/audit.log — 1 arquivo por pasta de ferramenta, git-ignored (runtime,
# não código). Registra todo BLOCKED/WARNING, nunca os "passou sem bater
# em nada" (senão vira ruído). Best-effort: nunca derruba o guard chamador.

_data_dir() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s' "$dir"
}

audit_log_path() {
  printf '%s/audit.log' "$(_data_dir)"
}

# Args: timestamp_iso guard decision detail
format_audit_line() {
  local ts="$1" guard="$2" decision="$3" detail="${4:-}"
  printf '[%s] guard=%s decision=%s%s\n' "$ts" "$guard" "$decision" "${detail:+ detail=$detail}"
}

# Args: guard decision [detail]
audit_log() {
  format_audit_line "$(date -Iseconds)" "$1" "$2" "${3:-}" >> "$(audit_log_path)" 2>/dev/null || true
}
