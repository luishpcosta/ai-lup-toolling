# automate-session-lifecycle

Hooks de **ciclo de vida de sessão** para agentes de codificação (Claude Code, Devin CLI, ou outra
plataforma compatível) — diferente de [`automate-security/`](../automate-security) e
[`automate-resource-guards/`](../automate-resource-guards), nenhum destes dois hooks **bloqueia**
nada: são ações de melhor esforço amarradas a eventos de ciclo de vida (compactação de contexto,
início de sessão), não guards de `PreToolUse`.

## Por que uma pasta própria

Dos 5 guards de `yurukusa/cc-safe-setup` inspecionados no início desta automação, estes 2
(`pre-compact-checkpoint`, `mcp-warmup-wait`) não são segurança
([`automate-security/`](../automate-security)) nem controle de recurso/orçamento
([`automate-resource-guards/`](../automate-resource-guards)) — são confiabilidade/continuidade de
sessão. Mecanismo, evento disparador e formato de configuração são todos diferentes dos guards de
bloqueio, por isso categoria e pasta próprias.

## Hooks incluídos

| Hook | Evento | O que faz |
|---|---|---|
| [`compact-checkpoint.sh`](hooks/scripts/compact-checkpoint.sh) | `PreCompact` (Claude Code) / `PostCompaction` (Devin CLI) | Se há mudanças não commitadas no repositório git do cwd, cria um commit `checkpoint: pre-compact auto-save (...)` (`--no-verify`). Recuperação: `git log --oneline -5`. |
| [`mcp-warmup-wait.sh`](hooks/scripts/mcp-warmup-wait.sh) | `SessionStart` (mesmo nome nas duas plataformas) | Se algum arquivo de config candidato declara `"mcpServers"`, espera `SESSION_LIFECYCLE_WARMUP_SECONDS` (default 3s) antes do primeiro turno — evita erro de "ferramenta indisponível" quando a sessão começa antes dos servidores MCP subirem (comum em sessões via trigger remoto/cron). |

Origem: portados de `yurukusa/cc-safe-setup` (`examples/pre-compact-checkpoint.sh` e
`examples/mcp-warmup-wait.sh`) — lógica de formatação/decisão extraída em funções puras testáveis
(`hooks/lib.sh`); I/O real (git, sleep, leitura de config) fica só nos entrypoints em
`hooks/scripts/`.

## `PreCompact` (Claude Code) vs `PostCompaction` (Devin CLI)

Confirmado via `docs.devin.ai/cli/extensibility/hooks/lifecycle-hooks`: o Devin CLI **não** expõe
um evento "antes" da compactação — só `PostCompaction` ("After context compaction succeeds"). O
Claude Code, ao contrário, expõe `PreCompact` ("fires right before context compression",
confirmado no comentário original do script do `cc-safe-setup`).

Isso poderia parecer uma incompatibilidade real, mas não é, pro propósito deste hook
especificamente: a compactação afeta só a memória CONVERSACIONAL do agente (o resumo que ele vê),
nunca o conteúdo dos arquivos em disco. Um `git add -A && git commit` captura o mesmo estado de
arquivos rodando um instante antes ou um instante depois da compactação — o "checkpoint" em si é
idêntico nos dois casos. Por isso `compact-checkpoint.sh` é o **mesmo script** registrado sob
`PreCompact` no Claude Code e sob `PostCompaction` no Devin CLI (ver `examples/{claude-settings,
devin-hooks}.json`) — só o nome do evento no arquivo de config muda, o script não precisa saber
qual dos dois disparou.

## Onde procurar `mcpServers`

O `cc-safe-setup` original só olhava `~/.claude/settings.json`. Como este hook também roda sob
Devin CLI, `mcp-warmup-wait.sh` confere uma lista maior de caminhos candidatos — globais e
por-projeto, das duas plataformas (`~/.claude/settings.json`, `~/.claude/settings.local.json`,
`~/.claude.json`, `~/.config/devin/config.json`, `$DEVIN_PROJECT_DIR/.devin/config.json` e
`.local.json`, e os equivalentes em `$PWD`) — conforme a seção "Configuration Locations" da
documentação oficial do Devin CLI. O primeiro arquivo que existir E declarar `"mcpServers"` já é
suficiente pra disparar a espera; nenhum erro se nenhum existir (sessão sem MCP configurado não
paga o custo do warmup).

## Instalar num repositório (Claude Code)

Copie `examples/claude-settings.json` para o `.claude/settings.json` do repositório (ou mescle):

```json
{
  "hooks": {
    "PreCompact": [
      { "hooks": [{ "type": "command", "command": "$HOME/development/tools/automate-session-lifecycle/hooks/scripts/compact-checkpoint.sh" }] }
    ],
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "$HOME/development/tools/automate-session-lifecycle/hooks/scripts/mcp-warmup-wait.sh" }] }
    ]
  }
}
```

## Instalar num repositório (Devin CLI)

Copie `examples/devin-hooks.json` para `.devin/hooks.v1.json` no repositório — note o evento
`PostCompaction` no lugar de `PreCompact` (ver seção acima):

```json
{
  "PostCompaction": [
    { "hooks": [{ "type": "command", "command": "$HOME/development/tools/automate-session-lifecycle/hooks/scripts/compact-checkpoint.sh" }] }
  ],
  "SessionStart": [
    { "hooks": [{ "type": "command", "command": "$HOME/development/tools/automate-session-lifecycle/hooks/scripts/mcp-warmup-wait.sh" }] }
  ]
}
```

## Configuração (`config.env`)

| Variável | Papel |
|---|---|
| `SESSION_LIFECYCLE_CHECKPOINT_ENABLED` | Liga/desliga o checkpoint automático (`true` por padrão) |
| `SESSION_LIFECYCLE_WARMUP_ENABLED` | Liga/desliga a espera de warmup do MCP (`true` por padrão) |
| `SESSION_LIFECYCLE_WARMUP_SECONDS` | Segundos de espera quando `mcpServers` está configurado (default `3`) |

## Estrutura

```
automate-session-lifecycle/
├── README.md
├── config.env
├── examples/
│   ├── claude-settings.json       ← PreCompact + SessionStart
│   └── devin-hooks.json           ← PostCompaction + SessionStart
└── hooks/
    ├── lib.sh
    ├── scripts/
    │   ├── compact-checkpoint.sh
    │   └── mcp-warmup-wait.sh
    └── tests/
        └── run-tests.sh
```

## Testar

```bash
bash hooks/tests/run-tests.sh
```
