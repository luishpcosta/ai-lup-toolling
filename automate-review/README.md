# automate-review

Review de PR assíncrono depois do push. Um hook detecta `git push` numa branch `feature/*`,
acompanha a CI em segundo plano e, quando a CI passa, roda `claude -p` (ou o comando que você
configurar) **direto em background** no repositório do push — sem abrir janela nenhuma — para
popular a descrição da PR e revisar o código. Compatível com Claude Code, Devin CLI ou qualquer
ferramenta de linha de comando que você configure.

Esta pasta é compartilhada por máquina, não por repositório: todo repo que registra o hook usa os
mesmos scripts. A skill de revisão (`/review-pr` ou outra) é escolha de cada repositório — veja
"Plataforma agêntica" abaixo.

## Como funciona

```
git push (feature/*)
  └─ post-push-review.sh          hook PostToolUse: confere gate, retorna em ~ms
       └─ poll-and-review.sh      background (setsid): resolve repo/commit via git+gh
            ├─ long-polling dos check-runs → success | failure | timeout
            ├─ repo com automerge?     → comenta na PR + gh pr merge, fim
            ├─ gate por branch?        → acima do limite, para aqui
            ├─ success com PR aberta   → roda AGENT_PR_REVIEW_PLATFORM_CMD DIRETO
            │                            (sem janela), cwd no repo do push
            │     ├─ comando terminou OK  → fim, só log
            │     └─ comando falhou       → open-terminal.sh (alerta com o erro)
            └─ failure | timeout | success sem PR → open-terminal.sh (mensagem informativa)
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

Só é usado quando **não** dá pra terminar silenciosamente: CI falhou, deu timeout, a CI passou mas
nenhuma PR foi encontrada ainda, ou `AGENT_PR_REVIEW_PLATFORM_CMD` falhou (exit != 0) — nesse último
caso é o jeito de "chamar atenção" para um erro que aconteceu em background. No caminho feliz
(CI passou, PR encontrada, comando da plataforma terminou com sucesso) nenhuma janela abre.

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

O que roda quando a CI passa e a PR é encontrada — **direto no processo do poller** (já em
background, sem janela nenhuma), com `cwd` no repositório que fez o push, não em
`AGENT_PR_REVIEW_SKILL_PATH`. Cada elemento aceita os placeholders `{pr_url}` e `{repo}`:

```bash
# default: Claude Code, sessão nova (-p), sem skill fixa
AGENT_PR_REVIEW_PLATFORM_CMD=(
  claude -p
  'Contexto: execução automática, não-interativa, disparada porque a CI passou na PR {pr_url} do repositório {repo}. Não há usuário observando esta sessão — não peça confirmação nem espere aprovação, publique diretamente. Primeiro, veja a descrição atual da PR (gh pr view {pr_url} --json body) e, se estiver vazia ou não refletir o que foi feito, gere uma nova a partir de git log/git diff da branch atual e grave com gh pr edit {pr_url} --body-file -. Depois, revise o código desta PR (use a skill /review-pr se este projeto tiver uma instalada; senão, revise você mesmo o diff) e publique os comentários/relatório diretamente, sem esperar aprovação.'
  --permission-mode dontAsk
  --allowedTools
  'Bash(gh pr view *)'
  'Bash(gh pr diff *)'
  'Bash(gh pr edit *)'
  'Bash(gh pr comment *)'
  'Bash(gh pr review *)'
  'Bash(git log *)'
  'Bash(git diff *)'
  'Bash(git show *)'
  'Bash(git status *)'
  Read
  Glob
  Grep
)

