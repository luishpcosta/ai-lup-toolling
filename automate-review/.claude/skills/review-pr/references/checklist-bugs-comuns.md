# Checklist de Bugs Comuns

Padrões de bugs de referência rápida organizados por categoria. Para exemplos de código detalhados, explicações e checklists de revisão completos, veja os guias dedicados por linguagem vinculados abaixo.

## Problemas Universais

### Erros de Lógica
- [ ] Erros de off-by-one em loops e acesso a arrays
- [ ] Lógica booleana incorreta (violações da lei de De Morgan)
- [ ] Verificações de null/undefined ausentes
- [ ] Condições de corrida em código concorrente
- [ ] Operadores de comparação incorretos (`==` vs `===`, `=` vs `==`)
- [ ] Overflow/underflow de inteiros
- [ ] Problemas de comparação de ponto flutuante

### Gerenciamento de Recursos
- [ ] Vazamentos de memória (conexões e listeners não fechados)
- [ ] File handles não fechados
- [ ] Conexões de banco de dados não liberadas
- [ ] Event listeners não removidos
- [ ] Timers/intervals não limpos

### Tratamento de Erros
- [ ] Exceções engolidas (blocos catch vazios)
- [ ] Tratamento genérico de exceções escondendo erros específicos
- [ ] Propagação de erro ausente
- [ ] Tipos de erro incorretos sendo lançados
- [ ] Blocos finally/cleanup ausentes

## TypeScript/JavaScript

- [ ] `==` em vez de `===`
- [ ] Uso de `any` — prefira tipos adequados ou `unknown` com type guards
- [ ] `await` ausente em chamadas assíncronas
- [ ] Promise rejections não tratadas (sem try-catch em volta do await)
- [ ] Contexto de `this` perdido em callbacks
- [ ] Prop `key` ausente em listas
- [ ] Closure capturando variável de loop desatualizada (stale)
- [ ] `parseInt` sem o parâmetro radix
- [ ] Modificação de array/objeto durante iteração

**Guia completo:** [Guia de Revisão TypeScript](guia-typescript.md)

## Python

- [ ] Argumentos padrão mutáveis (`def f(x=[])`)
- [ ] `except:` genérico capturando `KeyboardInterrupt` e `SystemExit`
- [ ] Atributos de classe mutáveis compartilhados (`class C: items = []`)
- [ ] Uso de `is` em vez de `==` para comparação de valor
- [ ] Esquecer o parâmetro `self` em métodos
- [ ] Modificação de lista durante iteração
- [ ] Concatenação de strings em loops (use `"".join()`)
- [ ] Não fechar arquivos (use a instrução `with`)
- [ ] Anotações de tipo ausentes em funções públicas

**Guia completo:** [Guia de Revisão Python](guia-python.md)

## Go

- [ ] Ignorar erros (`result, _ := SomeFunction()`)
- [ ] Goroutine sem mecanismo de saída (vazamento)
- [ ] Propagação de `context.Context` ausente ou incorreta
- [ ] Problema de captura de variável de loop (Go < 1.22)
- [ ] `defer` em loops (é postergado até o fim da função, não da iteração do loop)
- [ ] Shadowing de variável
- [ ] Map usado antes da inicialização
- [ ] Encapsulamento de erro com `%v` em vez de `%w` (quebra `errors.Is`/`errors.As`)

**Guia completo:** [Guia de Revisão Go](guia-go.md)

## Java / Spring Boot

- [ ] POJO/DTO com boilerplate manual em vez de `record`
- [ ] Switch tradicional sem `break` (use switch expressions)
- [ ] Injeção por campo em vez de injeção por construtor
- [ ] Consulta N+1 do JPA (sem `fetch join` ou `@EntityGraph`)
- [ ] `equals`/`hashCode` incorretos em entidades JPA (use chave de negócio, não o ID)
- [ ] `Optional.get()` sem verificação `isPresent()`
- [ ] Operações de Stream com efeitos colaterais

**Guia completo:** [Guia de Revisão Java](guia-java.md)

## SQL

- [ ] Concatenação de string para queries (risco de injeção SQL) — use consultas parametrizadas
- [ ] Índices ausentes em colunas filtradas/usadas em JOIN
- [ ] `SELECT *` em vez de colunas específicas
- [ ] Padrões de consulta N+1
- [ ] `LIMIT` ausente em tabelas grandes
- [ ] Comparações com `NULL` tratadas incorretamente (`IS NULL` vs `= NULL`)
- [ ] Transações ausentes para operações relacionadas
- [ ] Tipos de JOIN incorretos
- [ ] Surpresas de collation / case sensitivity entre bancos de dados (padrões do MySQL vs. Postgres)
- [ ] Erros de tratamento de data e timezone (timestamps naive, `NOW()` no horário local do servidor, DST)

**Veja também:** [Guia de Revisão de Segurança](guia-revisao-seguranca.md) para prevenção de injeção SQL

## Design de API

- [ ] Nomenclatura de recursos inconsistente
- [ ] Métodos HTTP incorretos (POST para operações idempotentes)
- [ ] Paginação ausente em endpoints de listagem
- [ ] Códigos de status incorretos
- [ ] Rate limiting ausente
- [ ] Validação e sanitização de entrada ausentes
- [ ] Confiar apenas na validação do lado do cliente

## Testes

- [ ] Testando detalhes de implementação em vez de comportamento
- [ ] Testes de casos extremos ausentes
- [ ] Testes instáveis (flaky, não determinísticos)
- [ ] Testes com dependências externas (sem mocks)
- [ ] Testes negativos ausentes (casos de erro)
- [ ] Setup de teste excessivamente complexo
