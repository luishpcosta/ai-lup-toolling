# ai-lup-toolling

Ferramentas de automação para fluxos de desenvolvimento assistidos por agentes de IA (Claude Code,
Devin CLI). Cada subpasta é uma ferramenta independente, instalável em qualquer repositório.

## Ferramentas

| Ferramenta | O que faz | Padrão |
|---|---|---|
| [`automate-review/`](./automate-review) | Detecta `git push` numa branch `feature/*`, acompanha a CI em segundo plano e abre uma janela com o resultado, já invocando a skill de review quando a CI passa | **desligada** |
| [`automate-security/`](./automate-security) | Guards `PreToolUse` que bloqueiam caça/exfiltração de credencial e conexão direta com banco remoto. Portados de [`yurukusa/cc-safe-setup`](https://github.com/yurukusa/cc-safe-setup) | ligada |
| [`automate-resource-guards/`](./automate-resource-guards) | Guard `PreToolUse` de orçamento: limite de subagentes em paralelo. Mesmo mecanismo dos guards de segurança, categoria própria porque o risco não é segurança | ligada |
| [`automate-session-lifecycle/`](./automate-session-lifecycle) | Hooks sem bloqueio: checkpoint git na compactação de contexto, espera de warmup do MCP no início da sessão | ligada |

Todas compatíveis com Claude Code e Devin CLI — o README de cada uma separa o que está confirmado na
documentação oficial de cada plataforma do que ainda precisa de verificação manual.

## Instalar

```bash
./install.sh                                                     # interativo
./install.sh --tools=all --platform=both --scope=global --yes
./install.sh --tools=security --platform=claude --scope=repo --repo=/caminho/do/repo
./install.sh --dry-run                                           # simula, não escreve nada
./install.sh --help
```

Instala uma ou várias ferramentas de uma vez, para Claude Code e/ou Devin CLI, no escopo global
(`~`) ou de um repositório. O instalador:

- **mescla** no config existente em vez de sobrescrever — nada do que já estava lá é apagado, e a
  ordem dos hooks que você já tinha é preservada (hook roda na ordem do arquivo);
- **reescreve o caminho** dos hooks para este checkout, então o repositório pode ficar em qualquer
  lugar;
- faz **backup** (`.bak-<timestamp>`) antes de qualquer mudança e é **idempotente** — rodar de novo
  não duplica nem gera backup à toa;
- preserva as permissões do arquivo de destino.

Precisa de `jq` **ou** `python3`: mesclar JSON com segurança exige um parser de verdade.

Cada ferramenta tem configuração própria em `config.env` — veja o README dela.

## Testar

```bash
for d in automate-*/; do (cd "$d" && bash hooks/tests/run-tests.sh); done
(cd automate-review && python3 -m unittest hooks.tests.test_review_db)
```

Sem framework externo: bash puro nos hooks, `unittest` da stdlib no gate de revisões.
