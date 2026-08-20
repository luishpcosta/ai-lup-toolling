# automate-resource-guards

Guards `PreToolUse` de **orçamento/recurso** para agentes de codificação (Claude Code, Devin CLI,
ou outra plataforma compatível) — mesmo mecanismo de bloqueio dos guards de
[`automate-security/`](../automate-security) (intercepta antes de rodar, bloqueia com exit code 2),
mas o risco protegido aqui não é segurança: é a agente **estourar recurso/custo** — hoje, spawnar
subagentes em paralelo demais.

## Por que uma pasta própria, separada de `automate-security/`

Ao inspecionar os 5 guards de `yurukusa/cc-safe-setup` que motivaram esta automação, só 2 eram
segurança de verdade (exfiltração de credencial, conexão indevida com DB — foram pra
`automate-security/`). Este guard (`subagent-budget-guard`) tem o mesmo formato técnico (hook
`PreToolUse`, bloqueia com exit 2), mas resolve um problema categoricamente diferente — controle
de recurso/custo, não uma ameaça de segurança — por isso ganhou categoria própria em vez de ser
misturado ali. Ver [`../automate-session-lifecycle/`](../automate-session-lifecycle) para os
outros 2 guards do lote original (esses nem são guards de bloqueio — são hooks de ciclo de vida
de sessão).

## Guard incluído

| Guard | Bloqueia |
|---|---|
| [`subagent-budget-guard.sh`](hooks/guards/subagent-budget-guard.sh) | Spawn de um novo subagente (ferramenta `Agent`) quando já há `RESOURCE_GUARD_MAX_SUBAGENTS` (default 5) subagentes "ativos" — spawnados há menos de `RESOURCE_GUARD_TTL_SECONDS` (default 1800s/30min). O guard não sabe quando um subagente termina de verdade, só estima por idade (mesma limitação do script original do `cc-safe-setup`). |

Origem: portado de `yurukusa/cc-safe-setup` (`examples/subagent-budget-guard.sh`) — lógica de
contagem/expiração extraída em funções puras testáveis (`hooks/lib.sh`), que operam sobre o
CONTEÚDO do arquivo de tracking como texto, não sobre o filesystem diretamente (I/O real fica só
no entrypoint) — mesma separação usada em `automate-review/` e `automate-security/`.

## Instalar num repositório (Claude Code)

Copie `examples/claude-settings.json` para o `.claude/settings.json` do repositório (ou mescle):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [{ "type": "command", "command": "$HOME/development/tools/automate-resource-guards/hooks/guards/subagent-budget-guard.sh" }]
      }
    ]
  }
}
```

## Instalar num repositório (Devin CLI)

Copie `examples/devin-hooks.json` para `.devin/hooks.v1.json` no repositório.

**O que não está confirmado**: a documentação pública do Devin CLI consultada
(`docs.devin.ai/cli/extensibility/hooks/{overview,lifecycle-hooks}`) não lista um nome de
ferramenta distinto para spawn de subagente — o payload documentado só cobre `tool_name`/
`tool_input` genéricos, sem exemplo específico de multi-agente. `examples/devin-hooks.json` usa
`"Agent"` (o nome confirmado no Claude Code) como melhor esforço, mas **isso não foi testado nem
confirmado no Devin CLI**. Antes de confiar neste guard lá: rode `/hooks` numa sessão Devin CLI
depois de spawnar um subagente pra ver o `tool_name` real que aparece no log, e ajuste o matcher
em `examples/devin-hooks.json` (ou no `entrypoint` — `[ "$TOOL" = "Agent" ]` em
`hooks/guards/subagent-budget-guard.sh`) se o nome for outro.

O resto do mecanismo (payload via stdin JSON, bloqueio por exit code 2) é o mesmo confirmado em
`automate-security/README.md` — só o nome da ferramenta específica de spawn de subagente é a
incógnita aqui.

## Configuração (`config.env`)

| Variável | Papel |
|---|---|
| `RESOURCE_GUARD_ENABLED` | Liga/desliga o guard (`true` por padrão) |
| `RESOURCE_GUARD_MAX_SUBAGENTS` | Máximo de subagentes ativos simultâneos (default `5`) |
| `RESOURCE_GUARD_TTL_SECONDS` | Segundos até um subagente ser considerado "não mais ativo" (default `1800`) |
| `RESOURCE_GUARD_TRACKER_PATH` | Caminho do arquivo de tracking (default `~/.claude/active-agents`, mesmo caminho do script original) |

## Estrutura

```
automate-resource-guards/
├── README.md
├── config.env
├── examples/
│   ├── claude-settings.json
│   └── devin-hooks.json           ← matcher "Agent" NÃO CONFIRMADO no Devin, ver acima
└── hooks/
    ├── lib.sh
    ├── guards/
    │   └── subagent-budget-guard.sh
    └── tests/
        └── run-tests.sh
```

## Testar

```bash
bash hooks/tests/run-tests.sh

# smoke test manual (usa um tracker temporário pra não sujar o real)
RESOURCE_GUARD_TRACKER_PATH=/tmp/active-agents-test RESOURCE_GUARD_MAX_SUBAGENTS=2 bash -c '
  echo "{\"tool_name\":\"Agent\"}" | hooks/guards/subagent-budget-guard.sh   # exit=0
  echo "{\"tool_name\":\"Agent\"}" | hooks/guards/subagent-budget-guard.sh   # exit=0
  echo "{\"tool_name\":\"Agent\"}" | hooks/guards/subagent-budget-guard.sh   # BLOCKED, exit=2
'
```
