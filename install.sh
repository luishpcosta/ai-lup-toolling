#!/usr/bin/env bash
# CLI de instalação dos hooks deste repositório (automate-review,
# automate-security, automate-resource-guards, automate-session-lifecycle).
# Escolhe ferramenta(s), plataforma(s) (Claude Code e/ou Devin CLI) e
# escopo (global ou por repositório) — instala uma ou várias de uma vez,
# mesclando no config existente sem apagar nada (backup automático).
#
# Uso interativo: ./install.sh
# Uso por flags:   ./install.sh --tools=security,resource-guards --platform=both --scope=repo --repo=/caminho
# Ajuda:            ./install.sh --help
set -uo pipefail

TOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- registro de ferramentas ------------------------------------------------

TOOL_KEYS=(review security resource-guards session-lifecycle)
declare -A TOOL_DIR=(
  [review]="automate-review"
  [security]="automate-security"
  [resource-guards]="automate-resource-guards"
  [session-lifecycle]="automate-session-lifecycle"
)
declare -A TOOL_DESC=(
  [review]="Review de PR pós-push (CI + skill review-pr)"
  [security]="Guards de segurança (credencial, DB de produção)"
  [resource-guards]="Guard de orçamento (limite de subagentes)"
  [session-lifecycle]="Checkpoint de compactação + warmup de MCP"
)
# Aviso extra impresso depois de instalar essa combinação (tool:platform).
declare -A TOOL_CAVEAT=(
  [resource-guards:devin]='matcher "Agent" não confirmado no Devin CLI — ver automate-resource-guards/README.md'
  [review:claude]='automação vem DESLIGADA por padrão — edite automate-review/config.env (AGENT_PR_REVIEW_ENABLED=true) pra ligar'
  [review:devin]='automação vem DESLIGADA por padrão — edite automate-review/config.env (AGENT_PR_REVIEW_ENABLED=true) pra ligar'
)

DRY_RUN=false
ASSUME_YES=false

# --- utilitários --------------------------------------------------------

die() { echo "ERRO: $*" >&2; exit 1; }

# Mesclar JSON com segurança (sem apagar nada, sem corromper) exige um
# parser de verdade — não dá pra fazer com grep/sed como os guards fazem na
# LEITURA de um campo. jq é a 1ª escolha; python3 é o fallback (mesma
# lógica, ver install_merge.py). Sem os dois, erro claro em vez de arriscar
# escrever um JSON quebrado.
MERGE_ENGINE=""
detect_merge_engine() {
  if command -v jq >/dev/null 2>&1; then
    MERGE_ENGINE="jq"
  elif command -v python3 >/dev/null 2>&1; then
    MERGE_ENGINE="python3"
  else
    die "precisa de 'jq' OU 'python3' pra mesclar o config JSON existente sem apagar nada. Instale um dos dois e rode de novo."
  fi
}

# Args: file
is_valid_json() {
  local f="$1"
  if [ "$MERGE_ENGINE" = "jq" ]; then
    jq -e . "$f" >/dev/null 2>&1
  else
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" >/dev/null 2>&1
  fi
}

usage() {
  cat <<'EOF'
install.sh — instala os hooks das automações deste repositório.

Uso:
  ./install.sh                          modo interativo (recomendado)
  ./install.sh [flags]                  modo direto, sem prompts

Flags:
  --tools=LISTA        review,security,resource-guards,session-lifecycle ou "all"
  --platform=claude|devin|both
  --scope=global|repo
  --repo=CAMINHO        obrigatório se --scope=repo (default: diretório atual)
  --dry-run             mostra o que mudaria, não escreve nada
  --yes                 pula a confirmação
  --list                lista as ferramentas disponíveis e sai
  --help                esta ajuda

Exemplos:
  ./install.sh --tools=all --platform=claude --scope=global
  ./install.sh --tools=security,resource-guards --platform=both --scope=repo --repo=. --yes
  ./install.sh --tools=review --platform=devin --scope=repo --dry-run
EOF
}

list_tools() {
  echo "Ferramentas disponíveis:"
  for key in "${TOOL_KEYS[@]}"; do
    printf '  %-18s %s\n' "$key" "${TOOL_DESC[$key]}"
  done
}

