#!/usr/bin/env bash
# Testes das funções puras de ../lib.sh. Sem rede, sem framework novo.
# Uso: bash tests/run-tests.sh (a partir de ~/development/tools/automate-review/hooks/)
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

# --- classify_environment (lógica pura de detect_environment) ---

assert_eq "classify_environment: /proc/version com 'microsoft' -> wsl2" \
  "wsl2" "$(classify_environment "Linux version 5.15.0-microsoft-standard-WSL2" "")"

assert_eq "classify_environment: sem microsoft, MSYSTEM setado -> gitbash" \
  "gitbash" "$(classify_environment "Linux version 5.15.0-generic" "MINGW64")"

assert_eq "classify_environment: nenhum indicador -> unknown" \
  "unknown" "$(classify_environment "Linux version 5.15.0-generic" "")"

assert_eq "classify_environment: microsoft tem prioridade mesmo com MSYSTEM setado" \
  "wsl2" "$(classify_environment "Linux version 5.15.0-microsoft-standard-WSL2" "MINGW64")"

# --- detect_environment (integração com o host real de teste) ---

assert_eq "detect_environment reflete o host real (aqui: WSL2)" \
  "wsl2" "$(detect_environment)"

# --- to_native_path ---

assert_eq "to_native_path: wsl2 traduz para UNC \\\\wsl.localhost\\<distro>\\..." \
  "//wsl.localhost/Ubuntu/root/development/tools/automate-review" \
  "$(WSL_DISTRO_NAME=Ubuntu to_native_path wsl2 /root/development/tools/automate-review)"

assert_eq "to_native_path: gitbash não traduz (já é nativo)" \
  "/c/Users/x/repo" "$(to_native_path gitbash /c/Users/x/repo)"

assert_eq "to_native_path: wsl2 sem \$WSL_DISTRO_NAME falha (exit != 0)" \
  "1" "$(WSL_DISTRO_NAME= to_native_path wsl2 /root/foo >/dev/null 2>&1; echo $?)"

assert_eq "to_native_path: ambiente desconhecido falha" \
  "1" "$(to_native_path unknown /root/foo >/dev/null 2>&1; echo $?)"

# --- extract_json_string_field (fallback sem jq) ---

assert_eq "extract_json_string_field: campo top-level simples" \
  "/root/meu-repo" "$(extract_json_string_field '{"cwd":"/root/meu-repo","x":1}' cwd)"

assert_eq "extract_json_string_field: campo aninhado (tool_input.command)" \
  "git push -u origin HEAD" \
  "$(extract_json_string_field '{"tool_input":{"command":"git push -u origin HEAD"},"cwd":"/x"}' command)"

assert_eq "extract_json_string_field: campo ausente retorna vazio" \
  "" "$(extract_json_string_field '{"cwd":"/x"}' command)"

assert_eq "extract_json_string_field: espaços em volta dos dois-pontos" \
  "valor" "$(extract_json_string_field '{"campo"  :   "valor"}' campo)"

# --- is_feature_branch ---

if is_feature_branch "feature/minha-coisa"; then r=0; else r=1; fi
assert_eq "is_feature_branch aceita feature/minha-coisa" "0" "$r"

if is_feature_branch "main"; then r=0; else r=1; fi
assert_eq "is_feature_branch rejeita main" "1" "$r"

if is_feature_branch "featurex/nope"; then r=0; else r=1; fi
assert_eq "is_feature_branch rejeita prefixo parecido sem barra" "1" "$r"

# --- is_git_push_command ---

if is_git_push_command "git push"; then r=0; else r=1; fi
assert_eq "is_git_push_command aceita 'git push' puro" "0" "$r"

if is_git_push_command "git push -u origin HEAD"; then r=0; else r=1; fi
assert_eq "is_git_push_command aceita com flags/args" "0" "$r"

if is_git_push_command "cd repo && git push"; then r=0; else r=1; fi
assert_eq "is_git_push_command aceita mesmo não sendo o comando inteiro" "0" "$r"

if is_git_push_command "git status"; then r=0; else r=1; fi
assert_eq "is_git_push_command rejeita outros comandos git" "1" "$r"

if is_git_push_command "npm run build"; then r=0; else r=1; fi
assert_eq "is_git_push_command rejeita comando não relacionado" "1" "$r"

# --- render_platform_cmd_line ---

AGENT_PR_REVIEW_PLATFORM_CMD=(claude '/review-pr revisa {pr_url} por favor')
assert_eq "render_platform_cmd_line: substitui {pr_url} e prefixa MSYS_NO_PATHCONV=1" \
  "MSYS_NO_PATHCONV=1 claude /review-pr\\ revisa\\ https://github.com/x/y/pull/1\\ por\\ favor" \
  "$(render_platform_cmd_line 'https://github.com/x/y/pull/1')"

