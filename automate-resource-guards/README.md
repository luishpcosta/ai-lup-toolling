# automate-resource-guards

Guard `PreToolUse` de **orçamento**: mesmo mecanismo de bloqueio de
[`automate-security/`](../automate-security) (exit 2), mas o risco é a agente estourar custo e
paralelismo, não segurança — daí a pasta separada. Compatível com Claude Code e Devin CLI.

## Guard

| Guard | Bloqueia |
|---|---|
| `subagent-budget-guard.sh` | Spawn de subagente (ferramenta `Agent`) quando já há `RESOURCE_GUARD_MAX_SUBAGENTS` (default 5) ativos — isto é, spawnados há menos de `RESOURCE_GUARD_TTL_SECONDS` (default 1800s). |

Cada spawn autorizado vira uma linha `<timestamp>|agent` no tracker
(`~/.claude/active-agents` por padrão). A contagem e a gravação rodam sob lock por diretório, então
spawns simultâneos não passam os dois pelo mesmo slot. Não conseguir o lock **não** bloqueia o
spawn: travar a sessão por causa de um lock seria pior que deixar o orçamento estourar — fica
registrado no trace log como `WARNING`.

## Instalar

```bash
../install.sh --tools=resource-guards --platform=claude --scope=global
```

Manualmente: `examples/claude-settings.json` → `.claude/settings.json`, ou
`examples/devin-hooks.json` → `.devin/hooks.v1.json`.

**Devin CLI — não confirmado**: a documentação pública não lista o nome da ferramenta de spawn de
subagente. O matcher usa `"Agent"` (confirmado no Claude Code) como melhor esforço. Rode `/hooks`
numa sessão Devin depois de spawnar um subagente para confirmar o `tool_name` real antes de confiar
nisso lá.

## Config (`config.env`)

| Variável | Papel |
|---|---|
| `RESOURCE_GUARD_ENABLED` | Liga/desliga (`true` por padrão) |
| `RESOURCE_GUARD_MAX_SUBAGENTS` | Máximo de subagentes ativos (default `5`) |
| `RESOURCE_GUARD_TTL_SECONDS` | Segundos até um spawn sair da contagem (default `1800`) |
| `RESOURCE_GUARD_TRACKER_PATH` | Arquivo de tracking (default `~/.claude/active-agents`) |
| `RESOURCE_GUARD_TRACE_LOG_PATH` | Onde gravar o trace log (default: `data/trace.log` nesta pasta) |

Variável já exportada no ambiente vence sobre o arquivo. Valor não-numérico em
`MAX_SUBAGENTS`/`TTL_SECONDS` cai no default em vez de quebrar o guard.

## Limites conhecidos

- O guard não sabe quando um subagente **termina** — nenhum evento de hook informa isso. "Ativo" é
  estimado por idade (`TTL_SECONDS`), então um subagente que terminou em 2 minutos continua ocupando
  slot até o TTL expirar. Ajuste o TTL para a duração típica dos seus subagentes.
- O tracker é por máquina, não por sessão: várias sessões concorrem pelo mesmo orçamento.

## Trace log (auditoria)

Todo `BLOCKED` (e o `WARNING` de lock indisponível) vai para `data/trace.log`, um evento por linha,
por máquina, fora do controle de versão.

## Testar

```bash
bash hooks/tests/run-tests.sh

TRACKER=$(mktemp -d)/agents
for i in 1 2 3; do
  echo '{"tool_name":"Agent"}' \
    | RESOURCE_GUARD_TRACKER_PATH=$TRACKER RESOURCE_GUARD_MAX_SUBAGENTS=2 \
      hooks/guards/subagent-budget-guard.sh
  echo "spawn $i -> exit=$?"          # 0, 0, 2
done
```
