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

interval_sec="$(review_poll_interval_sec)"
max_attempts="$(review_poll_max_attempts)"
skill_path="$(review_skill_path)"
max_per_branch="$(review_max_per_branch)"

if ! command -v gh >/dev/null 2>&1; then
  log "ERRO: 'gh' não encontrado no PATH — sem ele não dá pra consultar a CI nem a PR. Abortando."
  exit 1
fi

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

  # Classifica cada check-run com o jq embutido do gh, uma linha por run, em
  # vez de grepar o JSON cru: o espaçamento da saída do gh não é contrato, um
  # check chamado `"conclusion":"success"` envenenaria a contagem, e status
  # que não sejam queued/in_progress (waiting, requested, pending) ficavam
  # invisíveis — o polling encerrava como "success" com check ainda rodando.
  # per_page=100 + --paginate: a API devolve só 30 check-runs por padrão.
  check_states="$(gh api "repos/$repo/commits/$commit_sha/check-runs?per_page=100" --paginate --jq '
    .check_runs[]
    | if .status != "completed" then "pending"
      elif .conclusion == "success" then "success"
      elif (.conclusion == "failure" or .conclusion == "cancelled"
            or .conclusion == "timed_out" or .conclusion == "action_required"
            or .conclusion == "startup_failure") then "failure"
      else "other" end' 2>/dev/null || printf '')"

  success_count=$(printf '%s\n' "$check_states" | grep -c '^success$')
  failure_count=$(printf '%s\n' "$check_states" | grep -c '^failure$')
  pending_count=$(printf '%s\n' "$check_states" | grep -c '^pending$')

  state="$(classify_state "$success_count" "$failure_count" "$pending_count" "$attempt" "$max_attempts")"

  log "tentativa $attempt/$max_attempts — sucesso:$success_count falha:$failure_count pendente:$pending_count -> estado:$state"

  [ "$state" != "pending" ] && break

  sleep "$interval_sec"
done

log "Polling encerrado com estado final: $state"
trace_log "$repo" "$branch" "polling_finished" "estado=$state commit=$commit_sha"

pr_url="$(cd "$cwd" && gh pr view "$branch" --json url -q .url 2>/dev/null || echo "")"
checks_url="https://github.com/$repo/commit/$commit_sha/checks"