AGENT_PR_REVIEW_PLATFORM_CMD=(devin run "revisa a PR {pr_url}")
assert_eq "render_platform_cmd_line: funciona com outro comando configurado (ex.: devin)" \
  "MSYS_NO_PATHCONV=1 devin run revisa\\ a\\ PR\\ https://x/pull/2" \
  "$(render_platform_cmd_line 'https://x/pull/2')"

AGENT_PR_REVIEW_PLATFORM_CMD=(claude '/review-pr revisa {pr_url} do repo {repo} por favor')
assert_eq "render_platform_cmd_line: substitui {repo} além de {pr_url}" \
  "MSYS_NO_PATHCONV=1 claude /review-pr\\ revisa\\ https://github.com/x/y/pull/1\\ do\\ repo\\ x/y\\ por\\ favor" \
  "$(render_platform_cmd_line 'https://github.com/x/y/pull/1' 'x/y')"

AGENT_PR_REVIEW_PLATFORM_CMD=(claude '/review-pr revisa {pr_url} por favor')
assert_eq "render_platform_cmd_line: {repo} ausente (2º arg omitido) vira string vazia, sem quebrar {pr_url}" \
  "MSYS_NO_PATHCONV=1 claude /review-pr\\ revisa\\ https://github.com/x/y/pull/1\\ por\\ favor" \
  "$(render_platform_cmd_line 'https://github.com/x/y/pull/1')"

AGENT_PR_REVIEW_PLATFORM_CMD=()

# --- classify_state ---

assert_eq "classify_state: qualquer falha vence, mesmo com sucessos" \
  "failure" "$(classify_state 2 1 0 5 20)"

assert_eq "classify_state: tudo concluído com sucesso" \
  "success" "$(classify_state 3 0 0 4 20)"

assert_eq "classify_state: ainda há pendentes, dentro do limite" \
  "pending" "$(classify_state 1 0 1 4 20)"

assert_eq "classify_state: limite atingido sem sucesso nem falha (timeout)" \
  "timeout" "$(classify_state 0 0 1 20 20)"

assert_eq "classify_state: nenhum check-run encontrado até o limite (timeout, não erro)" \
  "timeout" "$(classify_state 0 0 0 20 20)"

assert_eq "classify_state: nenhum check-run ainda, mas dentro do limite (segue pollando)" \
  "pending" "$(classify_state 0 0 0 3 20)"

# --- load_config_env ---

_tmp_config="$(mktemp)"
cat > "$_tmp_config" <<'EOF'
AGENT_PR_REVIEW_ENABLED=true
AGENT_PR_REVIEW_POLL_INTERVAL_SEC=15
EOF

unset AGENT_PR_REVIEW_ENABLED AGENT_PR_REVIEW_POLL_INTERVAL_SEC AGENT_PR_REVIEW_POLL_MAX_ATTEMPTS
load_config_env "$_tmp_config"
assert_eq "load_config_env: preenche variável ausente a partir do arquivo" \
  "true" "$AGENT_PR_REVIEW_ENABLED"
assert_eq "load_config_env: variável não mencionada no arquivo continua ausente" \
  "" "${AGENT_PR_REVIEW_POLL_MAX_ATTEMPTS:-}"

unset AGENT_PR_REVIEW_ENABLED AGENT_PR_REVIEW_POLL_INTERVAL_SEC
AGENT_PR_REVIEW_ENABLED=false
load_config_env "$_tmp_config"
assert_eq "load_config_env: variável de ambiente já definida vence sobre o arquivo" \
  "false" "$AGENT_PR_REVIEW_ENABLED"

rm -f "$_tmp_config"
unset AGENT_PR_REVIEW_ENABLED AGENT_PR_REVIEW_POLL_INTERVAL_SEC

assert_eq "load_config_env: arquivo inexistente não quebra (retorna sucesso)" \
  "0" "$(load_config_env /tmp/nao-existe-$$-config.env; echo $?)"

# --- AGENT_PR_REVIEW_TERMINAL_CMD (array configurável) ---

assert_eq "TERMINAL_CMD: default é o Git Bash nativo (3 elementos: exe, -i, -l)" \
  "3" "${#AGENT_PR_REVIEW_TERMINAL_CMD[@]}"
assert_eq "TERMINAL_CMD: primeiro elemento do default é o bash.exe do MSYS" \
  'C:\Program Files\Git\usr\bin\bash.exe' "${AGENT_PR_REVIEW_TERMINAL_CMD[0]}"

_tmp_config2="$(mktemp)"
cat > "$_tmp_config2" <<'EOF'
AGENT_PR_REVIEW_TERMINAL_CMD=(wsl.exe bash)
EOF
AGENT_PR_REVIEW_TERMINAL_CMD=()
load_config_env "$_tmp_config2"
assert_eq "TERMINAL_CMD: config.env consegue sobrescrever com outro terminal" \
  "2 wsl.exe bash" "${#AGENT_PR_REVIEW_TERMINAL_CMD[@]} ${AGENT_PR_REVIEW_TERMINAL_CMD[*]}"