# Versão numerada, usada no modo interativo — o prompt pede número, então a
# lista precisa mostrar número.
list_tools_numbered() {
  local idx=1 key
  echo "Ferramentas disponíveis:"
  for key in "${TOOL_KEYS[@]}"; do
    printf '  %d) %-18s %s\n' "$idx" "$key" "${TOOL_DESC[$key]}"
    idx=$((idx + 1))
  done
}

# Os examples/*.json trazem o caminho padrão ($HOME/development/tools/...).
# Se este checkout está em outro lugar, o hook instalado apontaria pra uma
# pasta inexistente e nunca rodaria — sem nenhum erro visível.
# Copia o example trocando esse caminho pelo caminho real deste checkout.
# Args: source_file out_file
render_source_file() {
  local src="$1" out="$2" escaped
  if [ "$TOOLS_ROOT" = "$HOME/development/tools" ]; then
    cp "$src" "$out"
    return 0
  fi
  # Escapa \ & | (delimitador) no lado de substituição do sed.
  escaped="$(printf '%s' "$TOOLS_ROOT" | sed -e 's/[\\&|]/\\&/g')"
  sed "s|\\\$HOME/development/tools|$escaped|g" "$src" > "$out"
  is_valid_json "$out" \
    || die "não consegui reescrever o caminho de $src para '$TOOLS_ROOT' sem quebrar o JSON — instale manualmente."
}

# Lista os scripts registrados como hook dentro de um config JSON.
# Args: json_file
list_hook_commands() {
  if [ "$MERGE_ENGINE" = "jq" ]; then
    jq -r '.. | objects | select(has("command")) | .command' "$1" 2>/dev/null
  else
    python3 -c '
import json, sys

def walk(node):
    if isinstance(node, dict):
        value = node.get("command")
        if isinstance(value, str):
            print(value)
        for child in node.values():
            walk(child)
    elif isinstance(node, list):
        for child in node:
            walk(child)

with open(sys.argv[1]) as f:
    walk(json.load(f))
' "$1" 2>/dev/null
  fi
}

# Um hook sem bit de execução falha em silêncio, e um checkout via .zip perde
# esse bit. Marca só os scripts que o config realmente registra — lib.sh é
# sourced, não executado, e não deve virar executável.
# Args: rendered_source_file
ensure_hooks_executable() {
  local cmd
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    cmd="${cmd/#\$HOME/$HOME}"
    [ -f "$cmd" ] && chmod +x "$cmd" 2>/dev/null
  done < <(list_hook_commands "$1")
  return 0
}

# Args: file
ensure_json_file() {
  local f="$1"
  if [ ! -f "$f" ]; then
    printf '{}\n' > "$f"
    return 0
  fi
  is_valid_json "$f" || die "$f existe mas não é JSON válido — corrija manualmente antes de instalar."
}

# Args: file
backup_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  cp "$f" "${f}.bak-$(date +%s)"
}

