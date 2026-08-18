# ai-lup-toolling

Ferramentas compartilhadas de automação para fluxos de desenvolvimento assistidos por agentes de IA
(Claude Code, Devin CLI, etc.). Cada subpasta é uma ferramenta independente, instalável em qualquer
repositório que queira reaproveitá-la.

## Ferramentas

- [`automate-review/`](./automate-review) — automação assíncrona de review de PR pós-push: detecta um
  `git push` numa branch `feature/*`, acompanha a CI em segundo plano e abre uma janela com o resultado,
  já invocando a skill de review quando a CI passa.

Veja o README de cada ferramenta para instruções de instalação e configuração.
