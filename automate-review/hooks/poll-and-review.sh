#!/usr/bin/env bash
# Poller pesado: resolve contexto via git/gh, faz long-polling dos check-runs
# do commit, classifica o resultado em 3 estados finais, e abre a janela final
# correspondente. Disparado em background por post-push-review.sh — nunca
# rodado diretamente pelo hook. Vive em ~/development/tools/automate-review/hooks/,
# fora de qualquer repositório. A janela final abre sempre em $skill_path (Git
# Bash nativo), não no repositório onde o push aconteceu — ver open-terminal.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

cwd="$1"
branch="$2"
feature_name="$3"
log_file="$4"

log() {
  printf '[%s] %s\n' "$(date -Iseconds)" "$1"
}

# shellcheck disable=SC2046
read -r _enabled interval_sec max_attempts skill_path <<< "$(resolve_config)"

environment="$(detect_environment)"
if [ "$environment" = "unknown" ]; then
  log "ERRO: ambiente não reconhecido (nem WSL2 nem Git Bash) — abortando antes do polling."
  exit 1
fi
log "Ambiente detectado: $environment"

repo="$(cd "$cwd" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")"
commit_sha="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || echo "")"
remote_url="$(git -C "$cwd" remote get-url origin 2>/dev/null || echo "")"

if [ -z "$repo" ] || [ -z "$commit_sha" ]; then
  log "ERRO: não foi possível resolver repositório/commit via git/gh — abortando antes do polling."
  exit 1
fi

log "Repositório: $repo | branch: $branch | commit: $commit_sha | remoto: $remote_url"

state="pending"
attempt=0

while [ "$attempt" -lt "$max_attempts" ]; do
  attempt=$((attempt + 1))

  checks_json="$(gh api "repos/$repo/commits/$commit_sha/check-runs" --jq '.check_runs' 2>/dev/null || echo "[]")"

  success_count=$(printf '%s' "$checks_json" | grep -o '"conclusion":"success"' | wc -l)
  failure_count=$(printf '%s' "$checks_json" | grep -oE '"conclusion":"(failure|cancelled|timed_out)"' | wc -l)
  pending_count=$(printf '%s' "$checks_json" | grep -o '"status":"queued"\|"status":"in_progress"' | wc -l)

  state="$(classify_state "$success_count" "$failure_count" "$pending_count" "$attempt" "$max_attempts")"

  log "tentativa $attempt/$max_attempts — sucesso:$success_count falha:$failure_count pendente:$pending_count -> estado:$state"

  [ "$state" != "pending" ] && break

  sleep "$interval_sec"
done

log "Polling encerrado com estado final: $state"

pr_url="$(cd "$cwd" && gh pr view "$branch" --json url -q .url 2>/dev/null || echo "")"
checks_url="https://github.com/$repo/commit/$commit_sha/checks"

final_script="$(dirname "$log_file")/.pr-review-final-${feature_name//\//-}.sh"

# O final_script roda como ARQUIVO dentro do Git Bash nativo do Windows (não
# via string -c inline — comprovadamente frágil, ver open-terminal.sh) — todo
# caminho embutido nele precisa estar traduzido antes de ser escrito.
skill_path_native="$(to_native_path "$environment" "$skill_path")" || {
  log "ERRO: não foi possível traduzir o caminho da skill para o Git Bash nativo."
  exit 1
}
log_file_native="$(to_native_path "$environment" "$log_file")" || {
  log "ERRO: não foi possível traduzir o caminho do log para o Git Bash nativo."
  exit 1
}

{
  echo "#!/usr/bin/env bash"
  echo "cd '$skill_path_native'"
  echo "cat '$log_file_native'"
  echo "echo"
  case "$state" in
    success)
      if [ -n "$pr_url" ]; then
        echo "echo '✅ CI passou para a branch $branch — abrindo revisão de PR.'"
        # Plataforma/prompt configurável via AGENT_PR_REVIEW_PLATFORM_CMD
        # (default: Claude Code + skill review-pr) — ver lib.sh.
        echo "$(render_platform_cmd_line "$pr_url")"
      else
        echo "echo '✅ CI passou para a branch $branch, mas nenhuma PR foi encontrada ainda para invocar a revisão.'"
        echo "echo 'Abra a PR e rode a skill review-pr manualmente quando estiver pronta.'"
        echo "exec bash"
      fi
      ;;
    failure)
      cat <<MSG
echo "❌ CI falhou para a branch feature/$feature_name"
echo "Repositório: $repo"
echo "Commit: $commit_sha"
echo "Automação de review NÃO foi executada."
echo "Veja os detalhes em: $checks_url"
exec bash
MSG
      ;;
    timeout)
      cat <<MSG
echo "⚠️  CI não respondeu após $max_attempts tentativas para a branch feature/$feature_name"
echo "Repositório: $repo"
echo "Commit: $commit_sha"
echo "A automação de review NÃO foi executada — motivo: sem resposta definitiva da CI (nem sucesso, nem falha)."
echo "Verifique manualmente em: $checks_url"
exec bash
MSG
      ;;
  esac
} > "$final_script"
chmod +x "$final_script"

final_script_native="$(to_native_path "$environment" "$final_script")" || {
  log "ERRO: não foi possível traduzir o caminho do script final para o Git Bash nativo."
  exit 1
}

title="review-pr: $state ($branch)"
# A janela abre sempre em $skill_path (pasta da skill, já embutido como `cd`
# no início do final_script), nunca em $cwd (o repo onde o push aconteceu).
"$SCRIPT_DIR/open-terminal.sh" "$environment" "$title" "$final_script_native"
