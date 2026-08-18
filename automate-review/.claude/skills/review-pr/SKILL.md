---
name: review-pr
description: |
  Fornece orientação completa de revisão de código para Angular 17+, Go, TypeScript, Python, Java e C#/.NET: encontra bugs, avalia arquitetura/performance/segurança e dá feedback construtivo priorizado por severidade.
  Use sempre que o usuário pedir para revisar, comentar ou dar uma olhada em um PR, diff ou mudança de código — mesmo sem dizer "code review" (ex.: "o que você acha desse PR", "tem algum problema nesse diff"). Cobre também publicar a revisão no GitHub via gh CLI (revisão pendente, sugestões de código), então acione também ao pedir para comentar, aprovar ou solicitar mudanças em um PR.
  Use quando: revisar PR, revisão de código, estabelecer padrões de revisão, mentorar desenvolvedores, revisão de arquitetura, auditoria de segurança, encontrar bugs, dar feedback sobre código, publicar revisão no GitHub, criar revisão pendente com gh CLI.
metadata:
  language: multiple
  tags: [meta, code-review, code-quality, pr-review, security-audit, architecture-review]
---

# Skill de Revisão de Código

Transforma revisões de código de um controle de acesso burocrático em compartilhamento de conhecimento, por meio de feedback construtivo, análise sistemática e melhoria colaborativa.

## Quando Usar Esta Skill

- Revisar pull requests e mudanças de código
- Estabelecer padrões de revisão de código para equipes
- Mentorar desenvolvedores juniores por meio de revisões
- Conduzir revisões de arquitetura
- Criar checklists e diretrizes de revisão
- Melhorar a colaboração da equipe
- Reduzir o tempo de ciclo da revisão de código
- Manter padrões de qualidade de código

## Princípios Fundamentais

### 1. A Mentalidade de Revisão

**Objetivos da Revisão de Código:**
- Encontrar bugs e casos extremos
- Garantir a manutenibilidade do código
- Compartilhar conhecimento entre a equipe
- Reforçar padrões de codificação
- Melhorar o design e a arquitetura
- Construir a cultura da equipe

**O Que Não São Objetivos:**
- Exibir conhecimento
- Fazer micro-correções de formatação (use linters)
- Bloquear o progresso sem necessidade
- Reescrever de acordo com sua preferência pessoal

### 2. Feedback Eficaz

**Um Bom Feedback é:**
- Específico e acionável
- Educativo, não acusatório
- Focado no código, não na pessoa
- Equilibrado (também elogie o que está bom)
- Priorizado (crítico vs. desejável)

```markdown
Ruim: "Isso está errado."
Bom: "Isso pode causar uma condição de corrida quando vários usuários
     acessam simultaneamente. Considere usar um mutex aqui."

Ruim: "Por que você não usou o padrão X?"
Bom: "Você já considerou o padrão Repository? Isso facilitaria
     os testes. Aqui está um exemplo: [link]"

Ruim: "Renomeie esta variável."
Bom: "[nit] Considere `userCount` em vez de `uc` para
     maior clareza. Não é bloqueante se preferir manter assim."
```

### 3. Escopo da Revisão

**O Que Revisar:**
- Corretude da lógica e casos extremos
- Vulnerabilidades de segurança
- Implicações de performance
- Cobertura e qualidade dos testes
- Tratamento de erros
- Documentação e comentários
- Design de API e nomenclatura
- Adequação arquitetural

**O Que Não Revisar Manualmente:**
- Formatação de código (use Prettier, Black, etc.)
- Organização de imports
- Violações de linting
- Erros de digitação simples

## Processo de Revisão

### Fase 1: Coleta de Contexto (2-3 minutos)

Antes de mergulhar no código, entenda:
1. Leia a descrição do PR e a issue vinculada
2. Verifique o tamanho do PR (>400 linhas? Peça para dividir)
3. Verifique o status do CI/CD (os testes estão passando?)
4. Entenda o requisito de negócio
5. Anote quaisquer decisões arquiteturais relevantes

> Para diffs grandes, passe o diff por [`scripts/analisador-pr.py`](scripts/analisador-pr.py) (`git diff main...HEAD | python scripts/analisador-pr.py`) para triar a complexidade e obter uma sugestão de abordagem de revisão antes de ler o código.

### Fase 2: Revisão de Alto Nível (5-10 minutos)

1. **Arquitetura e Design** - A solução é adequada ao problema?
   - Para mudanças significativas, consulte o [Guia de Revisão de Arquitetura](references/guia-revisao-arquitetura.md)
   - Verifique: princípios SOLID, acoplamento/coesão, anti-padrões
2. **Avaliação de Performance** - Há preocupações de performance?
   - Para código crítico em termos de performance, consulte o [Guia de Revisão de Performance](references/guia-revisao-performance.md)
   - Verifique: complexidade de algoritmo, consultas N+1, uso de memória
3. **Organização de Arquivos** - Os novos arquivos estão nos lugares certos?
4. **Estratégia de Testes** - Existem testes cobrindo casos extremos?

### Fase 3: Revisão Linha a Linha (10-20 minutos)

Para cada arquivo, verifique:
- **Lógica e Corretude** - Casos extremos, erros off-by-one, verificações de null, condições de corrida
- **Segurança** - Validação de entrada, riscos de injeção, XSS, dados sensíveis
- **Performance** - Consultas N+1, loops desnecessários, vazamentos de memória
- **Manutenibilidade** - Nomes claros, responsabilidade única, comentários
- **Reuso** - Antes de aceitar código novo, procure utilitários/helpers existentes que poderiam substituí-lo. Verifique arquivos adjacentes e módulos compartilhados em busca de padrões semelhantes. Veja o [Guia de Qualidade Universal](references/qualidade-codigo-universal.md) para anti-padrões como excesso de parâmetros (parameter sprawl), abstrações com vazamento (leaky abstractions), condicionais aninhados, código com tipagem por string (stringly-typed), TOCTOU e atualizações sem efeito (no-op updates).

