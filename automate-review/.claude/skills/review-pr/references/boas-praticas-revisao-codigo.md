# Boas Práticas de Revisão de Código

Diretrizes completas para conduzir revisões de código eficazes.

## Filosofia de Revisão

### Objetivos da Revisão de Código

**Objetivos primários:**
- Detectar bugs e casos extremos antes da produção
- Garantir a manutenibilidade e a legibilidade do código
- Compartilhar conhecimento entre o time
- Aplicar padrões de codificação de forma consistente
- Melhorar decisões de design e arquitetura

**Objetivos secundários:**
- Mentorar desenvolvedores juniores
- Construir cultura e confiança no time
- Documentar decisões de design por meio das discussões

### O que a revisão de código NÃO é

- Um mecanismo de bloqueio para travar o progresso
- Uma oportunidade para exibir conhecimento
- Um lugar para implicar com formatação (use linters)
- Uma forma de reescrever código de acordo com preferência pessoal

## Momento da Revisão

### Quando revisar

| Gatilho | Ação |
|---------|------|
| PR aberto | Revisar dentro de 24 horas, idealmente no mesmo dia |
| Mudanças solicitadas | Revisar novamente dentro de 4 horas |
| Problema bloqueante encontrado | Comunicar imediatamente |

### Alocação de tempo

- **PR pequeno (<100 linhas)**: 10-15 minutos
- **PR médio (100-400 linhas)**: 20-40 minutos
- **PR grande (>400 linhas)**: Solicitar divisão, ou 60+ minutos

## Níveis de Profundidade da Revisão

### Nível 1: Revisão Superficial (5 minutos)
- Verificar a descrição do PR e issues vinculadas
- Verificar o status do CI/CD
- Olhar a visão geral das alterações de arquivos
- Identificar se é necessária uma revisão mais profunda

### Nível 2: Revisão Padrão (20-30 minutos)
- Percorrer todo o código
- Verificação da lógica
- Verificação de cobertura de testes
- Varredura de segurança

### Nível 3: Revisão Profunda (60+ minutos)
- Avaliação de arquitetura
- Análise de performance
- Auditoria de segurança
- Exploração de casos extremos

## Diretrizes de Comunicação

### Tom e linguagem

**Use linguagem colaborativa:**
- "O que você pensa sobre..." em vez de "Você deveria..."
- "Poderíamos considerar..." em vez de "Isso está errado"
- "Estou curioso sobre..." em vez de "Por que você não..."

**Seja específico e prático:**
- Inclua exemplos de código ao sugerir mudanças
- Vincule a documentação ou discussões anteriores
- Explique o "porquê" por trás das sugestões

### Lidando com discordâncias

1. **Busque entender**: Faça perguntas de esclarecimento
2. **Reconheça pontos válidos**: Mostre que você considerou a perspectiva da outra pessoa
3. **Forneça dados**: Use benchmarks, documentação ou exemplos
4. **Escale se necessário**: Envolva um dev sênior ou arquiteto
5. **Saiba quando deixar passar**: Nem toda colina vale a luta

## Priorização da Revisão

### Deve corrigir (bloqueante)
- Vulnerabilidades de segurança
- Riscos de corrupção de dados
- Mudanças que quebram compatibilidade sem migração
- Problemas críticos de performance
- Tratamento de erros ausente em funcionalidades voltadas ao usuário

### Deveria corrigir (importante)
- Lacunas na cobertura de testes
- Preocupações moderadas de performance
- Duplicação de código
- Nomenclatura ou estrutura pouco clara
- Documentação ausente para lógica complexa

### Bom ter (não bloqueante)
- Preferências de estilo além do que o linter cobre
- Otimizações menores
- Casos de teste adicionais
- Melhorias de documentação

## Anti-Padrões a Evitar

### Anti-padrões do revisor
- **Aprovação automática (rubber stamping)**: Aprovar sem de fato revisar
- **Bike shedding**: Debater detalhes triviais extensivamente
- **Scope creep**: "Já que você está nisso, pode também..."
- **Ghosting**: Solicitar mudanças e depois desaparecer
- **Perfeccionismo**: Bloquear por preferências menores de estilo

### Anti-padrões do autor
- **Mega PRs**: Submeter mudanças com 1000+ linhas
- **Sem contexto**: Faltando descrição do PR ou issues vinculadas
- **Respostas defensivas**: Discutir cada sugestão
- **Atualizações silenciosas**: Fazer mudanças sem responder aos comentários

## Métricas e Melhoria

### Acompanhe estas métricas
- Tempo até a primeira revisão
- Tempo de ciclo de revisão
- Número de rodadas de revisão
- Taxa de escape de defeitos
- Percentual de cobertura de revisão

### Melhoria contínua
- Faça retrospectivas sobre o processo de revisão
- Compartilhe aprendizados de bugs que escaparam
- Atualize checklists com base em problemas recorrentes
- Celebre boas revisões e boas detecções
