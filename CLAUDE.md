# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## O que é este repositório

Coleção de automações (hooks + skill) para agentes de IA de linha de comando (Claude Code, Devin
CLI), instaláveis em qualquer repositório via `./install.sh`. Cada subpasta `automate-*/` é uma
ferramenta independente e autocontida — mesma estrutura interna, config própria, testes próprios.
Escrito em bash + Python, sem framework externo. README em português (pt-BR) — mantenha esse idioma
ao editar documentação existente.

## Comandos

```bash
# Rodar todos os testes de todas as ferramentas
for d in automate-*/; do (cd "$d" && bash hooks/tests/run-tests.sh); done

# Testes Python (só automate-review tem)
(cd automate-review && python3 -m unittest hooks.tests.test_review_db -v)

# Testar uma ferramenta isolada
(cd automate-security && bash hooks/tests/run-tests.sh)

# Instalar (interativo ou por flags)
./install.sh
./install.sh --tools=all --platform=both --scope=global --yes
./install.sh --tools=security --platform=claude --scope=repo --repo=/caminho/do/repo
./install.sh --dry-run          # simula, não escreve nada
./install.sh --list             # lista ferramentas disponíveis
```

Requer `jq` **ou** `python3` no PATH (mesclagem segura de JSON no install). `gh` autenticado é
necessário só para `automate-review`.

## Arquitetura

### As quatro ferramentas

| Pasta | Mecanismo | Padrão |
|---|---|---|
| `automate-review/` | `PostToolUse` (detecta `git push` em `feature/*`) → poller em background via `gh` → abre terminal invocando a skill `review-pr` quando a CI passa | **desligada** (`AGENT_PR_REVIEW_ENABLED=false`) |
| `automate-security/` | `PreToolUse` — guards que bloqueiam (exit 2) exfiltração de credencial e conexão direta com DB remoto | ligada |
| `automate-resource-guards/` | `PreToolUse` — guard de orçamento (limite de subagentes simultâneos) | ligada |
| `automate-session-lifecycle/` | Hooks sem bloqueio (`PreCompact`/`PostCompaction`, `SessionStart`) — checkpoint git e warmup de MCP | ligada |

`automate-security` e `automate-resource-guards` usam o mesmo mecanismo de bloqueio (exit 2 num
`PreToolUse`), mas ficam separados porque a categoria de risco é diferente (segurança vs. custo).

### Convenção interna comum a toda `automate-*/`

```
automate-X/
├── config.env              ← config editável, carregada por hooks/lib.sh; env var já exportada vence
├── data/                   ← runtime (trace.log, SQLite): criada sob demanda, git-ignored, por máquina
├── examples/
│   ├── claude-settings.json    ← fragmento de .claude/settings.json (shape "nested": eventos dentro de "hooks")
│   └── devin-hooks.json        ← fragmento de .devin/hooks.v1.json (shape "flat")
└── hooks/
    ├── lib.sh              ← funções puras + parsing de stdin + trace log; sourced pelos scripts, nunca executado
    ├── <entrypoints>.sh    ← um script por hook/guard, lido via PreToolUse/PostToolUse etc.
    └── tests/run-tests.sh  ← bash puro, sem framework
```

Pontos que se repetem em toda ferramenta e valem para qualquer script novo nessa família:

- **Parsing de stdin em 3 camadas**: `jq` → `python3` → regex. O Git for Windows/MSYS2 não traz
  `jq`, então a camada regex existe de verdade e precisa desfazer escapes JSON (`\"`, `\\`) — veja
  `json_unescape`/`extract_json_string_field` em qualquer `lib.sh`.
- **Compatibilidade Claude Code / Devin CLI**: mesmo payload por stdin (`tool_input.command`),
  mesmo bloqueio por exit 2. O que muda é o matcher (`"Bash"` no Claude Code vs. `"exec"` no Devin) e
  o nome de alguns eventos (`PreCompact` vs. `PostCompaction`). Um script novo deve ler o payload e
  decidir sozinho, nunca confiar no matcher da plataforma para filtrar conteúdo.