# Mescla o config de hooks de source_file DENTRO de target_file (escreve o
# resultado em target_file), sem apagar nada que já exista (permissions,
# autoMode, outros hooks manuais etc.) e sem duplicar entradas se rodar de
# novo. Entradas que já existem são mantidas ONDE ESTÃO e as novas vão pro
# fim da lista: o `unique` do jq usado antes ordenava o array inteiro por
# JSON canônico e reordenava silenciosamente os hooks que o usuário já
# tinha — e hook de PreToolUse roda na ordem em que está no arquivo.
# Despacha pra jq ou python3 conforme detect_merge_engine().
# Args: target_file source_file source_shape target_shape
#   shape ∈ {flat, nested} — nested = eventos dentro de ".hooks"
merge_hooks_json() {
  local target_file="$1" source_file="$2" source_shape="$3" target_shape="$4"

  if [ "$MERGE_ENGINE" = "python3" ]; then
    local out; out="$(mktemp)"
    python3 "$TOOLS_ROOT/install_merge.py" "$target_file" "$source_file" "$source_shape" "$target_shape" "$out" \
      || { rm -f "$out"; die "falha ao mesclar $source_file em $target_file (python3)"; }
    cat "$out" > "$target_file"
    rm -f "$out"
    return 0
  fi

  local tmp src_expr append_new
  tmp="$(mktemp)"
  [ "$source_shape" = "nested" ] && src_expr='$srcs[0].hooks' || src_expr='$srcs[0]'
  # Acrescenta ao array do evento só o que ainda não está lá, preservando a
  # ordem existente. `==` do jq compara objetos por chave, não por ordem de
  # chave — mesma semântica do `not in` do install_merge.py.
  append_new='reduce $src[$event][] as $item ((.[$event] // []);
                if any(.[]; . == $item) then . else . + [$item] end)'

  if [ "$target_shape" = "nested" ]; then
    jq --slurpfile srcs "$source_file" "
      (${src_expr}) as \$src
      | .hooks = (
          (.hooks // {}) as \$th
          | reduce (\$src | keys[]) as \$event (\$th;
              .[\$event] = ( ${append_new} )
            )
        )
    " "$target_file" > "$tmp" || { rm -f "$tmp"; die "falha ao mesclar $source_file em $target_file (jq)"; }
  else
    jq --slurpfile srcs "$source_file" "
      (${src_expr}) as \$src
      | reduce (\$src | keys[]) as \$event (.;
          .[\$event] = ( ${append_new} )
        )
    " "$target_file" > "$tmp" || { rm -f "$tmp"; die "falha ao mesclar $source_file em $target_file (jq)"; }
  fi
  cat "$tmp" > "$target_file"
  rm -f "$tmp"
}

# Args: tool_key platform scope [repo_path]
install_one() {
  local tool_key="$1" platform="$2" scope="$3" repo_path="${4:-}"
  local tool_dir="$TOOLS_ROOT/${TOOL_DIR[$tool_key]}"
  local source_file target_file source_shape target_shape

  if [ "$platform" = "claude" ]; then
    source_file="$tool_dir/examples/claude-settings.json"
    source_shape="nested"
    target_shape="nested"
    if [ "$scope" = "global" ]; then
      target_file="$HOME/.claude/settings.json"
    else
      target_file="$repo_path/.claude/settings.json"
    fi
  else
    source_file="$tool_dir/examples/devin-hooks.json"
    source_shape="flat"
    if [ "$scope" = "global" ]; then
      target_file="$HOME/.config/devin/config.json"
      target_shape="nested"
    else
      target_file="$repo_path/.devin/hooks.v1.json"
      target_shape="flat"
    fi
  fi

  [ -f "$source_file" ] || die "$source_file não existe (ferramenta '$tool_key' sem exemplo pra '$platform')"

  local rendered_source; rendered_source="$(mktemp)"
  render_source_file "$source_file" "$rendered_source"
  source_file="$rendered_source"

  local target_exists=false
  [ -f "$target_file" ] && target_exists=true

  # dry-run não toca o filesystem de verdade nenhuma vez — nem mkdir, nem
  # criar o {} inicial. Simula tudo num arquivo temporário.
  if [ "$DRY_RUN" = "true" ]; then
    local tmp; tmp="$(mktemp)"
    if [ "$target_exists" = "true" ]; then
      is_valid_json "$target_file" || die "$target_file existe mas não é JSON válido — corrija manualmente antes de instalar."
      cp "$target_file" "$tmp"
    else
      printf '{}\n' > "$tmp"
    fi
    merge_hooks_json "$tmp" "$source_file" "$source_shape" "$target_shape"
    if [ "$target_exists" = "true" ] && diff -q "$target_file" "$tmp" >/dev/null 2>&1; then
      echo "[dry-run] $target_file: ${TOOL_DIR[$tool_key]} ($platform) já instalado, nada mudaria"
    elif [ "$target_exists" = "true" ]; then
      echo "[dry-run] $target_file mudaria (${TOOL_DIR[$tool_key]}, $platform):"
      diff -u "$target_file" "$tmp" | sed 's/^/    /'
    else
      echo "[dry-run] $target_file seria CRIADO (${TOOL_DIR[$tool_key]}, $platform):"
      sed 's/^/    /' "$tmp"
    fi
    rm -f "$tmp" "$rendered_source"
    return 0
  fi

  mkdir -p "$(dirname "$target_file")" 2>/dev/null || true
  ensure_json_file "$target_file"
  ensure_hooks_executable "$source_file"

  # Só faz backup + escreve se algo realmente muda — rodar de novo sem
  # mudança nenhuma não deve acumular backup.
  local tmp; tmp="$(mktemp)"
  cp "$target_file" "$tmp"
  merge_hooks_json "$tmp" "$source_file" "$source_shape" "$target_shape"
  local caveat="${TOOL_CAVEAT[${tool_key}:${platform}]:-}"

  if diff -q "$target_file" "$tmp" >/dev/null 2>&1; then
    echo "=    ${TOOL_DIR[$tool_key]} -> $target_file ($platform) — já instalado"
    rm -f "$tmp" "$rendered_source"
    # O aviso vale a cada execução: reinstalar não muda o config, mas quem
    # está lendo a saída continua precisando saber do caveat.
    [ -n "$caveat" ] && echo "     atenção: $caveat"
    return 0
  fi

  backup_file "$target_file"
  # cat em vez de mv: mv trocaria o arquivo alvo pelo temporário do mktemp e
  # levaria junto o modo 600 dele — um settings.json 644 virava 600.
  cat "$tmp" > "$target_file"
  rm -f "$tmp" "$rendered_source"
  echo "OK   ${TOOL_DIR[$tool_key]} -> $target_file ($platform)"

  [ -n "$caveat" ] && echo "     atenção: $caveat"
  return 0
}

