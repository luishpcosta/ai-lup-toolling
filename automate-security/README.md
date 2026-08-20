# automate-security

Guards `PreToolUse` que interceptam o comando **antes** de ele rodar e bloqueiam (exit 2) caça ou
exfiltração de credencial e conexão direta com banco de dados remoto. Compatíveis com Claude Code e
Devin CLI.

A pasta é compartilhada por máquina: qualquer repositório que registre o hook usa estes mesmos
scripts. Ligados por padrão (`SECURITY_GUARD_ENABLED=true`) — são checagens rápidas, sem efeito
colateral em disco ou rede.

## Guards

| Guard | Bloqueia | Só avisa |
|---|---|---|
| `credential-exfil-guard.sh` | `env\|grep <termo secreto>`, busca de arquivo de credencial, leitura de chave SSH / `/etc/shadow` / credencial de nuvem, busca em perfil de navegador, upload ou pipe de credencial para `curl`/`wget`, extração via keychain do macOS, variável secreta pipada para cliente de rede | `env\|grep <qualquer termo>` (vaza valor mesmo sem termo óbvio), `env`/`printenv` sem filtro |
| `db-connect-guard.sh` | `mysql`/`psql`/`mongo(sh)`/`redis-cli` com `-h`/`--host`, `prisma db push`, `prisma migrate deploy`, `prisma migrate reset` | — |

Aviso não interrompe a avaliação: um comando que avisa e depois faz algo bloqueável continua sendo
bloqueado.

## Instalar

```bash
../install.sh --tools=security --platform=claude --scope=repo --repo=.   # ou --scope=global
../install.sh --tools=security --platform=devin  --scope=repo --repo=.
```

O instalador mescla no config existente sem apagar nada e reescreve o caminho dos hooks para este
checkout. Manualmente: `examples/claude-settings.json` → `.claude/settings.json`;
`examples/devin-hooks.json` → `.devin/hooks.v1.json` (nesse caso ajuste o caminho à mão, os exemplos
assumem `$HOME/development/tools/`).

## Compatibilidade Claude Code / Devin CLI

- Payload por stdin em JSON, mesmo campo `tool_input.command` nas duas plataformas.
- Bloqueio por exit code 2 num hook `PreToolUse`, igual nas duas.
- Matcher: `"Bash"` no Claude Code, `"exec"` no Devin. Os dois filtram por nome de ferramenta; cada
  guard decide sozinho se bloqueia, então não precisa de filtro por conteúdo.
- Leitura do comando: `jq` → `python3` → regex. Só a última camada é aproximada, e mesmo ela trata
  `\"`/`\\` — o Git for Windows não traz `jq`, e sem esse cuidado o comando era truncado na primeira
  aspa escapada e o guard deixava passar.
- `"PowerShell"` como ferramenta separada no Devin: não confirmado. `examples/devin-hooks.json`
  registra só `"exec"`.

## Config (`config.env`)

| Variável | Papel |
|---|---|
| `SECURITY_GUARD_ENABLED` | Liga/desliga os dois guards (`true` por padrão) |
| `SECURITY_GUARD_TRACE_LOG_PATH` | Onde gravar o trace log (default: `data/trace.log` nesta pasta) |

Variável já exportada no ambiente vence sobre o arquivo.

## Limites conhecidos

- A detecção é por padrão de texto do comando, não sandbox: comando ofuscado (base64, variável
  intermediária, script externo) não é reconhecido. Isso reduz erro operacional, não contém um
  agente adversarial.
- `is_bare_env_dump` e o aviso de `env|grep` são ruidosos por escolha: preferem falso positivo a
  vazamento silencioso.

## Trace log (auditoria)

Todo `BLOCKED`/`WARNING` vai para `data/trace.log` — um evento por linha (comando multi-linha é
achatado e cortado em 500 caracteres), por máquina, fora do controle de versão. Comando que passa
sem bater em nada não é logado.

```
[2026-08-19T14:32:01-03:00] guard=credential-exfil-guard decision=BLOCKED detail=acesso direto a credencial SSH | cmd=cat ~/.ssh/id_rsa
```

## Testar

```bash
bash hooks/tests/run-tests.sh

echo '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}' \
  | hooks/guards/credential-exfil-guard.sh; echo "exit=$?"   # BLOCKED / exit=2
```