# Devin CLI — "devin -p" confirmado em docs.devin.ai/cli/essential-commands
# (single-turn, imprime e sai; sem -c/-r fica stateless). Sem allowlist
# granular documentada — só existe bypass total (ver aviso abaixo). Sem
# subcomando/skill de review documentado; a revisão sai do prompt livre.
AGENT_PR_REVIEW_PLATFORM_CMD=(
  devin -p
  'Contexto: execução automática, não-interativa, disparada porque a CI passou na PR {pr_url} do repositório {repo}. Não há usuário observando esta sessão — não peça confirmação nem espere aprovação, publique diretamente. Primeiro, veja a descrição atual da PR (gh pr view {pr_url} --json body) e, se estiver vazia ou não refletir o que foi feito, gere uma nova a partir de git log/git diff da branch atual e grave com gh pr edit {pr_url} --body-file -. Depois, revise o código desta PR a partir do diff (gh pr diff {pr_url}) e publique os comentários/relatório via gh pr review/gh pr comment diretamente, sem esperar aprovação.'
  --permission-mode bypass
)
```

> **Risco (Devin CLI)**: a documentação do Devin CLI não lista nenhum equivalente a
> `--allowedTools` — a única forma confirmada de rodar `gh`/`git` sem prompt de aprovação é
> `--permission-mode bypass`, que libera **qualquer** comando, não só os necessários pra
> descrição+revisão. É uma superfície de risco maior que o default de Claude Code acima (allowlist
> granular). Não confirmado nesta sessão rodando o binário de verdade — só via
> [docs.devin.ai/cli/essential-commands](https://docs.devin.ai/cli/essential-commands); valide o
> comportamento real antes de habilitar em produção.

A linha final é sempre prefixada com `MSYS_NO_PATHCONV=1` (senão o Git Bash converte argumentos
começados com `/`, como `/review-pr`, em caminho Windows) e cada elemento é escapado com
`printf '%q'` — prompt com espaço, aspas ou acento funciona sem escaping manual.

**Sessão sempre nova**: o default usa `claude -p` sem `--continue`/`--resume` — cada push dispara
uma sessão stateless, sem herdar contexto de pushes anteriores na mesma branch (recuperar "o que foi
feito" é papel do prompt pedir `git log`/`git diff` no `cwd` do push, não de retomar uma sessão de
chat). **Nunca acrescente `--continue`/`--resume` a este comando.**

**Permissão sem trava**: não há terminal pra responder um prompt de permissão em `claude -p`, então o
default usa `--permission-mode dontAsk` + `--allowedTools` com uma allowlist — só os comandos
`gh`/`git`/leitura listados rodam sem prompt; qualquer coisa fora da lista é **negada
automaticamente** (não trava o poller). Ajuste a lista conforme o que a skill/comando do seu
repositório realmente precisa rodar. Evite `--dangerously-skip-permissions`: libera qualquer
ferramenta sem checagem nenhuma, incluindo o que um prompt malicioso ou um bug no texto poderia fazer
rodar no repositório. Confira a sintaxe exata dessas flags com `claude --help` — pode mudar entre
versões.

**Skill de revisão por repositório**: a automação não instala nem exige nenhuma skill. O default
sugere `/review-pr` só se o projeto tiver essa skill instalada localmente (`.claude/skills/`); cada
repositório é livre pra usar outra skill, ou nenhuma (o prompt já cobre "revise você mesmo o diff"
como alternativa), ou até o comando nativo de outra plataforma agêntica.

**Onde o comando precisa estar no PATH**: como agora roda dentro do mesmo shell do poller (WSL2 ou
Git Bash — o que `detect_environment()` identificou), não mais dentro de uma janela nova de Git Bash
nativo, o binário configurado aqui (`claude`, `devin`, etc.) precisa estar no PATH **desse ambiente**,
não só no Git Bash nativo do Windows.

### Gate de revisões (`AGENT_PR_REVIEW_MAX_PER_BRANCH`)

Impede que uma branch com muitos pushes dispare a mesma revisão repetidas vezes. Cada revisão
efetivamente invocada vira uma linha em `data/reviews.db` (SQLite, via
[`hooks/review-db.py`](hooks/review-db.py)) associada ao par (repositório, branch); a contagem é
conferida antes de rodar `AGENT_PR_REVIEW_PLATFORM_CMD`. Acima do limite, a automação só registra
"revisão não iniciada" e sai, sem consumir mais nada.

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
- `AGENT_PR_REVIEW_PLATFORM_CMD` roda com `cwd` no repositório do push; a janela de alerta (quando
  esse comando falha) ou informativa (falha/timeout/sem PR) abre em `AGENT_PR_REVIEW_SKILL_PATH`.
- O binário configurado em `AGENT_PR_REVIEW_PLATFORM_CMD` precisa estar no PATH do ambiente onde o
  poller roda (WSL2 ou Git Bash) — não é mais aberto dentro de uma janela nova de Git Bash nativo.
- Sem `gh` no PATH o poller aborta antes de começar (registrado no log da branch).
- Nenhum check-run encontrado até o fim das tentativas vira `timeout`, não erro — repositório sem CI
  simplesmente nunca abre revisão automática.
- No Devin CLI não há allowlist granular de permissão documentada (nada equivalente a
  `--allowedTools`) — só bypass total (`--permission-mode bypass`), mais arriscado que o default de
  Claude Code. Ver "Plataforma agêntica" acima.

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