# --- parsing de flags -----------------------------------------------------

TOOLS_FLAG=""
PLATFORM_FLAG=""
SCOPE_FLAG=""
REPO_FLAG=""
INTERACTIVE=true

for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    --list) list_tools; exit 0 ;;
    # --dry-run não desliga o modo interativo: "./install.sh --dry-run"
    # sozinho tem que poder perguntar o que simular, não morrer pedindo flags.
    --dry-run) DRY_RUN=true ;;
    --yes) ASSUME_YES=true ;;
    --tools=*) TOOLS_FLAG="${arg#--tools=}"; INTERACTIVE=false ;;
    --platform=*) PLATFORM_FLAG="${arg#--platform=}"; INTERACTIVE=false ;;
    --scope=*) SCOPE_FLAG="${arg#--scope=}"; INTERACTIVE=false ;;
    --repo=*) REPO_FLAG="${arg#--repo=}"; INTERACTIVE=false ;;
    *) die "flag desconhecida: $arg (veja --help)" ;;
  esac
done

detect_merge_engine

# --- modo interativo --------------------------------------------------------

if [ "$INTERACTIVE" = "true" ] && [ -t 0 ]; then
  echo "=== Instalador de hooks — $(basename "$TOOLS_ROOT") ==="
  [ "$DRY_RUN" = "true" ] && echo "(dry-run: nada será escrito)"
  echo
  # Numerada porque o prompt pede número — a lista sem número deixava a
  # pergunta sem resposta possível.
  list_tools_numbered
  echo "  a) todas"
  echo
  read -rp "Quais instalar (números ou nomes separados por vírgula, ou 'a')? " tools_choice
  if [ "$tools_choice" = "a" ]; then
    TOOLS_FLAG="all"
  else
    interactive_selected=()
    IFS=',' read -ra choices <<< "$tools_choice"
    for choice in "${choices[@]}"; do
      choice="$(printf '%s' "$choice" | tr -d '[:space:]')"
      [ -z "$choice" ] && continue
      matched=""
      # Aceita número da lista OU nome da ferramenta: quem digita "security"
      # não deveria ser respondido com "nenhuma ferramenta válida".
      if [ -n "${TOOL_DIR[$choice]:-}" ]; then
        matched="$choice"
      else
        idx=1
        for key in "${TOOL_KEYS[@]}"; do
          [ "$idx" = "$choice" ] && matched="$key"
          idx=$((idx + 1))
        done
      fi
      [ -z "$matched" ] && die "opção inválida: '$choice' (use número da lista, nome da ferramenta ou 'a')"
      interactive_selected+=("$matched")
    done
    [ "${#interactive_selected[@]}" -eq 0 ] && die "nenhuma ferramenta escolhida"
    TOOLS_FLAG="$(IFS=,; echo "${interactive_selected[*]}")"
  fi

  echo
  echo "Plataforma:"
  echo "  1) Claude Code"
  echo "  2) Devin CLI"
  echo "  3) Ambas"
  read -rp "Escolha [1-3]: " p_choice
  case "$p_choice" in
    1) PLATFORM_FLAG="claude" ;;
    2) PLATFORM_FLAG="devin" ;;
    3) PLATFORM_FLAG="both" ;;
    *) die "opção inválida" ;;
  esac

  echo
  echo "Escopo:"
  echo "  1) Global (~) — vale pra todos os repositórios desta máquina"
  echo "  2) Este repositório"
  read -rp "Escolha [1-2]: " s_choice
  case "$s_choice" in
    1) SCOPE_FLAG="global" ;;
    2)
      SCOPE_FLAG="repo"
      read -rp "Caminho do repositório [$PWD]: " repo_input
      REPO_FLAG="${repo_input:-$PWD}"
      ;;
    *) die "opção inválida" ;;
  esac
  echo