# Bifurcação nova: repos de auto-merge pulam a revisão inteiramente (e o
# gate); os demais passam pelo gate de quantidade de revisões por branch
# antes de abrir a janela. Roda aqui — dentro do poller, onde "gh" já está
# autenticado/resolvido — nunca dentro do final_script (Git Bash nativo do
# Windows, onde python3 pode nem estar no PATH).
if [ "$state" = "success" ] && [ -n "$pr_url" ]; then
  if is_automerge_repo "$repo"; then
    log "Repositório $repo configurado para auto-merge — pulando revisão automatizada."
    trace_log "$repo" "$branch" "automerge_triggered" "pr=$pr_url"

    comment_body="A verificação de CI foi concluída com sucesso para esta pull request. Este repositório está configurado para merge automático (AGENT_PR_REVIEW_AUTOMERGE_REPOS), então a revisão automatizada por agente foi propositalmente pulada e o merge será realizado agora, sem intervenção manual."

    if (cd "$cwd" && gh pr comment "$pr_url" --body "$comment_body") >>"$log_file" 2>&1; then
      log "Comentário de auto-merge postado na PR."
      trace_log "$repo" "$branch" "automerge_comment_posted" "pr=$pr_url"
    else
      log "ERRO: falha ao postar comentário de auto-merge na PR."
      trace_log "$repo" "$branch" "automerge_comment_failed" "pr=$pr_url"
    fi

    if (cd "$cwd" && gh pr merge "$pr_url" --merge) >>"$log_file" 2>&1; then
      log "Merge automático concluído."
      trace_log "$repo" "$branch" "automerge_succeeded" "pr=$pr_url"
    else
      log "ERRO: merge automático falhou."
      trace_log "$repo" "$branch" "automerge_failed" "pr=$pr_url"
    fi
    exit 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    log "AVISO: python3 não encontrado neste ambiente ($environment) — gate de revisões desabilitado, prosseguindo sem checar/gravar contagem."
    trace_log "$repo" "$branch" "gate_check_error" "motivo=python3_ausente pr=$pr_url"
    # fail-open: cai direto no fluxo normal de abertura de janela abaixo.
  else
    gate_output="$(python3 "$SCRIPT_DIR/review-db.py" check-and-increment \
      --db-path "$(review_db_path)" --repo "$repo" --branch "$branch" \
      --max "$max_per_branch" --commit-sha "$commit_sha" --pr-url "$pr_url" \
      2>>"$log_file")"
    gate_status=$?

    if [ "$gate_status" -eq 2 ]; then
      read -r _ gate_count gate_max <<< "$gate_output"
      log "Revisão não iniciada — excesso de PRs automatizados para esta branch ($gate_count/$gate_max)."
      trace_log "$repo" "$branch" "review_blocked_by_gate" "count=$gate_count max=$gate_max pr=$pr_url"
      exit 0
    elif [ "$gate_status" -ne 0 ]; then
      log "ERRO: falha ao consultar/gravar o contador de revisões — prosseguindo mesmo assim (fail-open)."
      trace_log "$repo" "$branch" "gate_check_error" "pr=$pr_url"
      # fail-open, mesma decisão do caso "python3 ausente" acima
    else
      read -r _ gate_count_after gate_max <<< "$gate_output"
      log "Revisão autorizada pelo gate ($gate_count_after/$gate_max)."
      trace_log "$repo" "$branch" "review_invoked" "count=$gate_count_after max=$gate_max pr=$pr_url"
    fi
  fi
fi

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

# Todo valor interpolado aqui (branch, repo, caminhos) passa por
# emit_script_line, que escapa com printf %q. O git aceita aspas simples no
# nome da branch (`feature/it's-broken`) — interpolar direto dentro de '...'
# gerava um script quebrado e dava pra injetar comando pelo nome da branch.
{
  printf '#!/usr/bin/env bash\n'
  emit_script_line cd "$skill_path_native"
  emit_script_line cat "$log_file_native"
  printf 'echo\n'
  case "$state" in
    success)
      if [ -n "$pr_url" ]; then
        emit_script_line echo "✅ CI passou para a branch $branch — abrindo revisão de PR."
        # Plataforma/prompt configurável via AGENT_PR_REVIEW_PLATFORM_CMD
        # (default: Claude Code + skill review-pr) — ver lib.sh.
        printf '%s\n' "$(render_platform_cmd_line "$pr_url" "$repo")"
      else
        emit_script_line echo "✅ CI passou para a branch $branch, mas nenhuma PR foi encontrada ainda para invocar a revisão."
        emit_script_line echo "Abra a PR e rode a skill review-pr manualmente quando estiver pronta."
        printf 'exec bash\n'
      fi
      ;;
    failure)
      emit_script_line echo "❌ CI falhou para a branch $branch"
      emit_script_line echo "Repositório: $repo"
      emit_script_line echo "Commit: $commit_sha"
      emit_script_line echo "Automação de review NÃO foi executada."
      emit_script_line echo "Veja os detalhes em: $checks_url"
      printf 'exec bash\n'
      ;;
    timeout)
      emit_script_line echo "⚠️  CI não respondeu após $max_attempts tentativas para a branch $branch"
      emit_script_line echo "Repositório: $repo"
      emit_script_line echo "Commit: $commit_sha"
      emit_script_line echo "A automação de review NÃO foi executada — motivo: sem resposta definitiva da CI (nem sucesso, nem falha)."
      emit_script_line echo "Verifique manualmente em: $checks_url"
      printf 'exec bash\n'
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