### Fase 4: Resumo e Decisão (2-3 minutos)

1. Resuma as principais preocupações
2. Destaque o que você gostou
3. Tome uma decisão clara:
   - Aprovar
   - Comentar (sugestões menores)
   - Solicitar Mudanças (precisa ser resolvido)
4. Ofereça-se para fazer pair review se for complexo

### Fase 5: Publicar no GitHub (se solicitado)

Se o usuário pedir para publicar a revisão no GitHub, use a CLI `gh` com o padrão de revisão pendente (nunca comentário a comentário) e só envie depois de aprovação explícita do usuário. Veja o [Guia de Publicação com gh CLI](references/guia-gh-cli.md) para o passo a passo completo.

## Técnicas de Revisão

### Técnica 1: O Método do Checklist

Use checklists para revisões consistentes. Veja o [Guia de Revisão de Segurança](references/guia-revisao-seguranca.md) para um checklist de segurança completo.

### Técnica 2: A Abordagem por Perguntas

Em vez de apontar problemas, faça perguntas:

```markdown
Ruim: "Isso vai falhar se a lista estiver vazia."
Bom: "O que acontece se `items` for um array vazio?"

Ruim: "Você precisa de tratamento de erro aqui."
Bom: "Como isso deveria se comportar se a chamada à API falhar?"
```

### Técnica 3: Sugira, Não Ordene

Use uma linguagem colaborativa:

```markdown
Ruim: "Você precisa mudar isso para usar async/await"
Bom: "Sugestão: async/await poderia tornar isso mais legível. O que você acha?"

Ruim: "Extraia isso para uma função"
Bom: "Essa lógica aparece em 3 lugares. Faria sentido extraí-la?"
```

### Técnica 4: Diferencie a Severidade

Use marcadores para indicar prioridade:

- `[bloqueante]` - Precisa ser corrigido antes do merge
- `[importante]` - Deveria ser corrigido; discuta se houver desacordo
- `[nit]` - Desejável, não bloqueante
- `[sugestão]` - Abordagem alternativa a considerar
- `[aprendizado]` - Comentário educativo, sem necessidade de ação
- `[elogio]` - Bom trabalho, continue assim!

**Níveis de severidade:** `[bloqueante]`, `[importante]` e `[nit]` são os três níveis de severidade usados como padrão em todos os guias desta skill — `[bloqueante]` bloqueia o merge, `[importante]` deveria ser resolvido, `[nit]` é opcional. Os demais marcadores (`[sugestão]`, `[aprendizado]`, `[elogio]`) são anotações não bloqueantes.

## Guias Específicos por Linguagem

Consulte o guia detalhado correspondente de acordo com a linguagem do código revisado:

| Linguagem/Framework | Arquivo de Referência | Principais Tópicos |
|-------------------|----------------|------------|
| **Angular 17+** | [Guia de Angular](references/guia-angular.md) | Signals, Componentes Standalone, RxJS, Detecção de mudanças Zoneless, Otimização de templates |
| **TypeScript** | [Guia de TypeScript](references/guia-typescript.md) | Segurança de tipos, async/await, Imutabilidade |
| **Python** | [Guia de Python](references/guia-python.md) | Argumentos padrão mutáveis, Tratamento de exceções, Atributos de classe |
| **Java** | [Guia de Java](references/guia-java.md) | Novidades do Java 17/21, Spring Boot 3, Virtual Threads, Stream/Optional |
| **C# / .NET** | [Guia de C#](references/guia-csharp.md) | Recursos do C# 12, Programação assíncrona, Performance do EF Core, ASP.NET Core, LINQ |
| **Go** | [Guia de Go](references/guia-go.md) | Tratamento de erros, Goroutine/Channel, Context, Design de interfaces |

## Guias Transversais

Padrões independentes de linguagem aplicáveis a todas as revisões de código:

| Tópico | Arquivo de Referência | Principais Tópicos |
|-------|----------------|------------|
| **Qualidade Universal** | [Guia de Qualidade Universal](references/qualidade-codigo-universal.md) | Auditoria de reuso, excesso de parâmetros, abstrações com vazamento, condicionais aninhados, código com tipagem por string, TOCTOU, atualizações sem efeito, estado redundante |

## Recursos Adicionais

- [Guia de Revisão de Arquitetura](references/guia-revisao-arquitetura.md) - Guia de revisão de design arquitetural (SOLID, anti-padrões, acoplamento)
- [Guia de Revisão de Performance](references/guia-revisao-performance.md) - Guia de revisão de performance (Web Vitals, N+1, complexidade)
- [Checklist de Bugs Comuns](references/checklist-bugs-comuns.md) - Lista de erros comuns organizada por linguagem
- [Guia de Revisão de Segurança](references/guia-revisao-seguranca.md) - Guia de revisão de segurança
- [Boas Práticas de Revisão de Código](references/boas-praticas-revisao-codigo.md) - Boas práticas de revisão de código
- [Guia de Publicação com gh CLI](references/guia-gh-cli.md) - Como publicar a revisão no GitHub via `gh api` (revisão pendente, sugestões de código, aprovação do usuário)
- [Modelo de Revisão de PR](assets/modelo-revisao-pr.md) - Modelo de comentário de revisão de PR
- [Checklist de Revisão](assets/checklist-revisao.md) - Lista de referência rápida
