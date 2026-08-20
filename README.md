# ai-lup-toolling

Ferramentas compartilhadas de automação para fluxos de desenvolvimento assistidos por agentes de IA
(Claude Code, Devin CLI, etc.). Cada subpasta é uma ferramenta independente, instalável em qualquer
repositório que queira reaproveitá-la.

## Ferramentas

- [`automate-review/`](./automate-review) — automação assíncrona de review de PR pós-push: detecta um
  `git push` numa branch `feature/*`, acompanha a CI em segundo plano e abre uma janela com o resultado,
  já invocando a skill de review quando a CI passa.
- [`automate-security/`](./automate-security) — guards `PreToolUse` de segurança: bloqueiam caça/
  exfiltração de credenciais e conexão direta com banco de dados de produção. Portados e adaptados de
  [`yurukusa/cc-safe-setup`](https://github.com/yurukusa/cc-safe-setup).
- [`automate-resource-guards/`](./automate-resource-guards) — guards `PreToolUse` de orçamento/recurso
  (hoje: limite de subagentes ativos em paralelo). Mesmo mecanismo de bloqueio dos guards de segurança,
  categoria própria porque o risco não é segurança.
- [`automate-session-lifecycle/`](./automate-session-lifecycle) — hooks de continuidade de sessão, sem
  bloqueio: checkpoint git automático antes/depois da compactação de contexto, espera de warmup do MCP
  no início da sessão.

Todas compatíveis com Claude Code e Devin CLI (ver o README de cada uma para o que está confirmado
via a documentação oficial de cada plataforma e o que ainda precisa de verificação manual).

Veja o README de cada ferramenta para instruções de instalação e configuração.
