# automate-review

Automação assíncrona de review de PR pós-push: um hook de plataforma agêntica (Claude Code, Devin
CLI, ou outra compatível), num repositório que usa esta pasta, detecta um `git push` numa branch
`feature/*`, acompanha a CI em segundo plano, e abre uma janela com o resultado — com a skill
`review-pr` (em `.claude/skills/review-pr/`) já invocada quando a CI passa.

Esta pasta é compartilhada por máquina, não por repositório: qualquer repo que registre o hook
(ver abaixo) reaproveita os mesmos scripts e a mesma skill.

## Instalar num repositório (Claude Code)

1. Copie `examples/claude-settings.json` para o `.claude/settings.json` do repositório (ou mescle,
   se o repositório já tiver outros hooks configurados):

   ```json
   {
     "hooks": {
       "PostToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             {
               "type": "command",
               "if": "Bash(git push *)",
               "command": "$HOME/development/tools/automate-review/hooks/post-push-review.sh",
               "async": true,
               "timeout": 15
             }
           ]
         }
       ]
     }
   }
   ```

2. Confirme que a CI do repositório expõe check-runs via a API do GitHub
   (`gh api repos/{owner}/{repo}/commits/{sha}/check-runs`) — qualquer workflow do GitHub Actions já
   satisfaz isso.
3. Edite `config.env` (nesta pasta) e mude `AGENT_PR_REVIEW_ENABLED` para `true` quando quiser ligar a
   automação nesta máquina. Fica desligada por padrão.

## Compatibilidade com outras plataformas agênticas (ex.: Devin CLI)

`post-push-review.sh` (o entrypoint do hook) não assume nada específico do Claude Code — ele lê o
payload do evento via stdin (JSON com `tool_input.command`/`cwd`, formato que Claude Code e Devin CLI
compartilham) e confere ele mesmo se o comando é um `git push`, em vez de depender só do filtro da
plataforma. Isso importa porque nem toda plataforma filtra hooks pelo **conteúdo** do comando: o
`"if": "Bash(git push *)"` é um recurso específico do Claude Code — o matcher do Devin CLI, por
exemplo, só filtra pelo **nome da ferramenta** (`"exec"`), não pelo texto do comando. Sem essa checagem
extra dentro do próprio script, um hook registrado no Devin sem filtro de conteúdo dispararia o script
a cada comando de shell, não só em pushes — daí o script conferir isso sozinho.

Essa checagem extra (e a leitura de `cwd`) usa `jq` quando disponível, com fallback automático em
bash/grep/sed puro quando não está — importa porque `jq` **não vem por padrão no Git for
Windows/MSYS2**, diferente deste host (WSL2/Ubuntu, onde já vem instalado). Testado sem `jq` no PATH:
o script continua funcionando, incluindo a defesa contra comandos que não são `git push`.

Para o Devin CLI, copie `examples/devin-hooks.json` para `.devin/hooks.v1.json` no repositório (ou
para `.claude/settings.json` — a própria documentação do Devin CLI lista esse arquivo como uma
localização de config válida):

```json
{
  "PostToolUse": [
    {
      "matcher": "exec",
      "hooks": [
        {
          "type": "command",
          "command": "$HOME/development/tools/automate-review/hooks/post-push-review.sh",
          "timeout": 15
        }
      ]
    }
  ]
}
```

**O que não está confirmado** (a documentação pública do Devin CLI consultada — `/cli/extensibility/hooks/overview`
e `/cli/extensibility/hooks/lifecycle-hooks` — não cobre isso): se existe um campo `async` equivalente
ao do Claude Code; pelo contrário, os exemplos da doc tratam hooks como síncronos/bloqueantes. **Isso
não é um problema** — `post-push-review.sh` já faz seu próprio `nohup ... & disown` internamente, então
o poller roda independente de a plataforma ter ou não suporte nativo a hooks assíncronos. Provado sob a
restrição específica de um hook síncrono: `post-push-review.sh` retorna em ~74ms mesmo com um `timeout`
curto simulando o do Devin, e o processo em background resultante tem sessão/grupo de processo próprios
(`setsid`) — sobrevive mesmo que o processo que disparou o hook seja encerrado logo depois.

