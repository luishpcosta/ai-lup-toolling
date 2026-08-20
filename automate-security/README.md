# automate-security

Guards de segurança `PreToolUse` para agentes de codificação (Claude Code, Devin CLI, ou outra
plataforma compatível): interceptam o comando **antes** de rodar e **bloqueiam** (não só avisam)
os casos de risco real — caça/exfiltração de credenciais e conexão direta com banco de dados de
produção.

Esta pasta é compartilhada por máquina, não por repositório: qualquer repo que registre os hooks
(ver abaixo) reaproveita os mesmos scripts.

**Origem**: os dois guards foram inspecionados e portados de
[`yurukusa/cc-safe-setup`](https://github.com/yurukusa/cc-safe-setup) (`examples/credential-exfil-guard.sh`
e `examples/db-connect-guard.sh`) — mesma lógica de detecção, reescrita em funções puras testáveis
(`hooks/lib.sh`) e sem dependência obrigatória de `jq` (fallback bash/grep/sed puro, mesmo padrão já
usado em [`automate-review/hooks/lib.sh`](../automate-review/hooks/lib.sh) deste repositório). Do
catálogo maior do `cc-safe-setup` (800+ exemplos), só esses dois foram trazidos por serem os únicos
genuinamente de **segurança** entre os 5 originalmente avaliados — os outros 3
(`subagent-budget-guard`, `pre-compact-checkpoint`, `mcp-warmup-wait`) são hooks operacionais/de
confiabilidade, não de segurança, e vivem em pastas próprias deste mesmo repositório (ver
[`../automate-resource-guards/`](../automate-resource-guards) e
[`../automate-session-lifecycle/`](../automate-session-lifecycle)).

## Guards incluídos