fi

# --- validação --------------------------------------------------------------

[ -z "$TOOLS_FLAG" ] && die "faltou --tools (ou 'all'). Veja --help."
[ -z "$PLATFORM_FLAG" ] && die "faltou --platform (claude|devin|both). Veja --help."
[ -z "$SCOPE_FLAG" ] && die "faltou --scope (global|repo). Veja --help."

case "$PLATFORM_FLAG" in
  claude) PLATFORMS=(claude) ;;
  devin) PLATFORMS=(devin) ;;
  both) PLATFORMS=(claude devin) ;;
  *) die "--platform inválido: $PLATFORM_FLAG (use claude|devin|both)" ;;
esac

case "$SCOPE_FLAG" in
  global) REPO_PATH="" ;;
  repo)
    REPO_PATH="${REPO_FLAG:-$PWD}"
    [ -d "$REPO_PATH" ] || die "--repo aponta pra um diretório que não existe: $REPO_PATH"
    REPO_PATH="$(cd "$REPO_PATH" && pwd)"
    ;;
  *) die "--scope inválido: $SCOPE_FLAG (use global|repo)" ;;
esac

if [ "$TOOLS_FLAG" = "all" ]; then
  SELECTED_TOOLS=("${TOOL_KEYS[@]}")
else
  IFS=',' read -ra SELECTED_TOOLS <<< "$TOOLS_FLAG"
  for t in "${SELECTED_TOOLS[@]}"; do
    [ -n "${TOOL_DIR[$t]:-}" ] || die "ferramenta desconhecida: '$t' (veja --list)"
  done
fi

# --- resumo + confirmação ---------------------------------------------------

echo "Vai instalar:"
for t in "${SELECTED_TOOLS[@]}"; do
  for p in "${PLATFORMS[@]}"; do
    if [ "$SCOPE_FLAG" = "global" ]; then
      echo "  - ${TOOL_DIR[$t]} ($p, global)"
    else
      echo "  - ${TOOL_DIR[$t]} ($p, repo=$REPO_PATH)"
    fi
  done
done
echo

if [ "$DRY_RUN" != "true" ] && [ "$ASSUME_YES" != "true" ]; then
  read -rp "Confirma? [s/N] " confirm
  case "$confirm" in
    s|S|sim|y|Y|yes) ;;
    *) echo "Cancelado."; exit 0 ;;
  esac
fi

# --- execução -----------------------------------------------------------

for t in "${SELECTED_TOOLS[@]}"; do
  for p in "${PLATFORMS[@]}"; do
    install_one "$t" "$p" "$SCOPE_FLAG" "$REPO_PATH"
  done
done

if [ "$DRY_RUN" != "true" ]; then
  echo
  echo "Pronto."
fi
