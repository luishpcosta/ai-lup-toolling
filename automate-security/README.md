# automate-security

Guards `PreToolUse` de segurança: intercepta o comando antes de rodar e **bloqueia** (exit 2)
caça/exfiltração de credenciais e conexão direta com banco de dados de produção. Compatível com
Claude Code e Devin CLI.

Compartilhado por máquina — qualquer repo que registre o hook (abaixo) reaproveita os scripts.

## Guards

| Guard | Bloqueia |
|---|---|
| `credential-exfil-guard.sh` | `env\|grep secret`, busca de arquivo de credencial, leitura de chave SSH/`/etc/shadow`/credenciais de nuvem, busca em credencial de navegador, upload/pipe de credencial pra `curl`/`wget`, extração via keychain macOS, segredo pipado pra rede. Avisa (não bloqueia) em dump de ambiente sem filtro. |
| `db-connect-guard.sh` | `mysql`/`psql`/`mongo(sh)`/`redis-cli` com `-h`/`--host`, `prisma db push`/`migrate deploy`/`migrate reset`. Não bloqueia conexão local nem `prisma generate`. |

## Instalar (Claude Code)

Copie `examples/claude-settings.json` pro `.claude/settings.json` do repositório (ou mescle).

`SECURITY_GUARD_ENABLED=true` por padrão em `config.env` — já vem ligado.

## Instalar (Devin CLI)

Copie `examples/devin-hooks.json` pra `.devin/hooks.v1.json`.

## Compatibilidade Claude Code / Devin CLI

- Payload via stdin JSON, mesmo campo `tool_input.command` nas duas.
- Bloqueio por exit code 2 num hook `PreToolUse`, igual nas duas.
- Matcher: `"Bash"` no Claude Code, `"exec"` no Devin (filtra por NOME da ferramenta, não conteúdo
  — cada guard já decide sozinho se bloqueia, então não precisa de filtro extra).
- `jq` opcional — fallback bash/grep/sed puro em `hooks/lib.sh` quando ausente (Git Bash não vem
  com `jq` por padrão).
- `"PowerShell"` como ferramenta distinta no Devin: não confirmado. `examples/devin-hooks.json`
  registra só `"exec"`.

## Auditoria

Todo `BLOCKED`/`WARNING` é gravado em `data/audit.log` (por máquina, git-ignored — não é código).
Passagens sem bloqueio não são logadas.

```
[2026-08-19T14:32:01-03:00] guard=credential-exfil-guard decision=BLOCKED detail=acesso direto a credencial SSH | cmd=cat ~/.ssh/id_rsa
```

## Config (`config.env`)

| Variável | Papel |
|---|---|
| `SECURITY_GUARD_ENABLED` | Liga/desliga os dois guards (`true` por padrão) |

## Testar

```bash
bash hooks/tests/run-tests.sh

echo '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}' \
  | hooks/guards/credential-exfil-guard.sh; echo "exit=$?"   # BLOCKED / exit=2
```
