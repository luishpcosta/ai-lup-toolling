# Guia de Publicação de Revisões com gh CLI

## Pré-requisitos

Verifique se a CLI `gh` está instalada antes de publicar qualquer revisão:

```bash
gh --version
```

Se não estiver instalada: pare, informe o usuário para instalar em https://cli.github.com/ (`brew install gh` no macOS, `winget install GitHub.cli` no Windows, ver o site para Linux) e depois autenticar com `gh auth login`. Não continue até que `gh --version` funcione.

## Regra Central

Sempre use o padrão de **revisão pendente** — nunca publique comentário a comentário, mesmo para um único comentário. Só envie a revisão depois de mostrar ao usuário o conteúdo exato (arquivo/linha, texto de cada comentário, tipo de evento, mensagem geral) e obter aprovação explícita via AskUserQuestion.

## Fluxo Técnico

**Passo 1 — criar a revisão pendente** (sem o campo `event`):

```bash
gh api repos/:owner/:repo/pulls/<NUMERO_DO_PR>/reviews \
  -X POST \
  -f commit_id="<SHA_DO_COMMIT>" \
  -f 'comments[][path]=caminho/do/arquivo.ts' \
  -F 'comments[][line]=<NUMERO_DA_LINHA>' \
  -f 'comments[][side]=RIGHT' \
  -f 'comments[][body]=Texto do comentário

```suggestion
// código sugerido aqui
```

Explicação adicional...' \
  --jq '{id, state}'
# Retorna: {"id": <ID_DA_REVISAO>, "state": "PENDING"}
```

Para mais de um comentário, repita o grupo `-f 'comments[][path]=...' -F 'comments[][line]=...' -f 'comments[][side]=...' -f 'comments[][body]=...'` dentro da mesma chamada, um grupo por comentário.

**Passo 2 — enviar a revisão pendente**, só depois da aprovação:

```bash
gh api repos/:owner/:repo/pulls/<NUMERO_DO_PR>/reviews/<ID_DA_REVISAO>/events \
  -X POST \
  -f event="REQUEST_CHANGES" \
  -f body="Mensagem geral da revisão"
```

## Tipos de Evento

| Tipo de Evento | Quando Usar | Severidade equivalente nesta skill |
|------------|-------------|------------|
| `APPROVE` | Sugestões não bloqueantes, PR pronto para merge | Só `[nit]` / `[sugestão]` |
| `REQUEST_CHANGES` | Existe pelo menos um problema bloqueante | Algum `[bloqueante]` |
| `COMMENT` | Feedback neutro, sem exigir mudança | Só `[importante]` / `[aprendizado]` |

## Referência Rápida

### Obtendo os pré-requisitos

```bash
gh pr view <NUMERO_DO_PR> --json commits --jq '.commits[-1].oid'   # SHA do commit
gh repo view --json owner,name                                      # owner/repo (geralmente automático)
```

### Parâmetros

- `commit_id`: SHA do commit mais recente do PR
- `comments[][path]`: caminho do arquivo relativo à raiz do repositório
- `comments[][line]`: número da linha final (use `-F`, é numérico)
- `comments[][side]`: `RIGHT` para linhas adicionadas/modificadas, `LEFT` para linhas removidas
- `comments[][start_line]` (opcional): para sugestões em múltiplas linhas (use `-F`)
- `comments[][body]`: texto do comentário, com bloco ```suggestion opcional
- `event` (opcional no passo 1): omita para deixar `PENDING`; no passo 2 use `COMMENT`/`APPROVE`/`REQUEST_CHANGES`

### Regras de Sintaxe

**Faça:**
- Aspas simples em volta de parâmetros com `[]`: `'comments[][path]'`
- `-f` para valores de string, `-F` para valores numéricos
- Crases triplas com o identificador `suggestion` para sugestões de código

**Não faça:**
- Aspas duplas em volta de parâmetros `comments[][]`
- Confundir as flags `-f` e `-F`
- Publicar sem antes obter o SHA do commit (`commit_id`)

## Formato de Sugestões de Código

```bash
-f 'comments[][body]=Seu comentário explicando o problema

```suggestion
// O código sugerido que vai substituir a(s) linha(s) indicada(s)
const corrigido = "assim";
```

Contexto ou explicação adicional após a sugestão.'
```

Sugestões de código substituem a linha inteira ou o intervalo de linhas indicado — garanta que o código sugerido esteja completo e correto.

### Caso especial: sugestões com blocos de código aninhados

Ao sugerir mudanças em arquivos Markdown que já contêm crases triplas, use 4 crases ou tils para evitar conflito:

`````markdown
````suggestion
```javascript
const example = "value";
```
````
`````

Ou use tils:

```markdown
~~~suggestion
```javascript
const example = "value";
```
~~~
```

## Erros Comuns

| Erro | Correção |
|---------|-----|
| Esquecer as aspas simples em volta de `comments[][]` | Sempre entre aspas: `'comments[][path]'`, não `comments[][path]` |
| Confundir `-f` e `-F` | `-f` para texto, `-F` para números (`line`, `start_line`) |
| Não obter o SHA do commit antes | Rode `gh pr view <NUMERO> --json commits --jq '.commits[-1].oid'` primeiro |
| Usar o tipo de evento errado | Algum `[bloqueante]` → `REQUEST_CHANGES`; só nits/sugestões → `APPROVE`; dúvida/neutro → `COMMENT` |
