# Guia de Revisão de Código Go

Checklist de revisão de código baseado no guia oficial do Go, no Effective Go e nas melhores práticas da comunidade.

## Índice

- [Checklist Rápido de Revisão](#checklist-rápido-de-revisão)
- [1. Tratamento de Erros](#1-tratamento-de-erros)
- [2. Concorrência e Goroutines](#2-concorrência-e-goroutines)
- [3. Uso do Context](#3-uso-do-context)
- [4. Design de Interfaces](#4-design-de-interfaces)
- [5. Escolha do Tipo de Receiver](#5-escolha-do-tipo-de-receiver)
- [6. Otimização de Performance](#6-otimização-de-performance)
- [7. Testes](#7-testes)
- [8. Armadilhas Comuns](#8-armadilhas-comuns)
- [9. Organização do Código](#9-organização-do-código)
- [10. Ferramentas e Verificações](#10-ferramentas-e-verificações)
- [Recursos de Referência](#recursos-de-referência)

## Checklist Rápido de Revisão

### Itens obrigatórios
- [ ] Os erros são tratados corretamente (sem ignorar, com contexto)
- [ ] As goroutines têm mecanismo de saída (evitar vazamentos)
- [ ] O context é propagado e cancelado corretamente
- [ ] A escolha do tipo de receiver é adequada (valor/ponteiro)
- [ ] O código está formatado com `gofmt`

### Problemas frequentes
- [ ] Captura de variável de loop (Go < 1.22)
- [ ] Verificações de nil estão completas
- [ ] O map é inicializado antes de ser usado
- [ ] Uso de defer dentro de loops
- [ ] Sombreamento de variáveis (shadowing)

---

## 1. Tratamento de Erros

### 1.1 Nunca ignore erros

```go
// Errado: ignora o erro
result, _ := SomeFunction()

// Correto: trata o erro
result, err := SomeFunction()
if err != nil {
    return fmt.Errorf("some function failed: %w", err)
}
```

### 1.2 Encapsulamento de erro com contexto

```go
// Errado: perde o contexto
if err != nil {
    return err
}

// Errado: usar %v perde a cadeia de erros
if err != nil {
    return fmt.Errorf("failed: %v", err)
}

// Correto: usar %w preserva a cadeia de erros
if err != nil {
    return fmt.Errorf("failed to process user %d: %w", userID, err)
}
```

### 1.3 Use errors.Is e errors.As

```go
// Errado: comparação direta (não funciona com erros encapsulados)
if err == sql.ErrNoRows {
    // ...
}

// Correto: usar errors.Is (suporta cadeia de erros)
if errors.Is(err, sql.ErrNoRows) {
    return nil, ErrNotFound
}

// Correto: usar errors.As para extrair um tipo específico
var pathErr *os.PathError
if errors.As(err, &pathErr) {
    log.Printf("path error: %s", pathErr.Path)
}
```

### 1.4 Tipos de erro personalizados

```go
// Recomendado: definir erros sentinela
var (
    ErrNotFound     = errors.New("not found")
    ErrUnauthorized = errors.New("unauthorized")
)

// Recomendado: erro personalizado com contexto
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation error on %s: %s", e.Field, e.Message)
}
```

### 1.5 Trate o erro apenas uma vez

```go
// Errado: registra em log e retorna (tratamento duplicado)
if err != nil {
    log.Printf("error: %v", err)
    return err
}

// Correto: apenas retorna, deixando o chamador decidir
if err != nil {
    return fmt.Errorf("operation failed: %w", err)
}

// Ou: apenas registra em log e trata (sem retornar)
if err != nil {
    log.Printf("non-critical error: %v", err)
    // continua executando a lógica alternativa
}
```

---

## 2. Concorrência e Goroutines

### 2.1 Evite vazamento de Goroutines

```go
// Errado: a goroutine nunca consegue terminar
func bad() {
    ch := make(chan int)
    go func() {
        val := <-ch // bloqueia para sempre, ninguém envia
        fmt.Println(val)
    }()
    // a função retorna, a goroutine vaza
}

// Correto: usar context ou um done channel
func good(ctx context.Context) {
    ch := make(chan int)
    go func() {
        select {
        case val := <-ch:
            fmt.Println(val)
        case <-ctx.Done():
            return // saída graciosa
        }
    }()
}
```

### 2.2 Boas práticas no uso de Channels

```go
// Errado: enviar para um channel nil (bloqueia permanentemente)
var ch chan int
ch <- 1 // bloqueia permanentemente

// Errado: enviar para um channel já fechado (panic)
close(ch)
ch <- 1 // panic!

// Correto: o emissor é responsável por fechar o channel
func producer(ch chan<- int) {
    defer close(ch) // o emissor é responsável por fechar
    for i := 0; i < 10; i++ {
        ch <- i
    }
}

// Correto: o receptor detecta o fechamento
for val := range ch {
    process(val)
}
// ou
val, ok := <-ch
if !ok {
    // o channel já foi fechado
}
```

### 2.3 Use sync.WaitGroup

```go
// Errado: Add chamado dentro da goroutine
var wg sync.WaitGroup
for i := 0; i < 10; i++ {
    go func() {
        wg.Add(1) // condição de corrida!
        defer wg.Done()
        work()
    }()
}
wg.Wait()

// Correto: Add chamado antes de iniciar a goroutine
var wg sync.WaitGroup
for i := 0; i < 10; i++ {
    wg.Add(1)
    go func() {
        defer wg.Done()
        work()
    }()
}
wg.Wait()
```

### 2.4 Evite capturar a variável de loop (Go < 1.22)

```go
// Errado (Go < 1.22): captura a variável de loop
for _, item := range items {
    go func() {
        process(item) // todas as goroutines podem usar o mesmo item
    }()
}

// Correto: passar como argumento
for _, item := range items {
    go func(it Item) {
        process(it)
    }(item)
}

// Go 1.22+: o comportamento padrão já foi corrigido, cada iteração cria uma nova variável
```

### 2.5 Padrão Worker Pool

```go
// Recomendado: limitar o número de goroutines concorrentes
func processWithWorkerPool(ctx context.Context, items []Item, workers int) error {
    jobs := make(chan Item, len(items))
    results := make(chan error, len(items))

    // inicia os workers
    for w := 0; w < workers; w++ {
        go func() {
            for item := range jobs {
                results <- process(item)
            }
        }()
    }

    // envia as tarefas
    for _, item := range items {
        jobs <- item
    }
    close(jobs)

    // coleta os resultados
    for range items {
        if err := <-results; err != nil {
            return err
        }
    }
    return nil
}
```

---

## 3. Uso do Context

### 3.1 Context como primeiro parâmetro

```go
// Errado: context não é o primeiro parâmetro
func Process(data []byte, ctx context.Context) error

// Errado: context armazenado em uma struct
type Service struct {
    ctx context.Context // não faça isso!
}

// Correto: context como primeiro parâmetro, nomeado ctx
func Process(ctx context.Context, data []byte) error
```

### 3.2 Propague em vez de criar um novo Context raiz

```go
// Errado: cria um novo context raiz dentro da cadeia de chamadas
func middleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        ctx := context.Background() // perde o context da requisição!
        process(ctx)
        next.ServeHTTP(w, r)
    })
}

// Correto: obtém a partir da requisição e propaga
func middleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        ctx := r.Context()
        ctx = context.WithValue(ctx, key, value)
        process(ctx)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

### 3.3 Sempre chame a função cancel

```go
// Errado: cancel não é chamado
ctx, cancel := context.WithTimeout(parentCtx, 5*time.Second)
// falta a chamada a cancel(), pode haver vazamento de recursos

// Correto: usar defer para garantir a chamada
ctx, cancel := context.WithTimeout(parentCtx, 5*time.Second)
defer cancel() // deve ser chamado mesmo em caso de timeout
```

### 3.4 Responda ao cancelamento do Context

```go
// Recomendado: verificar o context em operações de longa duração
func LongRunningTask(ctx context.Context) error {
    for {
        select {
        case <-ctx.Done():
            return ctx.Err() // retorna context.Canceled ou context.DeadlineExceeded
        default:
            // executa uma pequena parte do trabalho
            if err := doChunk(); err != nil {
                return err
            }
        }
    }
}
```

### 3.5 Diferencie a causa do cancelamento

```go
// Diferencia a causa do cancelamento com base em ctx.Err()
if err := ctx.Err(); err != nil {
    switch {
    case errors.Is(err, context.Canceled):
        log.Println("operation was canceled")
    case errors.Is(err, context.DeadlineExceeded):
        log.Println("operation timed out")
    }
    return err
}
```

---

## 4. Design de Interfaces

### 4.1 Aceite interfaces, retorne structs

```go
// Não recomendado: aceita um tipo concreto
func SaveUser(db *sql.DB, user User) error

// Recomendado: aceita uma interface (desacoplamento, facilita testes)
type UserStore interface {
    Save(ctx context.Context, user User) error
}

func SaveUser(store UserStore, user User) error

// Não recomendado: retorna uma interface
func NewUserService() UserServiceInterface

// Recomendado: retorna um tipo concreto
func NewUserService(store UserStore) *UserService
```

### 4.2 Defina a interface no lado do consumidor

```go
// Não recomendado: definir a interface no pacote de implementação
// package database
type Database interface {
    Query(ctx context.Context, query string) ([]Row, error)
    // ... 20 métodos
}

// Recomendado: definir, no pacote consumidor, a interface mínima necessária
// package userservice
type UserQuerier interface {
    QueryUsers(ctx context.Context, filter Filter) ([]User, error)
}
```

### 4.3 Mantenha as interfaces pequenas e focadas

```go
// Não recomendado: interface grande e genérica
type Repository interface {
    GetUser(id int) (*User, error)
    CreateUser(u *User) error
    UpdateUser(u *User) error
    DeleteUser(id int) error
    GetOrder(id int) (*Order, error)
    CreateOrder(o *Order) error
    // ... mais métodos
}

// Recomendado: interfaces pequenas e focadas
type UserReader interface {
    GetUser(ctx context.Context, id int) (*User, error)
}

type UserWriter interface {
    CreateUser(ctx context.Context, u *User) error
    UpdateUser(ctx context.Context, u *User) error
}

// composição de interfaces
type UserRepository interface {
    UserReader
    UserWriter
}
```

### 4.4 Evite o uso excessivo de interfaces vazias

```go
// Não recomendado: uso excessivo de interface{}
func Process(data interface{}) interface{}

// Recomendado: usar generics (Go 1.18+)
func Process[T any](data T) T

// Recomendado: definir uma interface concreta
type Processor interface {
    Process() Result
}
```

---

## 5. Escolha do Tipo de Receiver

### 5.1 Quando usar receiver por ponteiro

```go
// Quando é necessário modificar o receiver
func (u *User) SetName(name string) {
    u.Name = name
}

// Quando o receiver contém primitivas de sincronização como sync.Mutex
type SafeCounter struct {
    mu    sync.Mutex
    count int
}

func (c *SafeCounter) Inc() {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.count++
}

// Quando o receiver é uma struct grande (evita o custo de cópia)
type LargeStruct struct {
    Data [1024]byte
    // ...
}

func (l *LargeStruct) Process() { /* ... */ }
```

### 5.2 Quando usar receiver por valor

```go
// Quando o receiver é uma struct pequena e imutável
type Point struct {
    X, Y float64
}

func (p Point) Distance(other Point) float64 {
    return math.Sqrt(math.Pow(p.X-other.X, 2) + math.Pow(p.Y-other.Y, 2))
}

// Quando o receiver é um alias de um tipo básico
type Counter int

func (c Counter) String() string {
    return fmt.Sprintf("%d", c)
}

// Quando o receiver é map, func ou chan (que já são tipos de referência)
type StringSet map[string]struct{}

func (s StringSet) Contains(key string) bool {
    _, ok := s[key]
    return ok
}
```

### 5.3 Princípio da consistência

```go
// Não recomendado: misturar tipos de receiver
func (u User) GetName() string   // receiver por valor
func (u *User) SetName(n string) // receiver por ponteiro

// Recomendado: se algum método precisar de receiver por ponteiro, use ponteiro em todos
func (u *User) GetName() string { return u.Name }
func (u *User) SetName(n string) { u.Name = n }
```

---

## 6. Otimização de Performance

### 6.1 Pré-aloque Slices

```go
// Não recomendado: crescimento dinâmico
var result []int
for i := 0; i < 10000; i++ {
    result = append(result, i) // múltiplas alocações e cópias
}

// Recomendado: pré-alocar quando o tamanho é conhecido
result := make([]int, 0, 10000)
for i := 0; i < 10000; i++ {
    result = append(result, i)
}

// Ou inicializar diretamente
result := make([]int, 10000)
for i := 0; i < 10000; i++ {
    result[i] = i
}
```

### 6.2 Evite alocações desnecessárias no heap

```go
// Pode escapar para o heap
func NewUser() *User {
    return &User{} // escapa para o heap
}

// Considere retornar por valor (quando aplicável)
func NewUser() User {
    return User{} // pode ser alocado na stack
}

// verificar a análise de escape
// go build -gcflags '-m -m' ./...
```

### 6.3 Use sync.Pool para reutilizar objetos

```go
// Recomendado: objetos criados/destruídos com alta frequência devem usar sync.Pool
var bufferPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

func ProcessData(data []byte) string {
    buf := bufferPool.Get().(*bytes.Buffer)
    defer func() {
        buf.Reset()
        bufferPool.Put(buf)
    }()

    buf.Write(data)
    return buf.String()
}
```

### 6.4 Otimização de concatenação de strings

```go
// Não recomendado: usar + em loop para concatenar
var result string
for _, s := range strings {
    result += s // cria uma nova string a cada iteração
}

// Recomendado: usar strings.Builder
var builder strings.Builder
for _, s := range strings {
    builder.WriteString(s)
}
result := builder.String()

// Ou usar strings.Join
result := strings.Join(strings, "")
```

### 6.5 Evite o custo de conversão de interface{}

```go
// Usar interface{} no caminho crítico (hot path)
func process(data interface{}) {
    switch v := data.(type) { // a asserção de tipo tem custo
    case int:
        // ...
    }
}

// Usar generics ou tipos concretos no caminho crítico
func process[T int | int64 | float64](data T) {
    // o tipo é determinado em tempo de compilação, sem custo em tempo de execução
}
```

---

## 7. Testes

### 7.1 Testes orientados a tabela (table-driven)

```go
// Recomendado: testes orientados a tabela
func TestAdd(t *testing.T) {
    tests := []struct {
        name     string
        a, b     int
        expected int
    }{
        {"positive numbers", 1, 2, 3},
        {"with zero", 0, 5, 5},
        {"negative numbers", -1, -2, -3},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := Add(tt.a, tt.b)
            if result != tt.expected {
                t.Errorf("Add(%d, %d) = %d; want %d",
                    tt.a, tt.b, result, tt.expected)
            }
        })
    }
}
```

### 7.2 Testes em paralelo

```go
// Recomendado: executar casos de teste independentes em paralelo
func TestParallel(t *testing.T) {
    tests := []struct {
        name  string
        input string
    }{
        {"test1", "input1"},
        {"test2", "input2"},
    }

    for _, tt := range tests {
        tt := tt // necessário copiar em Go < 1.22
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel() // marca como executável em paralelo
            result := Process(tt.input)
            // assertions...
        })
    }
}
```

### 7.3 Use interfaces para Mock

```go
// Defina uma interface para facilitar os testes
type EmailSender interface {
    Send(to, subject, body string) error
}

// implementação de produção
type SMTPSender struct { /* ... */ }

// mock de teste
type MockEmailSender struct {
    SendFunc func(to, subject, body string) error
}

func (m *MockEmailSender) Send(to, subject, body string) error {
    return m.SendFunc(to, subject, body)
}

func TestUserRegistration(t *testing.T) {
    mock := &MockEmailSender{
        SendFunc: func(to, subject, body string) error {
            if to != "test@example.com" {
                t.Errorf("unexpected recipient: %s", to)
            }
            return nil
        },
    }

    service := NewUserService(mock)
    // test...
}
```

### 7.4 Funções auxiliares de teste

```go
// Use t.Helper() para marcar funções auxiliares
func assertEqual(t *testing.T, got, want interface{}) {
    t.Helper() // exibe a posição do chamador ao reportar o erro
    if got != want {
        t.Errorf("got %v, want %v", got, want)
    }
}

// Use t.Cleanup() para limpar recursos
func TestWithTempFile(t *testing.T) {
    f, err := os.CreateTemp("", "test")
    if err != nil {
        t.Fatal(err)
    }
    t.Cleanup(func() {
        os.Remove(f.Name())
    })
    // test...
}
```

---

## 8. Armadilhas Comuns

### 8.1 Nil Slice vs Slice Vazio

```go
var nilSlice []int     // nil, len=0, cap=0
emptySlice := []int{}  // não é nil, len=0, cap=0
made := make([]int, 0) // não é nil, len=0, cap=0

// Diferença na codificação JSON
json.Marshal(nilSlice)   // null
json.Marshal(emptySlice) // []

// Recomendado: inicializar explicitamente quando for necessário um array vazio no JSON
if slice == nil {
    slice = []int{}
}
```

### 8.2 Inicialização de Map

```go
// Errado: map não inicializado
var m map[string]int
m["key"] = 1 // panic: assignment to entry in nil map

// Correto: inicializar com make
m := make(map[string]int)
m["key"] = 1

// Ou usar um literal
m := map[string]int{}
```

### 8.3 Defer dentro de loops

```go
// Problema potencial: o defer só é executado ao final da função
func processFiles(files []string) error {
    for _, file := range files {
        f, err := os.Open(file)
        if err != nil {
            return err
        }
        defer f.Close() // todos os arquivos só são fechados ao final da função!
        // process...
    }
    return nil
}

// Correto: usar um closure ou extrair em uma função
func processFiles(files []string) error {
    for _, file := range files {
        if err := processFile(file); err != nil {
            return err
        }
    }
    return nil
}

func processFile(file string) error {
    f, err := os.Open(file)
    if err != nil {
        return err
    }
    defer f.Close()
    // process...
    return nil
}
```

### 8.4 Compartilhamento do array subjacente em Slices

```go
// Problema potencial: slices compartilham o array subjacente
original := []int{1, 2, 3, 4, 5}
slice := original[1:3] // [2, 3]
slice[0] = 100         // modificou o original!
// original passa a ser [1, 100, 3, 4, 5]

// Correto: copiar explicitamente quando for necessária uma cópia independente
slice := make([]int, 2)
copy(slice, original[1:3])
slice[0] = 100 // não afeta o original
```

### 8.5 Vazamento de memória em substrings

```go
// Problema potencial: a substring retém todo o array subjacente
func getPrefix(s string) string {
    return s[:10] // ainda referencia todo o array subjacente de s
}

// Correto: criar uma cópia independente (Go 1.18+)
func getPrefix(s string) string {
    return strings.Clone(s[:10])
}

// Antes do Go 1.18
func getPrefix(s string) string {
    return string([]byte(s[:10]))
}
```

### 8.6 Armadilha do Nil em Interfaces

```go
// Armadilha: verificação de nil em interface
type MyError struct{}
func (e *MyError) Error() string { return "error" }

func returnsError() error {
    var e *MyError = nil
    return e // o error retornado não é nil!
}

func main() {
    err := returnsError()
    if err != nil { // true! interface{type: *MyError, value: nil}
        fmt.Println("error:", err)
    }
}

// Correto: retornar nil explicitamente
func returnsError() error {
    var e *MyError = nil
    if e == nil {
        return nil // retorna nil explicitamente
    }
    return e
}
```

### 8.7 Comparação de Time

```go
// Não recomendado: usar == diretamente para comparar time.Time
if t1 == t2 { // pode falhar devido a diferenças no relógio monotônico
    // ...
}

// Recomendado: usar o método Equal
if t1.Equal(t2) {
    // ...
}

// Comparar intervalos de tempo
if t1.Before(t2) || t1.After(t2) {
    // ...
}
```

---

## 9. Organização do Código

### 9.1 Nomenclatura de pacotes

```go
// Não recomendado
package common   // excessivamente genérico
package utils    // excessivamente genérico
package helpers  // excessivamente genérico
package models   // agrupado por tipo

// Recomendado: nomear por funcionalidade
package user     // funcionalidades relacionadas a usuário
package order    // funcionalidades relacionadas a pedido
package postgres // implementação do PostgreSQL
```

### 9.2 Evite dependências circulares

```go
// Dependência circular
// package a importa package b
// package b importa package a

// Solução 1: extrair tipos compartilhados para um pacote independente
// package types (tipos compartilhados)
// package a importa types
// package b importa types

// Solução 2: usar interfaces para desacoplar
// package a define a interface
// package b implementa a interface
```

### 9.3 Convenções de identificadores exportados

```go
// Exporte apenas os identificadores necessários
type UserService struct {
    db *sql.DB // privado
}

func (s *UserService) GetUser(id int) (*User, error) // público
func (s *UserService) validate(u *User) error         // privado

// Pacotes internal restringem o acesso
// internal/database/... só pode ser importado por código do mesmo projeto
```

---

## 10. Ferramentas e Verificações

### 10.1 Ferramentas obrigatórias

```bash
# Formatação (obrigatório)
gofmt -w .
goimports -w .

# Análise estática
go vet ./...

# Detecção de condição de corrida
go test -race ./...

# Análise de escape
go build -gcflags '-m -m' ./...
```

### 10.2 Linters recomendados

```bash
# golangci-lint (integra múltiplos linters)
golangci-lint run

# verificações comuns
# - errcheck: verifica erros não tratados
# - gosec: verificação de segurança
# - ineffassign: atribuições sem efeito
# - staticcheck: análise estática
# - unused: código não utilizado
```

### 10.3 Testes de Benchmark

```go
// Teste de benchmark de performance
func BenchmarkProcess(b *testing.B) {
    data := prepareData()
    b.ResetTimer() // reinicia o cronômetro

    for i := 0; i < b.N; i++ {
        Process(data)
    }
}

// executar o benchmark
// go test -bench=. -benchmem ./...
```

---

## Recursos de Referência

- [Effective Go](https://go.dev/doc/effective_go)
- [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments)
- [Go Common Mistakes](https://go.dev/wiki/CommonMistakes)
- [100 Go Mistakes](https://100go.co/)
- [Go Proverbs](https://go-proverbs.github.io/)
- [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md)
