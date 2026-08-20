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
    AGENT_PR_REVIEW_POLL_MAX_ATTEMPTS AGENT_PR_REVIEW_SKILL_PATH
    AGENT_PR_REVIEW_MAX_PER_BRANCH AGENT_PR_REVIEW_TRACE_LOG_PATH)
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
#     agêntica no estado SUCCESS. Cada elemento pode conter os placeholders
#     literais "{pr_url}" e "{repo}", substituídos em render_platform_cmd_line()
#     pela URL real da PR e por "owner/repo" — permite usar Claude Code, Devin
#     CLI ou qualquer outra ferramenta de linha de comando, desde que o
#     usuário configure o comando real dela.
#   - AGENT_PR_REVIEW_AUTOMERGE_REPOS: lista opt-in de "owner/repo" — ver
#     is_automerge_repo() abaixo. Vazia por padrão (nenhum merge automático
#     até ser configurado explicitamente).
AGENT_PR_REVIEW_TERMINAL_CMD=()
AGENT_PR_REVIEW_PLATFORM_CMD=()
AGENT_PR_REVIEW_AUTOMERGE_REPOS=()

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

# Desfaz os escapes JSON que importam para um comando/caminho (\" \\ \/),
# numa passada só — `\\"` vira `\"`, não `"` solto.
json_unescape() {
  printf '%s' "$1" | sed 's|\\\(["\\/]\)|\1|g'
}

# Extrai o valor de um campo string de um JSON via regex — última camada de
# fallback, usada só quando nem "jq" nem "python3" estão disponíveis. Não
# entende aninhamento de verdade, só procura a CHAVE em qualquer nível —
# suficiente pros payloads reais de hook (Claude Code/Devin CLI), que não
# repetem nomes de campo como "cwd"/"command" em níveis diferentes.
# Args: json_text field_name
extract_json_string_field() {
  local json="$1" field="$2" raw
  raw="$(printf '%s' "$json" \
    | grep -oE "\"$field\"[[:space:]]*:[[:space:]]*\"(\\\\.|[^\"\\\\])*\"" \
    | head -1)"
  [ -z "$raw" ] && return 0
  raw="${raw#*:}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw#\"}"
  raw="${raw%\"}"
  json_unescape "$raw"
}

# Lê um campo do payload do hook com o melhor parser disponível:
# jq -> python3 -> regex. jq não vem no Git for Windows/MSYS2 e python3 quase
# sempre vem, então a camada do meio evita cair na regex na prática.
# Args: payload jq_filter python_expression
_read_payload_field() {
  local payload="$1" jq_filter="$2" py_expr="$3"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r "$jq_filter" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c "
import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
value = $py_expr
if isinstance(value, str):
    sys.stdout.write(value)
" 2>/dev/null
  else
    return 1
  fi
}

# tool_input.command do payload do hook.
read_tool_command() {
  local payload="$1"
  _read_payload_field "$payload" '.tool_input.command // empty' \
    '(payload.get("tool_input") or {}).get("command")' \
    || extract_json_string_field "$payload" "command"
}

