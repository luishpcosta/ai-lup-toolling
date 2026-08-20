# automate-review

Review de PR assíncrono depois do push. Um hook detecta `git push` numa branch `feature/*`,
acompanha a CI em segundo plano e abre uma janela com o resultado — invocando a skill
[`review-pr`](.claude/skills/review-pr) quando a CI passa. Compatível com Claude Code, Devin CLI ou
qualquer ferramenta de linha de comando que você configure.

Esta pasta é compartilhada por máquina, não por repositório: todo repo que registra o hook usa os
mesmos scripts e a mesma skill.

## Como funciona

```
git push (feature/*)
  └─ post-push-review.sh          hook PostToolUse: confere gate, retorna em ~ms
       └─ poll-and-review.sh      background (setsid): resolve repo/commit via git+gh
            ├─ long-polling dos check-runs → success | failure | timeout
            ├─ repo com automerge?  → comenta na PR + gh pr merge, fim
            ├─ gate por branch?     → acima do limite, para aqui
            └─ open-terminal.sh    → janela com o log + a revisão já invocada
```

**Vem desligado**: mude `AGENT_PR_REVIEW_ENABLED` para `true` em `config.env` para ligar nesta
máquina.

## Instalar

```bash
../install.sh --tools=review --platform=claude --scope=repo --repo=.
```

Manualmente: `examples/claude-settings.json` → `.claude/settings.json` do repositório, ou
`examples/devin-hooks.json` → `.devin/hooks.v1.json`.

Requisitos: `gh` autenticado, e a CI do repositório expondo check-runs em
`gh api repos/{owner}/{repo}/commits/{sha}/check-runs` (qualquer workflow do GitHub Actions já
satisfaz). `jq` é opcional; `python3` é necessário só para o gate de revisões.

## Configuração (`config.env`)

Tudo fica em [`config.env`](./config.env), editável direto — não precisa exportar nada no shell.
Variável já exportada no ambiente vence sobre o arquivo.

| Variável | Papel |
|---|---|
| `AGENT_PR_REVIEW_ENABLED` | Liga/desliga a automação (`false` por padrão) |
| `AGENT_PR_REVIEW_POLL_INTERVAL_SEC` | Intervalo entre tentativas de polling (default `30`) |
| `AGENT_PR_REVIEW_POLL_MAX_ATTEMPTS` | Tentativas antes de declarar timeout (default `20`) |
| `AGENT_PR_REVIEW_SKILL_PATH` | Pasta onde a janela final abre (esta pasta, por padrão) |
| `AGENT_PR_REVIEW_TERMINAL_CMD` | Array: programa + flags do terminal a abrir |
| `AGENT_PR_REVIEW_PLATFORM_CMD` | Array: programa + prompt da plataforma agêntica a invocar |
| `AGENT_PR_REVIEW_MAX_PER_BRANCH` | Máximo de revisões por (repo, branch) — default `3` |
| `AGENT_PR_REVIEW_AUTOMERGE_REPOS` | Array de `owner/repo` com merge automático — vazio por padrão |
| `AGENT_PR_REVIEW_TRACE_LOG_PATH` | Onde gravar o trace log central |

### Terminal (`AGENT_PR_REVIEW_TERMINAL_CMD`)

Array bash — cada elemento vira um argv, então caminho com espaço funciona sem escaping:

```bash
AGENT_PR_REVIEW_TERMINAL_CMD=('C:\Program Files\Git\usr\bin\bash.exe' -i -l)   # default
```

O script final é passado como **último argumento posicional** (nunca via `-c "<string>"`, que se
mostrou frágil na prática). O programa configurado precisa aceitar um caminho de script e
**interpretar bash** — o script gerado é sempre bash, trocar o terminal não troca a linguagem.
PowerShell ou `cmd.exe` puro aqui quebram tudo: a janela abriria só para mostrar erro de sintaxe.
Suportar um terminal sem bash exigiria gerar o script na linguagem dele, o que não está
implementado. Na prática, todo host Windows que roda Claude Code ou Devin CLI já tem Git Bash ou
WSL.

### Plataforma agêntica (`AGENT_PR_REVIEW_PLATFORM_CMD`)

Mesma ideia, agora para o que é invocado quando a CI passa e a PR é encontrada. Cada elemento aceita
os placeholders `{pr_url}` e `{repo}`:

```bash
# default: Claude Code + skill review-pr
AGENT_PR_REVIEW_PLATFORM_CMD=(claude '/review-pr faça revisão da pr aberta em {pr_url} e submeta os comentarios e relatório da validação')

# Devin CLI — "devin -p" confirmado em docs.devin.ai/pt-BR/cli/essential-commands (single-turn).
# Não há subcomando dedicado de review documentado; a revisão sai do prompt livre.
# AGENT_PR_REVIEW_PLATFORM_CMD=(devin -p "revise a PR aberta em {pr_url} do repositório {repo}")
```

A linha final é sempre prefixada com `MSYS_NO_PATHCONV=1` (senão o Git Bash converte argumentos
começados com `/`, como `/review-pr`, em caminho Windows) e cada elemento é escapado com
`printf '%q'` — prompt com espaço, aspas ou acento funciona sem escaping manual.

