# automate-session-lifecycle

Hooks de continuidade de sessão. **Não bloqueiam nada** — só agem em eventos de ciclo de vida
(compactação de contexto, início de sessão), sempre com exit 0. Categoria separada de
[`automate-security/`](../automate-security) e
[`automate-resource-guards/`](../automate-resource-guards), que são guards de bloqueio. Compatíveis
com Claude Code e Devin CLI.

## Hooks

| Hook | Evento | Faz |
|---|---|---|
| `compact-checkpoint.sh` | `PreCompact` (Claude Code) / `PostCompaction` (Devin CLI) | Havendo mudança não commitada, cria `git commit -m "checkpoint: pre-compact auto-save (...)"`. Recuperação: `git log --oneline -5`. |
| `mcp-warmup-wait.sh` | `SessionStart` (mesmo nome nas duas) | Se algum config candidato declara ao menos um servidor em `"mcpServers"`, espera `SESSION_LIFECYCLE_WARMUP_SECONDS` (default 3s) antes do 1º turno. |

## Instalar

```bash
../install.sh --tools=session-lifecycle --platform=claude --scope=global
```

Manualmente: `examples/claude-settings.json` → `.claude/settings.json` (`PreCompact` +
`SessionStart`), ou `examples/devin-hooks.json` → `.devin/hooks.v1.json` (`PostCompaction` +
`SessionStart`).

## O que o checkpoint commita — leia antes de ligar

`compact-checkpoint.sh` roda `git add -A` seguido de `git commit --no-verify` na branch atual.
Consequências:

- **Commita tudo que não está no `.gitignore`**, inclusive arquivo não rastreado que você ainda não
  pretendia versionar.
- **Desfaz o seu staging seletivo**: o que estava fora do índice entra no commit.
- Pula os hooks de commit do repositório (`--no-verify`), então lint/teste de pré-commit não rodam.

Ele **não** roda quando há `merge`, `rebase`, `cherry-pick`, `revert` ou `bisect` em andamento —
commitar ali concluiria a operação errada, marcando conflito como resolvido. Nesse caso o hook sai
sem tocar em nada e registra `SKIPPED`.

Se o commit falhar (índice travado, sem identidade git configurada, etc.), a sessão recebe uma
mensagem dizendo que o checkpoint **não** foi criado e o erro real vai para o trace log como
`FAILED`.

Para desligar só o checkpoint, mantendo o warmup: `SESSION_LIFECYCLE_CHECKPOINT_ENABLED=false`.

## `PreCompact` vs `PostCompaction`

O Devin CLI não tem evento antes da compactação, só `PostCompaction`. Não é problema: a compactação
só afeta a memória conversacional, nunca o disco, então um `git commit` captura o mesmo estado de
arquivos antes ou depois dela. O **mesmo script** roda sob `PreCompact` no Claude Code e
`PostCompaction` no Devin — muda só o nome do evento no config.

## Onde `mcp-warmup-wait` procura `mcpServers`

Percorre uma lista de candidatos, global e por projeto, das duas plataformas
(`~/.claude/settings.json`, `~/.claude.json`, `~/.config/devin/config.json`,
`$DEVIN_PROJECT_DIR/.devin/config.json`, equivalentes em `$PWD`). O primeiro que existir e declarar
**ao menos um** servidor já basta — `"mcpServers": {}` vazio não conta, para não custar 3s em toda
sessão. Sem MCP configurado, não espera nada.

## Config (`config.env`)

| Variável | Papel |
|---|---|
| `SESSION_LIFECYCLE_CHECKPOINT_ENABLED` | Liga/desliga o checkpoint (`true` por padrão) |
| `SESSION_LIFECYCLE_WARMUP_ENABLED` | Liga/desliga o warmup (`true` por padrão) |
| `SESSION_LIFECYCLE_WARMUP_SECONDS` | Segundos de espera (default `3`) |
| `SESSION_LIFECYCLE_TRACE_LOG_PATH` | Onde gravar o trace log (default: `data/trace.log` nesta pasta) |

Variável já exportada no ambiente vence sobre o arquivo.

## Trace log (auditoria)

Toda ação real (`ACTION`), pulo (`SKIPPED`) e falha (`FAILED`) vai para `data/trace.log`, um evento
por linha, por máquina, fora do controle de versão — além do próprio `git log`, que já é a trilha do
checkpoint.

## Testar

```bash
bash hooks/tests/run-tests.sh
```
