# Guia de Revisão de Código Java

Foco da revisão em Java: novas funcionalidades do Java 17/21, melhores práticas do Spring Boot 3, programação concorrente (Virtual Threads), otimização de performance em JPA e manutenibilidade do código.

## Índice

- [Funcionalidades modernas do Java (17/21+)](#funcionalidades-modernas-do-java-1721)
- [Stream API & Optional](#stream-api--optional)
- [Melhores práticas do Spring Boot](#melhores-práticas-do-spring-boot)
- [JPA e performance de banco de dados](#jpa-e-performance-de-banco-de-dados)
- [Concorrência e Virtual Threads](#concorrência-e-virtual-threads)
- [Padrões de uso do Lombok](#padrões-de-uso-do-lombok)
- [Tratamento de erros](#tratamento-de-erros)
- [Padrões de teste](#padrões-de-teste)
- [Checklist de Revisão](#checklist-de-revisão)

---

## Funcionalidades modernas do Java (17/21+)

### Record (classes de registro)

```java
// POJO/DTO tradicional: muito código boilerplate
public class UserDto {
    private final String name;
    private final int age;

    public UserDto(String name, int age) {
        this.name = name;
        this.age = age;
    }
    // getters, equals, hashCode, toString...
}

// Usando Record: conciso, imutável, semântica clara
public record UserDto(String name, int age) {
    // Construtor compacto para validação
    public UserDto {
        if (age < 0) throw new IllegalArgumentException("Age cannot be negative");
    }
}
```

### Switch expressions e pattern matching

```java
// Switch tradicional: fácil esquecer o break, além de verboso e propenso a erros
String type = "";
switch (obj) {
    case Integer i: // Java 16+
        type = String.format("int %d", i);
        break;
    case String s:
        type = String.format("string %s", s);
        break;
    default:
        type = "unknown";
}

// Switch expression: sem risco de fall-through, força retorno de valor
String type = switch (obj) {
    case Integer i -> "int %d".formatted(i);
    case String s  -> "string %s".formatted(s);
    case null      -> "null value"; // Java 21 trata null
    default        -> "unknown";
};
```

### Text Blocks (blocos de texto)

```java
// Concatenação de strings SQL/JSON
String json = "{\n" +
              "  \"name\": \"Alice\",\n" +
              "  \"age\": 20\n" +
              "}";

// Usando text block: o que se vê é o que se obtém
String json = """
    {
      "name": "Alice",
      "age": 20
    }
    """;
```

---

## Stream API & Optional

### Evite o uso excessivo de Stream

```java
// Loops simples não precisam de Stream (overhead de performance + legibilidade pior)
items.stream().forEach(item -> {
    process(item);
});

// Em cenários simples, use for-each diretamente
for (var item : items) {
    process(item);
}

// Cadeia de Stream extremamente complexa
List<Dto> result = list.stream()
    .filter(...)
    .map(...)
    .peek(...)
    .sorted(...)
    .collect(...); // Difícil de depurar

// Divida em etapas com significado claro
var filtered = list.stream().filter(...).toList();
// ...
```

### Uso correto do Optional

```java
// Usar Optional como parâmetro ou campo (problemas de serialização, aumenta a complexidade de chamada)
public void process(Optional<String> name) { ... }
public class User {
    private Optional<String> email; // Não recomendado
}

// Optional deve ser usado apenas como tipo de retorno
public Optional<User> findUser(String id) { ... }

// Já que está usando Optional, mas ainda usa isPresent() + get()
Optional<User> userOpt = findUser(id);
if (userOpt.isPresent()) {
    return userOpt.get().getName();
} else {
    return "Unknown";
}

// Use a API funcional
return findUser(id)
    .map(User::getName)
    .orElse("Unknown");
```

---

## Melhores práticas do Spring Boot

### Injeção de dependência (DI)

```java
// Injeção via campo (@Autowired)
// Desvantagens: difícil de testar (requer injeção via reflection), mascara o problema de
// dependências excessivas e prejudica a imutabilidade
@Service
public class UserService {
    @Autowired
    private UserRepository userRepo;
}

// Injeção via construtor (Constructor Injection)
// Vantagens: dependências explícitas, fácil de testar com unit tests (Mock), campos podem ser final
@Service
public class UserService {
    private final UserRepository userRepo;

    public UserService(UserRepository userRepo) {
        this.userRepo = userRepo;
    }
}
// Dica: combinar com Lombok @RequiredArgsConstructor pode simplificar o código, mas
// cuidado com dependências circulares
```

### Gerenciamento de configuração

```java
// Valores de configuração hardcoded
@Service
public class PaymentService {
    private String apiKey = "sk_live_12345";
}

// Uso direto de @Value espalhado pelo código
@Value("${app.payment.api-key}")
private String apiKey;

// Use @ConfigurationProperties para configuração type-safe
@ConfigurationProperties(prefix = "app.payment")
public record PaymentProperties(String apiKey, int timeout, String url) {}
```

---

## JPA e performance de banco de dados

### Problema de consultas N+1

```java
// FetchType.EAGER ou lazy loading disparado dentro de um loop
// Definição da Entity
@Entity
public class User {
    @OneToMany(fetch = FetchType.EAGER) // Perigoso!
    private List<Order> orders;
}

// Código de negócio
List<User> users = userRepo.findAll(); // 1 consulta SQL
for (User user : users) {
    // Se for Lazy, isto vai disparar N consultas SQL
    System.out.println(user.getOrders().size());
}

// Use @EntityGraph ou JOIN FETCH
@Query("SELECT u FROM User u JOIN FETCH u.orders")
List<User> findAllWithOrders();
```

### Gerenciamento de transações

```java
// Abrir transação na camada de Controller (tempo de uso da conexão com o
// banco muito longo)
// Adicionar @Transactional em método private (o AOP não tem efeito)
@Transactional
private void saveInternal() { ... }

// Adicione @Transactional em métodos públicos da camada de Service
// Marque explicitamente operações de leitura com readOnly = true (otimização de performance)
@Service
public class UserService {
    @Transactional(readOnly = true)
    public User getUser(Long id) { ... }

    @Transactional
    public void createUser(UserDto dto) { ... }
}
```

### Design de Entity

```java
// Usar Lombok @Data em uma Entity
// O equals/hashCode gerado pelo @Data inclui todos os campos, podendo disparar
// lazy loading e causar problemas de performance ou exceções
@Entity
@Data
public class User { ... }

// Use apenas @Getter, @Setter
// Implemente equals/hashCode customizados (geralmente baseados no ID)
@Entity
@Getter
@Setter
public class User {
    @Id
    private Long id;

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof User)) return false;
        return id != null && id.equals(((User) o).id);
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
```

---

## Concorrência e Virtual Threads

### Virtual Threads (Java 21+)

```java
// Pool de threads tradicional processando grande volume de tarefas com I/O bloqueante
// (esgotamento de recursos)
ExecutorService executor = Executors.newFixedThreadPool(100);

// Use Virtual Threads para tarefas intensivas em I/O (alto throughput)
// Habilitar no Spring Boot 3.2+: spring.threads.virtual.enabled=true
ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();

// Em uma Virtual Thread, operações bloqueantes (como consultas a banco de dados,
// requisições HTTP) praticamente não consomem recursos de thread do sistema operacional
```

### Segurança em threads

```java
// SimpleDateFormat não é thread-safe
private static final SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd");

// Use DateTimeFormatter (Java 8+)
private static final DateTimeFormatter dtf = DateTimeFormatter.ofPattern("yyyy-MM-dd");

// HashMap perde dados em ambiente multithread (no Java 7 e anteriores o resize
// ainda podia causar loop infinito; o Java 8 corrigiu o loop infinito, mas continua
// não sendo thread-safe)
// Use ConcurrentHashMap
Map<String, String> cache = new ConcurrentHashMap<>();
```

---

## Padrões de uso do Lombok

```java
// Uso excessivo de @Builder impede a validação obrigatória de campos
@Builder
public class Order {
    private String id; // Obrigatório
    private String note; // Opcional
}
// O chamador pode esquecer o id: Order.builder().note("hi").build();

// Para objetos de negócio críticos, recomenda-se escrever manualmente o Builder ou
// construtor para garantir os invariantes
// Ou adicionar lógica de validação no método build() (Lombok @Builder.Default etc.)
```

---

## Tratamento de erros

### Tratamento global de exceções

```java
// try-catch espalhado por todo lugar engolindo exceções ou apenas registrando log
try {
    userService.create(user);
} catch (Exception e) {
    e.printStackTrace(); // Não deve ser usado em produção
    // return null; // Engole a exceção, a camada superior não sabe o que aconteceu
}

// Exceção customizada + @ControllerAdvice (Spring Boot 3 ProblemDetail)
public class UserNotFoundException extends RuntimeException { ... }

@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(UserNotFoundException.class)
    public ProblemDetail handleNotFound(UserNotFoundException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
    }
}
```

---

## Padrões de teste

### Teste unitário vs teste de integração

```java
// Teste unitário dependendo de banco de dados real ou serviço externo
@SpringBootTest // Inicializa todo o Context, lento
public class UserServiceTest { ... }

// Teste unitário usando Mockito
@ExtendWith(MockitoExtension.class)
class UserServiceTest {
    @Mock UserRepository repo;
    @InjectMocks UserService service;

    @Test
    void shouldCreateUser() { ... }
}

// Teste de integração usando Testcontainers
@Testcontainers
@SpringBootTest
class UserRepositoryTest {
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15");
    // ...
}
```

---

## Checklist de Revisão

### Fundamentos e padrões
- [ ] Segue as novas funcionalidades do Java 17/21 (switch expressions, Records, text blocks)
- [ ] Evita o uso de classes obsoletas (Date, Calendar, SimpleDateFormat)
- [ ] As operações de coleção priorizam Stream API ou métodos de Collections?
- [ ] Optional é usado apenas como retorno, não em campos ou parâmetros

### Spring Boot
- [ ] Usa injeção via construtor em vez de injeção via campo com @Autowired
- [ ] Propriedades de configuração usam @ConfigurationProperties
- [ ] O Controller tem responsabilidade única, com a lógica de negócio delegada ao Service
- [ ] O tratamento global de exceções usa @ControllerAdvice / ProblemDetail

### Banco de dados & transações
- [ ] Transações de leitura estão marcadas com `@Transactional(readOnly = true)`
- [ ] Verifica se existem consultas N+1 (fetch EAGER ou chamadas em loop)
- [ ] As classes Entity não usam @Data e implementam corretamente equals/hashCode
- [ ] Os índices do banco de dados cobrem as condições das consultas

### Concorrência e performance
- [ ] Tarefas intensivas em I/O consideraram o uso de Virtual Threads?
- [ ] As classes thread-safe são usadas corretamente (ConcurrentHashMap vs HashMap)
- [ ] A granularidade dos locks é razoável? Evita operações de I/O dentro de locks

### Manutenibilidade
- [ ] A lógica de negócio crítica possui testes unitários suficientes
- [ ] O registro de logs é adequado (usa Slf4j, evita System.out)
- [ ] Valores mágicos foram extraídos como constantes ou enums
</content>