# cwd do payload do hook.
read_payload_cwd() {
  local payload="$1"
  _read_payload_field "$payload" '.cwd // empty' 'payload.get("cwd")' \
    || extract_json_string_field "$payload" "cwd"
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

# Confere se "$1" (owner/repo) está na lista opt-in AGENT_PR_REVIEW_AUTOMERGE_REPOS.
# Repos nessa lista pulam a revisão automatizada inteiramente e vão direto pro
# merge automático (ver poll-and-review.sh) — independentes do gate abaixo.
is_automerge_repo() {
  local repo="$1" candidate
  for candidate in "${AGENT_PR_REVIEW_AUTOMERGE_REPOS[@]}"; do
    [ "$candidate" = "$repo" ] && return 0
  done
  return 1
}

# Uma entrada do trace log é UMA linha: comando/erro multi-linha quebrava o
# formato pra quem lê com grep/tail.
sanitize_trace_detail() {
  local detail="$1"
  detail="$(printf '%s' "$detail" | tr '\n\r\t' '   ')"
  if [ "${#detail}" -gt 500 ]; then
    detail="${detail:0:500}…"
  fi
  printf '%s' "$detail"
}

# Emite uma linha do script final já escapada. Nome de branch e de
# repositório entram nesse script e o git ACEITA aspas simples no nome da
# branch (`feature/it's-broken`): interpolar direto dentro de '...' quebrava
# o script gerado e permitia injetar comando pelo nome da branch.
# Args: comando texto
emit_script_line() {
  printf '%s %q\n' "$1" "$2"
}

# Formata uma linha do trace log central — pura, testável sem tocar o
# filesystem (a escrita de fato é feita por trace_log() abaixo).
# Args: timestamp_iso repo branch event [detail]
format_trace_line() {
  local ts="$1" repo="$2" branch="$3" event="$4" detail="${5:-}"
  printf '[%s] repo=%s branch=%s event=%s%s\n' "$ts" "$repo" "$branch" "$event" "${detail:+ - $detail}"
}

# Monta a linha de comando final (já shell-quotada com segurança) que invoca
# a plataforma agêntica configurada em AGENT_PR_REVIEW_PLATFORM_CMD,
# substituindo os placeholders "{pr_url}" e "{repo}" pelos valores reais
# recebidos. Sempre prefixada com MSYS_NO_PATHCONV=1 — evita o bug de
# path-conversion do MSYS em argumentos que começam com "/" (ex.: "/review-pr").
render_platform_cmd_line() {
  local pr_url="$1" repo="${2:-}"
  local element line="MSYS_NO_PATHCONV=1"
  for element in "${AGENT_PR_REVIEW_PLATFORM_CMD[@]}"; do
    element="${element//\{pr_url\}/$pr_url}"
    element="${element//\{repo\}/$repo}"
    line+=" $(printf '%q' "$element")"
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

# Um getter por variável, em vez de uma linha só com tudo separado por
# espaço: com `read a b c d e <<< "$(resolve_config)"` um AGENT_PR_REVIEW_SKILL_PATH
# com espaço (ex.: "C:/Program Files/...") vazava para o campo seguinte e o
# limite do gate virava texto — o que fazia review-db.py rejeitar --max e a
# automação cair em fail-open sem gate nenhum.

# Valor inteiro positivo ou o default (config inválido não pode virar erro
# de aritmética/sleep no meio do polling). Args: value default
_positive_int_or_default() {
  case "${1:-}" in
    ''|*[!0-9]*) printf '%s' "$2" ;;
    0) printf '%s' "$2" ;;
    *) printf '%s' "$1" ;;
  esac
}

review_poll_interval_sec() {
  _positive_int_or_default "${AGENT_PR_REVIEW_POLL_INTERVAL_SEC:-}" 30
}

review_poll_max_attempts() {
  _positive_int_or_default "${AGENT_PR_REVIEW_POLL_MAX_ATTEMPTS:-}" 20
}

review_skill_path() {
  printf '%s' "${AGENT_PR_REVIEW_SKILL_PATH:-$HOME/development/tools/automate-review}"
}

review_max_per_branch() {
  _positive_int_or_default "${AGENT_PR_REVIEW_MAX_PER_BRANCH:-}" 3
}

# true (exit 0) se a automação está habilitada, false caso contrário.
is_automation_enabled() {
  [ "${AGENT_PR_REVIEW_ENABLED:-false}" = "true" ]
}

# Pasta de dados de runtime (SQLite do gate + trace log central), compartilhada
# por máquina — dentro de automate-review/, um nível acima de hooks/. Criada
# sob demanda, não versionada (ver .gitignore na raiz do repo).
_data_dir() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s' "$dir"
}

# Caminho do banco SQLite do gate de revisões (review-db.py).
review_db_path() {
  printf '%s/reviews.db' "$(_data_dir)"
}

# Caminho do trace log central (nível de máquina, todos os repos/branches).
# Default: data/trace.log dentro desta pasta. Override via
# AGENT_PR_REVIEW_TRACE_LOG_PATH (config.env ou env var) para gravar em
# outro lugar (ex.: um destino compartilhado entre máquinas).
trace_log_path() {
  if [ -n "${AGENT_PR_REVIEW_TRACE_LOG_PATH:-}" ]; then
    mkdir -p "$(dirname "$AGENT_PR_REVIEW_TRACE_LOG_PATH")" 2>/dev/null || true
    printf '%s' "$AGENT_PR_REVIEW_TRACE_LOG_PATH"
  else
    printf '%s/trace.log' "$(_data_dir)"
  fi
}

# Grava uma linha no trace log central. Args: repo branch event [detail]
# Melhor esforço — nunca falha o chamador (>/dev/null || true), o trace log é
# um extra, não algo que deva travar a automação se a escrita falhar.
trace_log() {
  format_trace_line "$(date -Iseconds)" "$1" "$2" "$3" "$(sanitize_trace_detail "${4:-}")" \
    >> "$(trace_log_path)" 2>/dev/null || true
}
