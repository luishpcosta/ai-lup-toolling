#!/usr/bin/env bash
# Funções puras e testáveis da automação de review de PR pós-push.
# Sem I/O de rede (exceto o load_config_env abaixo, que só lê um arquivo
# local) — pensadas para serem testadas isoladamente em tests/run-tests.sh.
# Vive em ~/development/tools/automate-review/hooks/, fora de qualquer
# repositório — cada repo que usa a automação aponta seu hook para este local
# compartilhado (ver .claude/settings.json do repo).

# Carrega KEY=value de um config.env, preservando qualquer variável já
# exportada no ambiente ANTES da chamada — env var explícita sempre vence
# sobre o arquivo (útil para overrides pontuais de teste). É a forma
# preferida de configurar a automação, no lugar de exportar manualmente.
load_config_env() {
  local config_file="$1"
  [ -f "$config_file" ] || return 0

  local vars=(AGENT_PR_REVIEW_ENABLED AGENT_PR_REVIEW_POLL_INTERVAL_SEC
    AGENT_PR_REVIEW_POLL_MAX_ATTEMPTS AGENT_PR_REVIEW_SKILL_PATH)
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

# Dois arrays (não strings) configuráveis via config.env — cada elemento vira
# um argv separado, então caminhos/prompts com espaço funcionam sem escaping
# manual. Vazios por padrão até o config.env (ou o fallback abaixo) definir:
#   - AGENT_PR_REVIEW_TERMINAL_CMD: programa+flags que roda o script final
#     na janela (o terminal/shell em si).
#   - AGENT_PR_REVIEW_PLATFORM_CMD: programa+prompt que invoca a plataforma
#     agêntica no estado SUCCESS. Cada elemento pode conter o placeholder
#     literal "{pr_url}", substituído em render_platform_cmd_line() pela URL
#     real da PR — permite usar Claude Code, Devin CLI ou qualquer outra
#     ferramenta de linha de comando, desde que o usuário configure o
#     comando real dela.
AGENT_PR_REVIEW_TERMINAL_CMD=()
AGENT_PR_REVIEW_PLATFORM_CMD=()

# Auto-carrega automate-review/config.env (um nível acima desta pasta) sempre
# que lib.sh é sourced, para qualquer script da automação receber a
# configuração sem precisar chamar nada explicitamente.
load_config_env "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"

# Defaults comprovados funcionando neste projeto, aplicados só se o
# config.env não tiver definido o array correspondente.
if [ "${#AGENT_PR_REVIEW_TERMINAL_CMD[@]}" -eq 0 ]; then
  AGENT_PR_REVIEW_TERMINAL_CMD=('C:\Program Files\Git\usr\bin\bash.exe' -i -l)
fi
if [ "${#AGENT_PR_REVIEW_PLATFORM_CMD[@]}" -eq 0 ]; then
  AGENT_PR_REVIEW_PLATFORM_CMD=(claude '/review-pr faça revisão da pr aberta em {pr_url} e submeta os comentarios e relatório da validação')
fi

# Classifica o ambiente a partir de entradas explícitas — pura, testável sem
# tocar o filesystem real. Args: proc_version_content msystem_value
classify_environment() {
  local proc_version_content="$1" msystem_value="$2"
  if printf '%s' "$proc_version_content" | grep -qi microsoft; then
    echo "wsl2"
  elif [ -n "$msystem_value" ]; then
    echo "gitbash"
  else
    echo "unknown"
  fi
}

# Detecta o ambiente de shell real: "wsl2", "gitbash" ou "unknown".
detect_environment() {
  local proc_version=""
  [ -r /proc/version ] && proc_version="$(cat /proc/version 2>/dev/null)"
  classify_environment "$proc_version" "${MSYSTEM:-}"
}

# Traduz um caminho do ambiente onde o poller roda para um caminho que o Git
# Bash NATIVO do Windows (bash.exe/MINGW64) consegue abrir de verdade — a
# automação sempre abre a janela final nesse Git Bash. Args: environment path
to_native_path() {
  local environment="$1" path="$2"
  case "$environment" in
    wsl2)
      local distro="${WSL_DISTRO_NAME:-}"
      [ -z "$distro" ] && return 1
      printf '//wsl.localhost/%s%s' "$distro" "$path"
      ;;
    gitbash)
      # Já nativo no Windows — nada a traduzir.
      printf '%s' "$path"
      ;;
    *)
      return 1
      ;;
  esac
}

