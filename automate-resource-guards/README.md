# automate-resource-guards

Guard `PreToolUse` de **orçamento/recurso**: mesmo mecanismo de bloqueio de
[`automate-security/`](../automate-security) (exit 2), mas o risco é a agente estourar
custo/paralelismo, não segurança — por isso pasta própria. Compatível com Claude Code e Devin CLI.

## Guard

| Guard | Bloqueia |
|---|---|
| `subagent-budget-guard.sh` | Spawn de subagente (ferramenta `Agent`) quando já há `RESOURCE_GUARD_MAX_SUBAGENTS` (default 5) ativos — spawnados há menos de `RESOURCE_GUARD_TTL_SECONDS` (default 1800s). |

## Instalar (Claude Code)

Copie `examples/claude-settings.json` pro `.claude/settings.json` do repositório.

## Instalar (Devin CLI)

Copie `examples/devin-hooks.json` pra `.devin/hooks.v1.json`.

**Não confirmado**: a doc pública do Devin CLI não lista um nome de ferramenta pra spawn de
subagente. O matcher usa `"Agent"` (nome confirmado no Claude Code) como melhor esforço — rode
`/hooks` numa sessão Devin depois de spawnar um subagente pra confirmar o `tool_name` real antes de
confiar nisso lá.

## Trace log (auditoria)

Todo `BLOCKED` vai pra `data/trace.log` (por máquina, git-ignored) — mesmo padrão do
`data/trace.log` de [`automate-review/`](../automate-review).

## Config (`config.env`)

| Variável | Papel |
|---|---|
| `RESOURCE_GUARD_ENABLED` | Liga/desliga (`true` por padrão) |
| `RESOURCE_GUARD_MAX_SUBAGENTS` | Máximo de subagentes ativos (default `5`) |
| `RESOURCE_GUARD_TTL_SECONDS` | Segundos até um spawn "expirar" da contagem (default `1800`) |
| `RESOURCE_GUARD_TRACKER_PATH` | Arquivo de tracking (default `~/.claude/active-agents`) |
| `RESOURCE_GUARD_TRACE_LOG_PATH` | Onde grava o trace log (default: `data/trace.log` nesta pasta) |

## Testar

```bash
bash hooks/tests/run-tests.sh

RESOURCE_GUARD_TRACKER_PATH=/tmp/active-agents-test RESOURCE_GUARD_MAX_SUBAGENTS=2 bash -c '
  echo "{\"tool_name\":\"Agent\"}" | hooks/guards/subagent-budget-guard.sh   # exit=0
  echo "{\"tool_name\":\"Agent\"}" | hooks/guards/subagent-budget-guard.sh   # exit=0
  echo "{\"tool_name\":\"Agent\"}" | hooks/guards/subagent-budget-guard.sh   # BLOCKED, exit=2
'
```