rm -f "$_tmp_config2"
AGENT_PR_REVIEW_TERMINAL_CMD=()

# --- resolve_config (defaults) ---

unset AGENT_PR_REVIEW_ENABLED AGENT_PR_REVIEW_POLL_INTERVAL_SEC AGENT_PR_REVIEW_POLL_MAX_ATTEMPTS AGENT_PR_REVIEW_SKILL_PATH AGENT_PR_REVIEW_MAX_PER_BRANCH
assert_eq "resolve_config: default desligado" \
  "false 30 20 $HOME/development/tools/automate-review 3" "$(resolve_config)"

AGENT_PR_REVIEW_ENABLED=true
assert_eq "is_automation_enabled: true quando env var é 'true'" "0" "$(is_automation_enabled; echo $?)"
unset AGENT_PR_REVIEW_ENABLED
assert_eq "is_automation_enabled: false por default" "1" "$(is_automation_enabled; echo $?)"

# --- is_automerge_repo ---

AGENT_PR_REVIEW_AUTOMERGE_REPOS=(org/repo-a org/repo-b)
if is_automerge_repo "org/repo-a"; then r=0; else r=1; fi
assert_eq "is_automerge_repo aceita repo presente na lista" "0" "$r"

if is_automerge_repo "org/repo-c"; then r=0; else r=1; fi
assert_eq "is_automerge_repo rejeita repo ausente da lista" "1" "$r"

AGENT_PR_REVIEW_AUTOMERGE_REPOS=()
if is_automerge_repo "org/repo-a"; then r=0; else r=1; fi
assert_eq "is_automerge_repo rejeita tudo com lista vazia (default)" "1" "$r"

# --- format_trace_line ---

assert_eq "format_trace_line: com detail" \
  "[2026-01-01T00:00:00-03:00] repo=org/repo branch=feature/x event=review_invoked - count=1 max=3" \
  "$(format_trace_line "2026-01-01T00:00:00-03:00" "org/repo" "feature/x" "review_invoked" "count=1 max=3")"

assert_eq "format_trace_line: sem detail (sem ' - ' sobrando)" \
  "[2026-01-01T00:00:00-03:00] repo= branch=feature/x event=push_detected" \
  "$(format_trace_line "2026-01-01T00:00:00-03:00" "" "feature/x" "push_detected")"

# --- AGENT_PR_REVIEW_MAX_PER_BRANCH (precedência via load_config_env) ---

_tmp_config3="$(mktemp)"
cat > "$_tmp_config3" <<'EOF'
AGENT_PR_REVIEW_MAX_PER_BRANCH=7
EOF
unset AGENT_PR_REVIEW_MAX_PER_BRANCH
load_config_env "$_tmp_config3"
assert_eq "MAX_PER_BRANCH: preenchido a partir do config.env quando ausente no ambiente" \
  "7" "$AGENT_PR_REVIEW_MAX_PER_BRANCH"

unset AGENT_PR_REVIEW_MAX_PER_BRANCH
AGENT_PR_REVIEW_MAX_PER_BRANCH=1
load_config_env "$_tmp_config3"
assert_eq "MAX_PER_BRANCH: variável de ambiente já definida vence sobre o arquivo" \
  "1" "$AGENT_PR_REVIEW_MAX_PER_BRANCH"
rm -f "$_tmp_config3"
unset AGENT_PR_REVIEW_MAX_PER_BRANCH

# --- AGENT_PR_REVIEW_AUTOMERGE_REPOS (override via config.env) ---

assert_eq "AUTOMERGE_REPOS: default vazio" "0" "${#AGENT_PR_REVIEW_AUTOMERGE_REPOS[@]}"

_tmp_config4="$(mktemp)"
cat > "$_tmp_config4" <<'EOF'
AGENT_PR_REVIEW_AUTOMERGE_REPOS=(org/repo-a org/repo-b)
EOF
AGENT_PR_REVIEW_AUTOMERGE_REPOS=()
load_config_env "$_tmp_config4"
assert_eq "AUTOMERGE_REPOS: config.env consegue definir a lista" \
  "2 org/repo-a org/repo-b" "${#AGENT_PR_REVIEW_AUTOMERGE_REPOS[@]} ${AGENT_PR_REVIEW_AUTOMERGE_REPOS[*]}"
rm -f "$_tmp_config4"
AGENT_PR_REVIEW_AUTOMERGE_REPOS=()

echo ""
echo "Resultado: $pass passaram, $fail falharam."
[ "$fail" -eq 0 ]