# Extrai o valor de um campo string de um JSON via regex — fallback usado só
# quando "jq" não está disponível (ex.: Git Bash puro do Windows, que não
# bundla jq por padrão). Não entende aninhamento de verdade, só procura a
# CHAVE em qualquer nível — suficiente pros payloads reais de hook (Claude
# Code/Devin CLI), que não repetem nomes de campo como "cwd"/"command" em
# níveis diferentes. Não desescapa `\"`/`\\` — melhor esforço, não substitui
# um parser de JSON de verdade. Args: json_text field_name
extract_json_string_field() {
  local json="$1" field="$2"
  printf '%s' "$json" \
    | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/"
}

# Confere se o nome de branch recebido começa com "feature/".
is_feature_branch() {
  case "$1" in
    feature/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Confere se um texto de comando de shell contém "git push" — usado como
# defesa extra dentro do hook, já que nem toda plataforma agêntica filtra
# hooks pelo conteúdo do comando (só algumas, como o "if" do Claude Code).
is_git_push_command() {
  case "$1" in
    *"git push"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Monta a linha de comando final (já shell-quotada com segurança) que invoca
# a plataforma agêntica configurada em AGENT_PR_REVIEW_PLATFORM_CMD,
# substituindo o placeholder "{pr_url}" pela URL real recebida. Sempre
# prefixada com MSYS_NO_PATHCONV=1 — evita o bug de path-conversion do MSYS
# em argumentos que começam com "/" (ex.: "/review-pr").
render_platform_cmd_line() {
  local pr_url="$1"
  local element line="MSYS_NO_PATHCONV=1"
  for element in "${AGENT_PR_REVIEW_PLATFORM_CMD[@]}"; do
    line+=" $(printf '%q' "${element//\{pr_url\}/$pr_url}")"
  done
  printf '%s' "$line"
}

# Classifica o estado da verificação de CI a partir das contagens de check-runs
# e do progresso do polling. Retorna exatamente um entre: success, failure,
# timeout, pending.
#
# Args: success_count failure_count pending_count attempts_used max_attempts
classify_state() {
  local success_count="$1" failure_count="$2" pending_count="$3"
  local attempts_used="$4" max_attempts="$5"

  if [ "$failure_count" -gt 0 ]; then
    echo "failure"
    return
  fi

  if [ "$pending_count" -eq 0 ] && [ "$success_count" -gt 0 ]; then
    echo "success"
    return
  fi

  if [ "$attempts_used" -ge "$max_attempts" ]; then
    echo "timeout"
    return
  fi

  echo "pending"
}

# Lê a configuração de env vars (com defaults) e imprime, em ordem:
# enabled interval_sec max_attempts skill_path
resolve_config() {
  local enabled="${AGENT_PR_REVIEW_ENABLED:-false}"
  local interval="${AGENT_PR_REVIEW_POLL_INTERVAL_SEC:-30}"
  local max_attempts="${AGENT_PR_REVIEW_POLL_MAX_ATTEMPTS:-20}"
  local skill_path="${AGENT_PR_REVIEW_SKILL_PATH:-$HOME/development/tools/automate-review}"
  echo "$enabled" "$interval" "$max_attempts" "$skill_path"
}

# true (exit 0) se a automação está habilitada, false caso contrário.
is_automation_enabled() {
  [ "${AGENT_PR_REVIEW_ENABLED:-false}" = "true" ]
}
