# automate-session-lifecycle

Hooks de continuidade de sessão — **não bloqueiam nada**, só agem em eventos de ciclo de vida
(compactação de contexto, início de sessão). Categoria própria: diferente de
[`automate-security/`](../automate-security) e [`automate-resource-guards/`](../automate-resource-guards),
que são guards de bloqueio. Compatível com Claude Code e Devin CLI.

## Hooks

| Hook | Evento | Faz |
|---|---|---|
| `compact-checkpoint.sh` | `PreCompact` (Claude Code) / `PostCompaction` (Devin CLI) | Se há mudanças não commitadas, cria `git commit -m "checkpoint: pre-compact auto-save (...)"`. Recuperação: `git log --oneline -5`. |
| `mcp-warmup-wait.sh` | `SessionStart` (mesmo nome nas duas) | Se algum config candidato declara `"mcpServers"`, espera `SESSION_LIFECYCLE_WARMUP_SECONDS` (default 3s) antes do 1º turno. |

## `PreCompact` vs `PostCompaction`

Devin CLI não tem evento "antes" da compactação — só `PostCompaction` (depois). Não é problema
aqui: a compactação só afeta a memória conversacional, nunca o disco. Um `git commit` captura o
mesmo estado de arquivos antes ou depois dela — por isso o **mesmo script** roda sob `PreCompact`
no Claude Code e `PostCompaction` no Devin (só o nome do evento no config muda).

## Onde procurar `mcpServers`

`mcp-warmup-wait.sh` confere uma lista de caminhos candidatos, globais e por-projeto, das duas
plataformas (`~/.claude/settings.json`, `~/.claude.json`, `~/.config/devin/config.json`,
`$DEVIN_PROJECT_DIR/.devin/config.json`, equivalentes em `$PWD`). Primeiro que existir e declarar
`"mcpServers"` já basta. Sem MCP configurado, não espera nada.

## Instalar (Claude Code)

Copie `examples/claude-settings.json` pro `.claude/settings.json` do repositório (`PreCompact` +
`SessionStart`).

## Instalar (Devin CLI)

Copie `examples/devin-hooks.json` pra `.devin/hooks.v1.json` (`PostCompaction` + `SessionStart`).

## Trace log (auditoria)

Toda ação real (commit criado, warmup esperado) vai pra `data/trace.log` (por máquina,
git-ignored) — mesmo padrão do `data/trace.log` de [`automate-review/`](../automate-review) —,
além do próprio `git log` já servir de trilha pro checkpoint.

## Config (`config.env`)

| Variável | Papel |
|---|---|
| `SESSION_LIFECYCLE_CHECKPOINT_ENABLED` | Liga/desliga o checkpoint (`true` por padrão) |
| `SESSION_LIFECYCLE_WARMUP_ENABLED` | Liga/desliga o warmup (`true` por padrão) |
| `SESSION_LIFECYCLE_WARMUP_SECONDS` | Segundos de espera (default `3`) |
| `SESSION_LIFECYCLE_TRACE_LOG_PATH` | Onde grava o trace log (default: `data/trace.log` nesta pasta) |

## Testar

```bash
bash hooks/tests/run-tests.sh
```