| Guard | Bloqueia |
|---|---|
| [`credential-exfil-guard.sh`](hooks/guards/credential-exfil-guard.sh) | `env\|grep secret`, `find` por arquivo de credencial, leitura direta de chave SSH/`/etc/shadow`/credenciais de nuvem (`~/.aws`, `~/.kube`, …), busca em armazém de credencial de navegador, upload/pipe de arquivo de credencial pra `curl`/`wget`, extração de token via keychain do macOS, segredo (keychain ou env var) pipado pra cliente de rede. Também **avisa** (sem bloquear) em dump de ambiente sem filtro e em `env \| grep <termo não-secreto>` (ainda vaza valores — #69053). |
| [`db-connect-guard.sh`](hooks/guards/db-connect-guard.sh) | `mysql`/`psql`/`mongo(sh)` com `-h`/`--host`, `redis-cli` com `-h`/`--host`, `prisma db push`/`migrate deploy`/`migrate reset`. NÃO bloqueia conexão local (sem `-h`) nem `prisma generate`. |

## Instalar num repositório (Claude Code)

Copie `examples/claude-settings.json` para o `.claude/settings.json` do repositório (ou mescle, se
o repositório já tiver outros hooks configurados):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "$HOME/development/tools/automate-security/hooks/guards/credential-exfil-guard.sh" }]
      },
      {
        "matcher": "Bash|PowerShell",
        "hooks": [{ "type": "command", "command": "$HOME/development/tools/automate-security/hooks/guards/db-connect-guard.sh" }]
      }
    ]
  }
}
```

`SECURITY_GUARD_ENABLED=true` por padrão em `config.env` (nesta pasta) — diferente do
`automate-review`, os guards já vêm **ligados**: são checagens de bloqueio rápidas, sem efeito
colateral em disco/rede, então o padrão seguro é "protegendo". Edite `config.env` para
`SECURITY_GUARD_ENABLED=false` se quiser desligar temporariamente numa máquina específica.

## Instalar num repositório (Devin CLI)

Copie `examples/devin-hooks.json` para `.devin/hooks.v1.json` no repositório (ou para
`.claude/settings.json` — a própria documentação do Devin CLI lista esse arquivo como uma
localização de config válida):

```json
{
  "PreToolUse": [
    {
      "matcher": "exec",
      "hooks": [
        { "type": "command", "command": "$HOME/development/tools/automate-security/hooks/guards/credential-exfil-guard.sh" },
        { "type": "command", "command": "$HOME/development/tools/automate-security/hooks/guards/db-connect-guard.sh" }
      ]
    }
  ]
}
```

## Compatibilidade Claude Code / Devin CLI

Confirmado via `docs.devin.ai/cli/extensibility/hooks/{overview,lifecycle-hooks}`:

- **Payload do evento**: os dois entregam o evento via **stdin JSON** com `tool_name` e
  `tool_input.command` — os guards leem exatamente esses dois campos, nenhum código específico de
  plataforma.
- **Bloqueio**: os dois usam o **mesmo mecanismo** — exit code `2` num hook `PreToolUse` nega a
  ação (`0` permite). O Devin também aceita `{"decision":"block","reason":"..."}` em stdout como
  alternativa, mas os guards aqui usam só o exit code, que funciona nos dois.
- **Matcher**: no Claude Code o matcher `"Bash"` filtra pelo NOME da ferramenta; no Devin, o
  matcher é regex sobre `tool_name` também (ex.: `"exec"`, o nome da ferramenta de shell no Devin
  CLI) — nenhuma das duas plataformas exige que o script confira o conteúdo do comando pra decidir
  se o evento é relevante, então (diferente do `automate-review`) os guards aqui não precisam de
  filtro de conteúdo extra: cada guard já examina o `command` para decidir se bloqueia, e simplesmente
  não bloqueia (`exit 0`) quando o comando não bate em nenhum padrão — dispara em todo `Bash`/`exec`,
  mas só age nos casos de risco.
- **`jq` opcional**: `hooks/lib.sh` usa `jq` quando disponível e cai pra um parser
  bash/grep/sed puro (`extract_json_string_field`) quando não está — importa porque `jq` não vem
  por padrão no Git for Windows/MSYS2. Diferente do `cc-safe-setup` original (que fica **mudo e
  sem proteção nenhuma** sem `jq`, só avisando uma vez), esta versão continua protegendo mesmo sem
  `jq` no PATH.
- **`PowerShell` no Devin**: `db-connect-guard.sh` era `TRIGGER: PreToolUse MATCHER: "Bash|PowerShell"`
  no `cc-safe-setup` original — não há confirmação, na documentação pública consultada, de que o
  Devin CLI tenha uma ferramenta de nome `"PowerShell"` distinta de `"exec"`; `examples/devin-hooks.json`
  registra só `"exec"`. Se o Devin rodar PowerShell através da mesma ferramenta `exec`, já está
  coberto; se tiver uma ferramenta própria, registre o guard nela também.

## Configuração (`config.env`)

| Variável | Papel |
|---|---|
| `SECURITY_GUARD_ENABLED` | Liga/desliga os dois guards (`true` por padrão) |

## Estrutura

```
automate-security/
├── README.md                          ← este arquivo
├── config.env                         ← configuração, editável
├── examples/
│   ├── claude-settings.json           ← exemplo de hook para copiar num repositório (Claude Code)
│   └── devin-hooks.json               ← exemplo de hook para copiar num repositório (Devin CLI)
└── hooks/
    ├── lib.sh                         ← funções puras (testáveis) + leitura de stdin + config.env
    ├── guards/
    │   ├── credential-exfil-guard.sh  ← entrypoint do guard de credenciais
    │   └── db-connect-guard.sh        ← entrypoint do guard de banco de dados
    └── tests/
        └── run-tests.sh               ← suíte de testes de lib.sh (bash puro, sem framework)
```

## Testar

```bash
bash hooks/tests/run-tests.sh

# smoke test manual de um guard (simula o payload do hook via stdin)
echo '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}' \
  | hooks/guards/credential-exfil-guard.sh; echo "exit=$?"   # esperado: BLOCKED / exit=2
```
