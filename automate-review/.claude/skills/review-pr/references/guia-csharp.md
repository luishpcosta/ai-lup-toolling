# Guia de Revisão de Código C# / .NET

> Guia de revisão de código C# / .NET 8, cobrindo as novidades do C# 12, programação assíncrona, performance do EF Core, boas práticas do ASP.NET Core, injeção de dependência, LINQ como temas centrais.

## Índice

- [Novidades do C# 12](#novidades-do-c-12)
- [Programação Assíncrona](#programação-assíncrona)
- [Performance do EF Core](#performance-do-ef-core)
- [Boas Práticas do ASP.NET Core](#boas-práticas-do-aspnet-core)
- [Injeção de Dependência](#injeção-de-dependência)
- [Boas Práticas de LINQ](#boas-práticas-de-linq)
- [Checklist de Revisão](#checklist-de-revisão)

---

## Novidades do C# 12

### Primary Constructors (tipos que não são record)

```csharp
// Construtor tradicional com excesso de código repetitivo (boilerplate)
public class ProductService
{
    private readonly ProductDbContext _db;
    private readonly ILogger<ProductService> _logger;

    public ProductService(ProductDbContext db, ILogger<ProductService> logger)
    {
        _db = db;
        _logger = logger;
    }
}

// Primary Constructor — injeção de dependência mais concisa
public class ProductService(ProductDbContext db, ILogger<ProductService> logger)
{
    public async Task<Product?> GetAsync(int id)
        => await db.Products.FindAsync(id);
}

// Atenção: os parâmetros do primary constructor não são propriedades e não podem ser reatribuídos
// Se precisar de armazenamento de longo prazo, declare o campo explicitamente
public class OrderService(OrderDbContext db)
{
    private readonly OrderDbContext _db = db; // captura explícita
}
```

### Collection Expressions

```csharp
// Inicialização tradicional de coleção
int[] nums = new int[] { 1, 2, 3 };
List<string> names = new List<string> { "alice", "bob" };

// Collection expressions
int[] nums = [1, 2, 3];
List<string> names = ["alice", "bob"];
Span<char> span = ['a', 'b'];

// Operador de spread
int[] merged = [..nums, 4, 5];
```

### Parâmetros padrão em Lambdas

```csharp
// Sobrecarga de lambda
var add = (int a, int b) => a + b;
var addDefault = (int a) => a + 1;

// Parâmetro padrão
var add = (int a, int b = 1) => a + b;
```

---

## Programação Assíncrona

### Task.Wait() / .Result / async void são anti-padrões graves

```csharp
// Task.Wait() — risco de deadlock (bloqueia de forma síncrona uma operação assíncrona)
public ActionResult<Data> Get(int id)
{
    var data = _service.GetDataAsync(id).Result; // deadlock!
    return Ok(data);
}

// async void — exceções não podem ser capturadas, derrubam o processo
public async void HandleEvent()
{
    await _service.ProcessAsync(); // a exceção derruba o processo direto
}

// async Task — assíncrono em toda a cadeia
public async Task<ActionResult<Data>> Get(int id)
{
    var data = await _service.GetDataAsync(id);
    return Ok(data);
}
```

### ConfigureAwait(false) para código de biblioteca

```csharp
// Código de biblioteca capturando o SynchronizationContext sem necessidade
public class LibraryService
{
    public async Task<string> GetDataAsync()
    {
        var response = await _httpClient.GetAsync("/api/data");
        return await response.Content.ReadAsStringAsync();
    }
}

// Código de biblioteca usando ConfigureAwait(false) para evitar deadlock
public class LibraryService
{
    public async Task<string> GetDataAsync()
    {
        var response = await _httpClient.GetAsync("/api/data").ConfigureAwait(false);
        return await response.Content.ReadAsStringAsync().ConfigureAwait(false);
    }
}
```

### Propagação do CancellationToken

```csharp
// Descartando o CancellationToken
public async Task<List<User>> SearchAsync(string query)
{
    return await _db.Users.Where(u => u.Name.Contains(query)).ToListAsync();
}

// Propagando o CancellationToken por toda a cadeia
public async Task<List<User>> SearchAsync(string query, CancellationToken ct = default)
{
    return await _db.Users
        .Where(u => u.Name.Contains(query))
        .ToListAsync(ct);
}
```

### Async Disposal

```csharp
// Dispose síncrono de recurso assíncrono
public class DataClient : IDisposable
{
    public void Dispose()
    {
        _httpClient.Dispose(); // pode descartar uma requisição em andamento
    }
}

// IAsyncDisposable
public class DataClient : IAsyncDisposable
{
    public async ValueTask DisposeAsync()
    {
        await _stream.DisposeAsync();
    }
}

// O chamador usa await using
await using var client = new DataClient();
```

---

## Performance do EF Core

### Problema de consulta N+1

```csharp
// N+1 clássico — cada Blog dispara uma consulta para buscar os Posts
foreach (var blog in await context.Blogs.ToListAsync())
{
    foreach (var post in blog.Posts) // a cada iteração consulta o banco de dados!
    {
        Console.WriteLine(post.Title);
    }
}

// Eager Loading + projeção
await foreach (var blog in context.Blogs
    .Select(b => new { b.Url, b.Posts })
    .AsAsyncEnumerable())
{
    foreach (var post in blog.Posts)
        Console.WriteLine(post.Title);
}
```

### Busca excessiva (sem projeção)

```csharp
// Carrega todas as colunas — quando só precisa de Url, carrega todos os campos
var urls = await context.Blogs.ToListAsync();

// Projeta apenas os campos necessários
var urls = await context.Blogs
    .Select(b => b.Url)
    .ToListAsync();
```

### Falta de paginação

```csharp
// Conjunto de resultados sem limite
var posts = await context.Posts
    .Where(p => p.Title.StartsWith("A"))
    .ToListAsync(); // pode ter milhões de registros!

// Limita a quantidade de resultados
var posts = await context.Posts
    .Where(p => p.Title.StartsWith("A"))
    .OrderBy(p => p.Id)
    .Skip((page - 1) * pageSize)
    .Take(pageSize)
    .ToListAsync();
```

### Cartesian Explosion (explosão cartesiana de JOIN)

```csharp
// Múltiplos Include criam uma grande quantidade de dados duplicados
var blogs = await context.Blogs
    .Include(b => b.Posts)
    .Include(b => b.Tags)
    .ToListAsync(); // os dados do Blog se repetem em cada linha

// Use AsSplitQuery para dividir a consulta
var blogs = await context.Blogs
    .Include(b => b.Posts)
    .Include(b => b.Tags)
    .AsSplitQuery()
    .ToListAsync();
```

### Falta de AsNoTracking em cenários somente leitura

```csharp
// Rastreamento padrão — consultas somente leitura também pagam o custo do rastreamento de mudanças
var products = await context.Products.ToListAsync();

// AsNoTracking — pula o rastreamento de mudanças, mais rápido e mais econômico em memória
var products = await context.Products
    .AsNoTracking()
    .ToListAsync();
```

### Funções em colunas impedem o uso de índices

```csharp
// Consegue usar o índice — sargable
var posts1 = await context.Posts
    .Where(p => p.Title.StartsWith("A"))
    .ToListAsync();

// Não consegue usar o índice — table scan completo
var posts2 = await context.Posts
    .Where(p => p.Title.EndsWith("A"))
    .ToListAsync();

// Função aplicada sobre a coluna — table scan completo
var posts3 = await context.Posts
    .Where(p => p.Title.ToLower() == "foo")
    .ToListAsync();
```

### Acesso síncrono vs. assíncrono ao banco de dados

```csharp
// Chamada síncrona ao banco de dados — bloqueia a thread
var products = context.Products.ToList();
context.SaveChanges();

// Chamada assíncrona ao banco de dados
var products = await context.Products.ToListAsync();
await context.SaveChangesAsync();
```

---

## Boas Práticas do ASP.NET Core

### Uso incorreto de HttpClient

```csharp
// Criar um novo HttpClient em cada requisição — esgotamento de sockets
using var client = new HttpClient();
var response = await client.GetAsync("https://api.example.com/data");

// Injeção via IHttpClientFactory
public class MyService
{
    private readonly HttpClient _client;
    public MyService(HttpClient client) => _client = client; // injetado pela factory
}
```

### Uso de HttpContext em thread em segundo plano

```csharp
// Capturar um serviço scoped em uma tarefa em segundo plano — já foi liberado após o fim da requisição
_ = Task.Run(async () =>
{
    await context.SaveChangesAsync(); // ObjectDisposedException!
});

// Crie um novo scope
_ = Task.Run(async () =>
{
    await using var scope = serviceScopeFactory.CreateAsyncScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.SaveChangesAsync();
});
```

### Acesso síncrono a Request.Form

```csharp
// Leitura síncrona de Form — sync over async
var form = HttpContext.Request.Form;

// Leitura assíncrona
var form = await HttpContext.Request.ReadFormAsync();
```

### Exceções usadas para controle de fluxo

```csharp
// Usar exceção para verificar existência — exceções têm custo alto, muito mais lento que uma verificação direta
try
{
    var user = await _db.Users.FirstAsync(u => u.Id == id);
}
catch (InvalidOperationException)
{
    return NotFound();
}

// Use verificação em vez de exceção
var user = await _db.Users.FirstOrDefaultAsync(u => u.Id == id);
if (user is null) return NotFound();
```

### Cabeçalhos de resposta definidos após o Body

```csharp
// Definir o header depois que o body já foi enviado — lança exceção
await next(context);
context.Response.Headers["X-Custom"] = "value"; // pode lançar exceção!

// Use o callback OnStarting
context.Response.OnStarting(() =>
{
    context.Response.Headers["X-Custom"] = "value";
    return Task.CompletedTask;
});
await next(context);
```

---

## Injeção de Dependência

### Serviço Scoped injetado em Singleton

```csharp
// Serviço Scoped injetado em Singleton — incompatibilidade de tempo de vida (lifetime)
services.AddSingleton<BackgroundWorker>();
services.AddScoped<IUserRepository, UserRepository>();

// BackgroundWorker é Singleton, UserRepository é Scoped
// → UserRepository fica compartilhado entre requisições ou já foi liberado

// Crie um scope dentro do Singleton via IServiceProvider
public class BackgroundWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;

    public BackgroundWorker(IServiceScopeFactory scopeFactory)
        => _scopeFactory = scopeFactory;

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await using var scope = _scopeFactory.CreateAsyncScope();
        var repo = scope.ServiceProvider.GetRequiredService<IUserRepository>();
    }
}
```

---

## Boas Práticas de LINQ

### LINQ aplicado depois de ToList

```csharp
// ToList primeiro, filtro depois — carrega a tabela inteira na memória
var results = context.Posts
    .Where(p => p.Title.StartsWith("A"))
    .ToList()
    .Where(p => SomeClientFilter(p)); // filtro no cliente, todas as linhas já foram carregadas

// Deixe o banco de dados executar o filtro sempre que possível
var results = await context.Posts
    .Where(p => p.Title.StartsWith("A") && SomeDbFilter(p))
    .AsAsyncEnumerable()
    .Where(p => SomeClientFilter(p)) // filtra apenas as linhas retornadas pelo banco
    .ToListAsync();
```

### Count() vs Any()

```csharp
// Count() executa a consulta completa
if (context.Users.Count() > 0) { /* ... */ }

// Any() é mais eficiente — retorna ao encontrar o primeiro registro
if (await context.Users.AnyAsync()) { /* ... */ }
```

### Enumeração múltipla de IEnumerable

```csharp
// O IEnumerable é enumerado duas vezes
public void Process(IEnumerable<int> numbers)
{
    if (numbers.Any()) // primeira enumeração
    {
        foreach (var n in numbers) // segunda enumeração (pode ser uma nova consulta)
        {
            Console.WriteLine(n);
        }
    }
}

// Se precisar usar várias vezes, materialize antes
public void Process(IEnumerable<int> numbers)
{
    var list = numbers.ToList(); // enumera apenas uma vez
    if (list.Any())
    {
        foreach (var n in list)
        {
            Console.WriteLine(n);
        }
    }
}
```

### Efeitos colaterais dentro de Select

```csharp
// Executar efeito colateral dentro de Select — momento de execução imprevisível
var results = users.Select(u =>
{
    _logger.LogInformation($"Processing {u.Name}"); // efeito colateral!
    return u.Email;
}).ToList();

// Coloque o efeito colateral dentro de um foreach
foreach (var user in users)
{
    _logger.LogInformation("Processing {Name}", user.Name);
}
var results = users.Select(u => u.Email).ToList();
```

---

## Checklist de Revisão

### Novidades do C# 12

- [ ] Parâmetros do primary constructor não são reatribuídos
- [ ] Sintaxe de collection expressions consistente (não mistura estilo novo e antigo)

### Programação Assíncrona

- [ ] Sem `Task.Wait()`, `.Result`, `async void`
- [ ] Código de biblioteca usa `ConfigureAwait(false)`
- [ ] `CancellationToken` propagado por toda a cadeia
- [ ] Recursos assíncronos usam `IAsyncDisposable` / `await using`
- [ ] Não mistura acesso a dados síncrono e assíncrono

### EF Core

- [ ] Sem consultas N+1 (propriedade de navegação acessada dentro de loop)
- [ ] Projeção com `Select()` evita busca excessiva
- [ ] Paginação: `Take()`/`Skip()` antes de `ToListAsync()`
- [ ] Múltiplos `Include()` usam `AsSplitQuery()`
- [ ] Consultas somente leitura usam `AsNoTracking()`
- [ ] Sem chamadas de função em colunas que impeçam o uso de índices
- [ ] Todas as chamadas ao banco de dados são assíncronas

### ASP.NET Core

- [ ] HttpClient obtido via `IHttpClientFactory`
- [ ] Serviços scoped não são usados diretamente em tarefas em segundo plano
- [ ] Uso de `ReadFormAsync` em vez de `Request.Form`
- [ ] Exceções não usadas para controle de fluxo
- [ ] Cabeçalhos de resposta definidos via `OnStarting`

### Injeção de Dependência

- [ ] Serviço Scoped não é injetado em Singleton
- [ ] Tarefas em segundo plano criam um novo scope

### LINQ

- [ ] Sem `ToList()` desnecessário seguido de LINQ
- [ ] `Any()` em vez de `Count() > 0`
- [ ] IEnumerable não é enumerado múltiplas vezes (ou é materializado antes)
- [ ] Sem efeitos colaterais dentro de Select