- **Trace log**: `data/trace.log`, um evento por linha, só para decisões que importam (`BLOCKED`,
  `WARNING`, `ACTION`, `FAILED`) — nunca "passou sem bater em nada" (viraria ruído). Best-effort:
  nunca derruba o script chamador (`|| true`).
- **`config.env`**: variáveis lidas via `load_config_env()`, que salva os valores já exportados no
  ambiente ANTES de dar `source` no arquivo e os restaura depois — para que env var explícita sempre
  vença sobre o arquivo.
- **Fail-open por padrão**: quando um mecanismo auxiliar falha (gate de revisão sem `python3`, lock
  de tracker indisponível), a automação deixa a ação prosseguir e registra o problema no trace log,
  em vez de travar o agente.

### `install.sh` / `install_merge.py`

Motor de instalação único para as quatro ferramentas. Pontos centrais:

- **Mescla, nunca sobrescreve**: entradas já existentes em `.claude/settings.json` ou
  `.devin/hooks.v1.json` são mantidas na posição original (hook `PreToolUse` roda na ordem do
  arquivo); só o que falta é acrescentado ao fim. Implementado duas vezes com a mesma semântica —
  `jq` inline em `install.sh` e `install_merge.py` como fallback sem `jq`. Uma mudança na lógica de
  merge precisa ser replicada nos dois.
- **Reescreve o caminho dos hooks** (`render_source_file`) trocando o `$HOME/development/tools`
  hardcoded nos `examples/*.json` pelo `TOOLS_ROOT` real deste checkout — por isso o repositório
  pode viver em qualquer lugar.
- **Backup automático** (`.bak-<timestamp>`) só quando algo de fato muda, e é idempotente.
- `--dry-run` nunca toca o filesystem real — toda simulação roda em arquivo temporário.
- `shape` (`flat` vs. `nested`) descreve se os eventos ficam soltos na raiz do JSON (Devin, escopo
  repo) ou dentro de uma chave `"hooks"` (Claude Code sempre; Devin em escopo global).

### `automate-review/` — fluxo assíncrono

```
git push (feature/*)
  └─ post-push-review.sh   PostToolUse: gate rápido (~ms), dispara poller e retorna
       └─ poll-and-review.sh   background (setsid/nohup), sobrevive ao fim do hook
            ├─ long-polling de check-runs via `gh api .../check-runs` → success | failure | timeout
            ├─ repo em AGENT_PR_REVIEW_AUTOMERGE_REPOS? → comenta + `gh pr merge`, fim
            ├─ acima de AGENT_PR_REVIEW_MAX_PER_BRANCH? → só loga, não abre nada
            └─ open-terminal.sh → janela com o log + invoca a skill review-pr
```

O gate de revisões por (repo, branch) é um SQLite (`data/reviews.db`, via `hooks/review-db.py`) com
checagem+gravação atômica (`BEGIN IMMEDIATE`) para tolerar pushes/pollers concorrentes. A contagem
nunca reseta sozinha — só mudando o nome da branch ou apagando as linhas manualmente.

A skill `review-pr` (`automate-review/.claude/skills/review-pr/`) é o que realmente faz a revisão de
código quando invocada; cobre Angular, Go, TypeScript, Python, Java e C#/.NET, com guias de
referência por linguagem em `references/` e um analisador de PR em `scripts/analisador-pr.py`.

## Ao alterar hooks/guards

- Testes são bash puro (`hooks/tests/run-tests.sh`) rodando os scripts via stdin JSON simulado —
  sem mock framework. Adicionar um caso de detecção nova é adicionar um `echo '{"tool_input":...}' |
  script.sh; check exit code` ao `run-tests.sh` da ferramenta.
- Um guard novo em `automate-security/hooks/guards/` ou `automate-resource-guards/hooks/guards/`
  precisa: ler stdin com o padrão de 3 camadas do `lib.sh` local, decidir e sair com 0/2, e logar só
  quando bloqueia ou avisa.
- Alterar `examples/claude-settings.json` ou `examples/devin-hooks.json` de qualquer ferramenta
  exige checar se `install.sh`/`install_merge.py` ainda mesclam corretamente (rode `--dry-run` antes
  e depois).
