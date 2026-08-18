# Guia de Revisão de Arquitetura

Guia de revisão de design arquitetural, para ajudar a avaliar se a arquitetura do código é razoável e se o design é adequado.

> **Antes de aplicar os critérios deste guia, verifique se o projeto já define suas próprias regras de arquitetura** — um `constitution.md` na raiz do repositório e/ou arquivos dentro de `docs/rules/`. Se existirem, eles são a fonte da verdade para a arquitetura *daquele* projeto e têm prioridade sobre este guia: avalie o código contra essas regras primeiro, e use os critérios genéricos abaixo (SOLID, acoplamento/coesão, anti-padrões etc.) apenas para complementar lacunas que o projeto não cobriu. Sem `constitution.md`/`docs/rules/`, aplique este guia normalmente como critério padrão.

## Índice

- [Checklist dos princípios SOLID](#checklist-dos-princípios-solid)
- [Identificação de anti-padrões de arquitetura](#identificação-de-anti-padrões-de-arquitetura)
- [Avaliação de acoplamento e coesão](#avaliação-de-acoplamento-e-coesão)
- [Revisão de arquitetura em camadas](#revisão-de-arquitetura-em-camadas)
- [Avaliação do uso de padrões de design](#avaliação-do-uso-de-padrões-de-design)
- [Avaliação de extensibilidade](#avaliação-de-extensibilidade)
- [Boas práticas de estrutura de código](#boas-práticas-de-estrutura-de-código)
- [Checklist de referência rápida](#checklist-de-referência-rápida)
- [Ferramentas recomendadas](#ferramentas-recomendadas)
- [Recursos de referência](#recursos-de-referência)

## Checklist dos princípios SOLID

### S - Princípio da Responsabilidade Única (SRP)

**Pontos de verificação:**
- Essa classe/módulo tem apenas um motivo para mudar?
- Os métodos da classe servem todos ao mesmo propósito?
- Se você tivesse que descrever essa classe para alguém não técnico, conseguiria explicar em uma frase?

**Sinais de identificação durante a revisão de código:**
```
Nome da classe contém termos genéricos como "And", "Manager", "Handler", "Processor"
Uma classe com mais de 200-300 linhas de código
Classe com mais de 5-7 métodos públicos
Métodos diferentes operam sobre dados completamente diferentes
```

**Perguntas de revisão:**
- "Quais responsabilidades essa classe tem? É possível dividi-la?"
- "Se o requisito X mudar, quais métodos precisam mudar? E se for o requisito Y?"

### O - Princípio Aberto/Fechado (OCP)

**Pontos de verificação:**
- Ao adicionar uma nova funcionalidade, é necessário modificar o código existente?
- É possível adicionar novo comportamento por meio de extensão (herança, composição)?
- Existem muitos if/else ou switch para tratar tipos diferentes?

**Sinais de identificação durante a revisão de código:**
```
Cadeias de switch/if-else tratando tipos diferentes
Adicionar uma nova funcionalidade exige modificar a classe central
Verificações de tipo (instanceof, typeof) espalhadas pelo código
```

**Perguntas de revisão:**
- "Se for necessário adicionar um novo tipo X, quais arquivos precisam ser modificados?"
- "Esse switch vai continuar crescendo conforme novos tipos forem adicionados?"

### L - Princípio da Substituição de Liskov (LSP)

**Pontos de verificação:**
- A subclasse pode substituir completamente a classe pai em uso?
- A subclasse altera o comportamento esperado dos métodos da classe pai?
- Existe alguma subclasse lançando exceções não declaradas pela classe pai?

**Sinais de identificação durante a revisão de código:**
```
Conversões de tipo explícitas (casting)
Métodos de subclasse lançando NotImplementedException
Métodos de subclasse com implementação vazia ou apenas um return
Locais que usam a classe base precisam verificar o tipo concreto
```

**Perguntas de revisão:**
- "Se substituirmos a classe pai pela subclasse, o código que a chama precisa ser alterado?"
- "O comportamento desse método na subclasse respeita o contrato da classe pai?"

### I - Princípio da Segregação de Interface (ISP)

**Pontos de verificação:**
- A interface é pequena e focada o suficiente?
- As classes que implementam são forçadas a implementar métodos que não precisam?
- Os clientes dependem de métodos que não utilizam?

**Sinais de identificação durante a revisão de código:**
```
Interface com mais de 5-7 métodos
Classes que implementam têm métodos vazios ou lançam NotImplementedException
Nome da interface muito genérico (IManager, IService)
Clientes diferentes usam apenas parte dos métodos da interface
```

**Perguntas de revisão:**
- "Todos os métodos dessa interface são usados por cada classe que a implementa?"
- "É possível dividir essa interface grande em interfaces menores e especializadas?"

### D - Princípio da Inversão de Dependência (DIP)

**Pontos de verificação:**
- Os módulos de alto nível dependem de abstrações em vez de implementações concretas?
- É usada injeção de dependência em vez de instanciar objetos diretamente com `new`?
- As abstrações são definidas pelos módulos de alto nível, não pelos de baixo nível?

**Sinais de identificação durante a revisão de código:**
```
Módulo de alto nível instancia diretamente (new) uma classe concreta de baixo nível
Importa classes de implementação concreta em vez de interfaces/classes abstratas
Configurações e strings de conexão fixas (hardcoded) na lógica de negócio
Dificuldade para escrever testes unitários para determinada classe
```

**Perguntas de revisão:**
- "As dependências dessa classe podem ser substituídas por mocks durante os testes?"
- "Se for necessário trocar a implementação de banco de dados/API, quantos lugares precisam ser alterados?"

---

## Identificação de anti-padrões de arquitetura

### Anti-padrões críticos

| Anti-padrão | Sinal de identificação | Impacto |
|--------|----------|------|
| **Bola de lama (Big Ball of Mud)** | Sem limites claros entre módulos, qualquer código pode chamar qualquer outro código | Difícil de entender, modificar e testar |
| **Classe Deus (God Object)** | Uma única classe assume responsabilidades demais, sabe demais e faz demais | Alto acoplamento, difícil de reutilizar e testar |
| **Código espaguete** | Fluxo de controle confuso, gotos ou aninhamento profundo, difícil de rastrear o caminho de execução | Difícil de entender e manter |
| **Fluxo de lava (Lava Flow)** | Código antigo que ninguém ousa tocar, sem documentação nem testes | Acúmulo de dívida técnica |

### Anti-padrões de design

| Anti-padrão | Sinal de identificação | Sugestão |
|--------|----------|------|
| **Martelo de ouro (Golden Hammer)** | Usar a mesma tecnologia/padrão para todos os problemas | Escolher a solução adequada para cada problema |
| **Engenharia excessiva (Gas Factory)** | Resolver problemas simples com soluções complexas, uso abusivo de padrões de design | Princípio YAGNI, começar simples e complicar depois se necessário |
| **Âncora morta (Boat Anchor)** | Código não utilizado escrito para "talvez ser necessário no futuro" | Remover código não utilizado, escrever quando for realmente necessário |
| **Copiar e colar** | A mesma lógica aparece em vários lugares | Extrair um método ou módulo comum |

### Perguntas de revisão

```markdown
[bloqueante] "Essa classe tem 2000 linhas de código, sugiro dividir em várias classes mais focadas"
[importante] "Essa lógica se repete em 3 lugares, que acha de extrair para um método comum?"
[sugestão] "Esse switch poderia ser substituído pelo padrão Strategy, ficando mais fácil de estender"
```

---

## Avaliação de acoplamento e coesão

### Tipos de acoplamento (do melhor para o pior)

| Tipo | Descrição | Exemplo |
|------|------|------|
| **Acoplamento por mensagem** | Dados passados por parâmetro | `calculate(price, quantity)` |
| **Acoplamento por dados** | Estrutura de dados simples compartilhada | `processOrder(orderDTO)` |
| **Acoplamento por marca (stamp)** | Estrutura de dados complexa compartilhada, mas usando só parte dela | Passar o objeto User inteiro mas usar só o name |
| **Acoplamento por controle** | Passar flags de controle que afetam o comportamento | `process(data, isAdmin=true)` |
| **Acoplamento comum** | Variáveis globais compartilhadas | Vários módulos lendo e escrevendo o mesmo estado global |
| **Acoplamento por conteúdo** | Acesso direto ao interior de outro módulo | Manipular diretamente atributos privados de outra classe |

### Tipos de coesão (do melhor para o pior)

| Tipo | Descrição | Qualidade |
|------|------|------|
| **Coesão funcional** | Todos os elementos realizam uma única tarefa | Melhor |
| **Coesão sequencial** | A saída de uma etapa é a entrada da próxima | Boa |
| **Coesão comunicacional** | Operam sobre os mesmos dados | Aceitável |
| **Coesão temporal** | Tarefas executadas ao mesmo tempo | Ruim |
| **Coesão lógica** | Relacionadas logicamente, mas com funções diferentes | Má |
| **Coesão acidental** | Sem relação aparente | Pior |

### Referência de métricas

```yaml
metricas_de_acoplamento:
  CBO (acoplamento entre classes):
    bom: < 5
    alerta: 5-10
    perigo: > 10

  Ce (acoplamento de saída):
    descricao: quantas classes externas são dependências
    bom: < 7

  Ca (acoplamento de entrada):
    descricao: quantas classes dependem desta
    valor_alto_significa: grande impacto em mudanças, precisa ser estável

metricas_de_coesao:
  LCOM4 (falta de coesão em métodos):
    1: responsabilidade única 
    2-3: pode precisar de divisão 
    >3: deveria ser dividida 
```

### Perguntas de revisão

- "De quantos outros módulos esse módulo depende? É possível reduzir?"
- "Modificar essa classe vai impactar quantos outros lugares?"
- "Os métodos dessa classe operam todos sobre os mesmos dados?"

---

## Revisão de arquitetura em camadas

### Verificação das camadas da Clean Architecture

```
┌─────────────────────────────────────┐
│         Frameworks & Drivers        │ ← Camada mais externa: Web, BD, UI
├─────────────────────────────────────┤
│         Interface Adapters          │ ← Controllers, Gateways, Presenters
├─────────────────────────────────────┤
│          Application Layer          │ ← Use Cases, Application Services
├─────────────────────────────────────┤
│            Domain Layer             │ ← Entities, Domain Services
└─────────────────────────────────────┘
          ↑ A direção da dependência só pode ser para dentro ↑
```

### Verificação da regra de dependência

**Regra central: o código-fonte só pode depender das camadas internas**

```typescript
// Viola a regra de dependência: a camada Domain depende da Infrastructure
// domain/User.ts
import { MySQLConnection } from '../infrastructure/database';

// Correto: a camada Domain define a interface, a Infrastructure implementa
// domain/UserRepository.ts (interface)
interface UserRepository {
  findById(id: string): Promise<User>;
}

// infrastructure/MySQLUserRepository.ts (implementação)
class MySQLUserRepository implements UserRepository {
  findById(id: string): Promise<User> { /* ... */ }
}
```

### Checklist de revisão

**Verificação dos limites entre camadas:**
- [ ] A camada Domain tem dependências externas (banco de dados, HTTP, sistema de arquivos)?
- [ ] A camada Application acessa diretamente o banco de dados ou chama APIs externas?
- [ ] O Controller contém lógica de negócio?
- [ ] Existem chamadas entre camadas que pulam etapas (UI chamando Repository diretamente)?

**Verificação da separação de responsabilidades:**
- [ ] A lógica de negócio está separada da lógica de apresentação?
- [ ] O acesso a dados está encapsulado em uma camada dedicada?
- [ ] O código de configuração e ambiente é gerenciado de forma centralizada?

### Perguntas de revisão

```markdown
[bloqueante] "A entidade de Domain importa diretamente a conexão com o banco de dados, violando a regra de dependência"
[importante] "O Controller contém lógica de cálculo de negócio, sugiro mover para a camada de Service"
[sugestão] "Considere usar injeção de dependência para desacoplar esses componentes"
```

---

## Avaliação do uso de padrões de design

### Quando usar padrões de design

| Padrão | Cenário adequado | Cenário inadequado |
|------|----------|------------|
| **Factory** | Precisa criar objetos de tipos diferentes, com o tipo determinado em tempo de execução | Existe apenas um tipo, ou o tipo é fixo |
| **Strategy** | O algoritmo precisa ser trocado em tempo de execução, há vários comportamentos intercambiáveis | Existe apenas um algoritmo, ou ele nunca muda |
| **Observer** | Dependência um-para-muitos, mudanças de estado precisam notificar vários objetos | Uma chamada direta simples já atende à necessidade |
| **Singleton** | Realmente é necessária uma única instância global, como gerenciamento de configuração | Objeto que pode ser passado via injeção de dependência |
| **Decorator** | Precisa adicionar responsabilidades dinamicamente, evitando explosão de herança | Responsabilidades fixas, sem necessidade de composição dinâmica |

### Sinais de alerta de design excessivo

```
Sinais de identificação de "Patternitis" (excesso de padrões):

1. Um if/else simples foi substituído por Strategy + Factory + Registry
2. Interface com apenas uma implementação
3. Camada de abstração adicionada para "talvez ser necessária no futuro"
4. Número de linhas de código aumentou bastante por causa da aplicação do padrão
5. Novos integrantes demoram muito para entender a estrutura do código
```

### Princípios de revisão

```markdown
Uso correto do padrão:
- Resolveu um problema real de extensibilidade
- O código ficou mais fácil de entender e testar
- Adicionar novas funcionalidades ficou mais simples

Uso excessivo do padrão:
- Usado apenas pelo motivo de usar um padrão
- Adicionou complexidade desnecessária
- Viola o princípio YAGNI
```

### Perguntas de revisão

- "Que problema concreto esse padrão resolveu?"
- "Se esse padrão não fosse usado, que problema o código teria?"
- "O valor trazido por essa camada de abstração é maior que sua complexidade?"

---

## Avaliação de extensibilidade

### Checklist de extensibilidade

**Extensibilidade de funcionalidades:**
- [ ] Adicionar uma nova funcionalidade exige modificar o código central?
- [ ] Existem pontos de extensão fornecidos (hooks, plugins, events)?
- [ ] A configuração está externalizada (arquivo de configuração, variáveis de ambiente)?

**Extensibilidade de dados:**
- [ ] O modelo de dados suporta a adição de novos campos?
- [ ] Foi considerado o cenário de crescimento do volume de dados?
- [ ] As consultas têm índices adequados?

**Extensibilidade de carga:**
- [ ] É possível escalar horizontalmente (adicionar mais instâncias)?
- [ ] Existe dependência de estado (session, cache local)?
- [ ] A conexão com o banco de dados usa pool de conexões?

### Verificação de design de pontos de extensão

```typescript
// Bom design de extensão: usando eventos/hooks
class OrderService {
  private hooks: OrderHooks;

  async createOrder(order: Order) {
    await this.hooks.beforeCreate?.(order);
    const result = await this.save(order);
    await this.hooks.afterCreate?.(result);
    return result;
  }
}

// Mau design de extensão: todo o comportamento fixo no código
class OrderService {
  async createOrder(order: Order) {
    await this.sendEmail(order);        // fixo no código
    await this.updateInventory(order);  // fixo no código
    await this.notifyWarehouse(order);  // fixo no código
    return await this.save(order);
  }
}
```

### Perguntas de revisão

```markdown
[sugestão] "Se no futuro for necessário suportar uma nova forma de pagamento, esse design permite estender facilmente?"
[importante] "Essa lógica está fixa no código, que acha de usar configuração ou o padrão Strategy?"
[aprendizado] "Uma arquitetura orientada a eventos pode tornar essa funcionalidade mais fácil de estender"
```

---

## Boas práticas de estrutura de código

### Organização de diretórios

**Organizado por funcionalidade/domínio (recomendado):**
```
src/
├── user/
│   ├── User.ts           (entidade)
│   ├── UserService.ts    (serviço)
│   ├── UserRepository.ts (acesso a dados)
│   └── UserController.ts (API)
├── order/
│   ├── Order.ts
│   ├── OrderService.ts
│   └── ...
└── shared/
    ├── utils/
    └── types/
```

**Organizado por camada técnica (não recomendado):**
```
src/
├── controllers/     ← domínios diferentes misturados
│   ├── UserController.ts
│   └── OrderController.ts
├── services/
├── repositories/
└── models/
```

### Verificação de convenções de nomenclatura

| Tipo | Convenção | Exemplo |
|------|------|------|
| Nome de classe | PascalCase, substantivo | `UserService`, `OrderRepository` |
| Nome de método | camelCase, verbo | `createUser`, `findOrderById` |
| Nome de interface | prefixo I ou sem prefixo | `IUserService` ou `UserService` |
| Constante | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| Atributo privado | prefixo de underscore ou sem | `_cache` ou `#cache` |

### Diretrizes de tamanho de arquivo

```yaml
limites_sugeridos:
  arquivo_unico: < 300 linhas
  funcao_unica: < 50 linhas
  classe_unica: < 200 linhas
  parametros_de_funcao: < 4
  profundidade_de_aninhamento: < 4 níveis

ao_exceder_os_limites:
  - considerar dividir em unidades menores
  - usar composição em vez de herança
  - extrair funções ou classes auxiliares
```

### Perguntas de revisão

```markdown
[nit] "Esse arquivo de 500 linhas poderia ser dividido por responsabilidade"
[importante] "Sugiro organizar a estrutura de diretórios por domínio funcional em vez de por camada técnica"
[sugestão] "O nome da função `process` não é claro o suficiente, que acha de mudar para `calculateOrderTotal`?"
```

---

## Checklist de referência rápida

### Checagem rápida de arquitetura em 5 minutos

```markdown
□ A direção das dependências está correta? (camadas externas dependendo das internas)
□ Existe dependência circular?
□ A lógica de negócio central está desacoplada do framework/UI/banco de dados?
□ Os princípios SOLID são seguidos?
□ Existe algum anti-padrão evidente?
```

### Sinais de bandeira vermelha (precisam ser tratados)

```markdown
Classe Deus (God Object) - uma única classe com mais de 1000 linhas
Dependência circular - A → B → C → A
Camada Domain contém dependência de framework
Configurações e chaves fixas (hardcoded) no código
Chamada a serviço externo sem interface
```

### Sinais de bandeira amarela (sugerido tratar)

```markdown
Acoplamento entre classes (CBO) > 10
Função com mais de 5 parâmetros
Profundidade de aninhamento maior que 4 níveis
Bloco de código duplicado > 10 linhas
Interface com apenas uma implementação
```

---

## Ferramentas recomendadas

| Ferramenta | Uso | Suporte de linguagem |
|------|------|----------|
| **SonarQube** | Qualidade de código, análise de acoplamento | Multilinguagem |
| **NDepend** | Análise de dependências, regras de arquitetura | .NET |
| **JDepend** | Análise de dependências entre pacotes | Java |
| **Madge** | Grafo de dependências entre módulos | JavaScript/TypeScript |
| **ESLint** | Padrões de código, verificação de complexidade | JavaScript/TypeScript |
| **CodeScene** | Dívida técnica, análise de pontos críticos | Multilinguagem |

---

## Recursos de referência

- [Clean Architecture - Uncle Bob](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [SOLID Principles in Code Review - JetBrains](https://blog.jetbrains.com/upsource/2015/08/31/what-to-look-for-in-a-code-review-solid-principles-2/)
- [Software Architecture Anti-Patterns](https://medium.com/@christophnissle/anti-patterns-in-software-architecture-3c8970c9c4f5)
- [Coupling and Cohesion in System Design](https://www.geeksforgeeks.org/system-design/coupling-and-cohesion-in-system-design/)
- [Design Patterns - Refactoring Guru](https://refactoring.guru/design-patterns)