A sintaxe de linha de comando para invocar o Devin CLI com um prompt está confirmada em
[`docs.devin.ai/pt-BR/cli/essential-commands`](https://docs.devin.ai/pt-BR/cli/essential-commands):
`devin -p "prompt"` roda em modo single-turn (imprime a resposta e sai). Não há, na documentação
pública consultada, um subcomando dedicado de review de PR — o Devin faz a revisão a partir do prompt
livre, igual o exemplo abaixo. O exemplo de `AGENT_PR_REVIEW_PLATFORM_CMD` para Devin (ver
`config.env`) usa essa sintaxe confirmada.

## Configuração (`config.env`)

Todas as variáveis da automação ficam em [`config.env`](./config.env), editável diretamente — não
precisa exportar nada no shell. Se uma variável já estiver exportada no ambiente de quem chamou o
script, ela vence sobre o arquivo (útil para um override pontual de teste).

| Variável | Papel |
|---|---|
| `AGENT_PR_REVIEW_ENABLED` | Liga/desliga a automação (`false` por padrão) |
| `AGENT_PR_REVIEW_POLL_INTERVAL_SEC` | Intervalo entre tentativas de polling da CI |
| `AGENT_PR_REVIEW_POLL_MAX_ATTEMPTS` | Tentativas antes de declarar estado indeterminado |
| `AGENT_PR_REVIEW_SKILL_PATH` | Pasta onde a janela final abre (esta pasta, por padrão) |
| `AGENT_PR_REVIEW_TERMINAL_CMD` | Array com o programa + flags do terminal a abrir (ver abaixo) |
| `AGENT_PR_REVIEW_PLATFORM_CMD` | Array com o programa + prompt da plataforma agêntica a invocar (ver abaixo) |

### Trocar o terminal (`AGENT_PR_REVIEW_TERMINAL_CMD`)

Por padrão a automação abre o **Git Bash nativo do Windows** — é o único mecanismo testado e
comprovado funcionando neste projeto.

`AGENT_PR_REVIEW_TERMINAL_CMD` é um **array bash**, não uma string — cada elemento vira um argv
separado, então caminhos com espaço (`C:\Program Files\...`) funcionam sem precisar escapar nada:

```bash
# default
AGENT_PR_REVIEW_TERMINAL_CMD=('C:\Program Files\Git\usr\bin\bash.exe' -i -l)
```

O script final gerado pela automação é sempre passado como **último argumento posicional** do
comando (nunca via `-c "<string inline>"` — essa abordagem se mostrou frágil na prática). Isso
significa que qualquer programa configurado aqui precisa:

- aceitar um caminho de arquivo de script como argumento e executá-lo; e
- ser capaz de interpretar **bash** (o script gerado é sempre um script bash — trocar o terminal não
  troca a linguagem do script).

Para usar outro shell compatível, edite a linha em `config.env`. Isso não foi testado neste projeto
além do Git Bash nativo — ajuste por sua conta.

**O que `AGENT_PR_REVIEW_TERMINAL_CMD` NÃO troca:** só o *programa que abre a janela e executa o
script* é configurável — o conteúdo do script em si (`cd`, `cat`, `echo`, a linha que invoca a
plataforma agêntica) é **sempre gerado em bash**, não importa o que você colocar aqui. Configurar
`AGENT_PR_REVIEW_TERMINAL_CMD` para PowerShell ou `cmd.exe` puro **quebra tudo**: nenhum dos dois
interpreta sintaxe bash, então a janela abriria só pra mostrar um erro de sintaxe.

Duas alternativas reais se você precisa de um terminal que não seja compatível com bash:

1. **Usar o terminal só como "casca", delegando a execução de volta pro bash** — ex.:
   `AGENT_PR_REVIEW_TERMINAL_CMD=(powershell.exe -Command)`, e o `open-terminal.sh` continuaria
   passando o script como argumento — mas isso não funciona com o design atual (`powershell.exe
   -Command "<script>.sh"` não executa um script bash sozinho; precisaria de mais uma camada,
   tipo `-Command "bash '<script>'"`, o que exige mudar como o argumento final é montado). É a opção
   de menor esforço se algum dia for necessária, mas **não implementada nem testada aqui** — ainda
   depende de existir um bash em algum lugar do host (Git Bash ou WSL).
2. **Gerar o script na linguagem nativa do terminal escolhido** (`.ps1` para PowerShell, `.bat` para
   `cmd.exe`) — a alternativa "correta" se o host realmente não tiver bash disponível em lugar nenhum.
   Exige generalizar a geração do script em `poll-and-review.sh` (hoje hardcoded em bash) por
   template, uma mudança bem maior — não implementada; avalie se vale a pena antes de pedir.

Na prática, como todo host Windows que já roda Claude Code ou Devin CLI tipicamente já tem Git Bash
ou WSL disponível (é dependência comum dessas ferramentas), a limitação a bash não chegou a ser um
problema real até agora.

### Trocar a plataforma agêntica (`AGENT_PR_REVIEW_PLATFORM_CMD`)

Mesma ideia do terminal, agora para qual plataforma/skill é invocada quando a CI passa e a PR é
encontrada. Também um **array bash**; cada elemento pode conter o placeholder literal `{pr_url}`,
substituído pela URL real da PR na hora de montar o comando final:

```bash
# default: Claude Code + skill review-pr
AGENT_PR_REVIEW_PLATFORM_CMD=(claude '/review-pr faça revisão da pr aberta em {pr_url} e submeta os comentarios e relatório da validação')

# exemplo para Devin CLI — "devin -p" confirmado em docs.devin.ai/pt-BR/cli/essential-commands
# (modo single-turn: imprime a resposta e sai). Não há subcomando dedicado de review documentado.
# AGENT_PR_REVIEW_PLATFORM_CMD=(devin -p "revise a PR aberta em {pr_url} e submeta os comentários e relatório da validação")
```

A linha final é sempre prefixada com `MSYS_NO_PATHCONV=1` (evita o Git Bash converter argumentos que
começam com `/`, como `/review-pr`, num caminho Windows — bug real encontrado neste projeto) e cada
elemento é escapado com segurança (`printf '%q'`) antes de virar texto no script gerado, então prompts
com espaço, aspas ou caracteres especiais funcionam sem escaping manual no `config.env`.

## Estrutura

```
automate-review/
├── README.md                    ← este arquivo
├── config.env                   ← configuração, editável
├── examples/
│   ├── claude-settings.json     ← exemplo de hook para copiar num repositório (Claude Code)
│   └── devin-hooks.json         ← exemplo de hook para copiar num repositório (Devin CLI)
├── .claude/skills/review-pr/    ← a skill de revisão (convenção de descoberta do Claude Code)
└── hooks/
    ├── lib.sh                   ← funções puras (testáveis) + carregamento do config.env
    ├── post-push-review.sh      ← entrypoint do hook (gate rápido)
    ├── poll-and-review.sh       ← poller pesado, disparado em background
    ├── open-terminal.sh         ← abre a janela final
    └── tests/run-tests.sh       ← suíte de testes (bash puro, sem framework)
```

## Testar

```bash
bash hooks/tests/run-tests.sh
```