### Gate de revisões (`AGENT_PR_REVIEW_MAX_PER_BRANCH`)

Impede que uma branch com muitos pushes dispare a mesma revisão repetidas vezes. Cada revisão
efetivamente invocada vira uma linha em `data/reviews.db` (SQLite, via
[`hooks/review-db.py`](hooks/review-db.py)) associada ao par (repositório, branch); a contagem é
conferida antes de abrir a janela. Acima do limite, a automação só registra "revisão não iniciada" e
sai, sem consumir mais nada.

A checagem e a gravação são atômicas (`BEGIN IMMEDIATE`): dois pushes rápidos na mesma branch, ou
dois pollers em paralelo, não perdem contagem nem estouram o limite.

A contagem **nunca reseta sozinha**. Uma branch que atinge o limite fica bloqueada até mudar de nome
(novo par, contagem zerada) ou até alguém apagar as linhas correspondentes:

```bash
sqlite3 data/reviews.db "DELETE FROM review_invocations WHERE repo='org/repo' AND branch='feature/x';"
python3 hooks/review-db.py count --db-path data/reviews.db --repo org/repo --branch feature/x
```

Sem `python3`, ou se `review-db.py` falhar, a automação segue **fail-open**: a revisão abre sem
gate, com `gate_check_error` no log.

### Merge automático (`AGENT_PR_REVIEW_AUTOMERGE_REPOS`)

Lista **opt-in**, vazia por padrão. Para um `owner/repo` listado, quando a CI passa e há PR aberta a
automação pula a revisão inteiramente (não abre janela, não invoca plataforma, não toca no gate),
comenta na PR explicando e roda `gh pr merge --merge`.

> **Risco**: é merge commit imediato, **sem** `--auto`, ou seja **sem esperar** requisitos de branch
> protection (aprovação obrigatória, outros checks). Decisão deliberada e mais arriscada que o
> padrão do GitHub. Só liste um repositório aqui se tiver certeza de que nenhuma proteção depende de
> revisão humana.

Comentário e merge são logados separadamente, com sucesso ou falha.

## Logs

| Log | Onde | Conteúdo |
|---|---|---|
| Por branch | `<repo>/.claude/logs/pr-review-<branch>.log` | Passo a passo de um push: ambiente, tentativas de polling, decisão |
| Trace central | `data/trace.log` (configurável) | Um evento por linha, todos os repos/branches da máquina: push detectado, estado final do polling, revisão invocada ou bloqueada, merge automático, erros |

A automação também grava o script da janela final em `<repo>/.claude/logs/.pr-review-final-*.sh` —
vale ignorar `.claude/logs/` no `.gitignore` dos repositórios que usam isso.

`data/reviews.db` e `data/trace.log` são dados de runtime da máquina, fora do controle de versão.

## Compatibilidade com Devin CLI

`post-push-review.sh` não assume nada específico do Claude Code: lê o payload por stdin
(`tool_input.command`/`cwd`, formato comum às duas) e confere **ele mesmo** se o comando é um `git
push`. Isso importa porque o `"if": "Bash(git push *)"` é um recurso do Claude Code — o matcher do
Devin filtra só pelo nome da ferramenta (`"exec"`), então sem essa checagem o script dispararia a
cada comando de shell.

A leitura usa `jq` → `python3` → regex, porque `jq` não vem no Git for Windows/MSYS2.

**Não confirmado**: se o Devin tem um campo `async` equivalente ao do Claude Code — os exemplos da
doc tratam hooks como síncronos. Não é problema: `post-push-review.sh` dispara o poller com `setsid`
(ou `nohup`), então ele ganha sessão própria e sobrevive ao fim do hook. Medido nesta versão, o
entrypoint retorna em ~44ms e o poller segue rodando.

## Limites conhecidos

- Só reage a branch `feature/*`.
- A janela final abre em `AGENT_PR_REVIEW_SKILL_PATH`, nunca no repositório onde o push aconteceu.
- Sem `gh` no PATH o poller aborta antes de começar (registrado no log da branch).
- Nenhum check-run encontrado até o fim das tentativas vira `timeout`, não erro — repositório sem CI
  simplesmente nunca abre revisão automática.

## Estrutura

```
automate-review/
├── config.env                   ← configuração, editável
├── data/                        ← runtime (SQLite + trace.log), criada sob demanda, git-ignored
├── examples/                    ← hooks prontos para Claude Code e Devin CLI
├── .claude/skills/review-pr/    ← a skill de revisão (convenção do Claude Code)
└── hooks/
    ├── lib.sh                   ← funções puras + carregamento do config.env
    ├── post-push-review.sh      ← entrypoint do hook (gate rápido)
    ├── poll-and-review.sh       ← poller pesado, em background
    ├── open-terminal.sh         ← abre a janela final
    ├── review-db.py             ← gate de revisões (SQLite)
    └── tests/                   ← run-tests.sh (bash) + test_review_db.py (unittest)
```

## Testar

```bash
bash hooks/tests/run-tests.sh
python3 -m unittest hooks.tests.test_review_db -v
```
