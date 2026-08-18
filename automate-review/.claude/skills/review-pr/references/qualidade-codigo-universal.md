# Anti-Padrões Universais de Qualidade de Código

> Guia de anti-padrões de qualidade de código independente de linguagem, cobrindo reuso de código, abstração com vazamento, explosão de parâmetros, condicionais aninhadas, tipagem por string (stringly-typed), TOCTOU, atualizações sem efeito (no-op) e outros temas centrais. Aplicável à revisão de PR em qualquer linguagem.

## Índice

- [Revisão de Reuso de Código](#revisão-de-reuso-de-código)
- [Explosão de Parâmetros](#explosão-de-parâmetros)
- [Abstração com Vazamento](#abstração-com-vazamento)
- [Tipagem por String](#tipagem-por-string)
- [Expressões Condicionais Aninhadas](#expressões-condicionais-aninhadas)
- [Variantes de Copiar e Colar](#variantes-de-copiar-e-colar)
- [Atualizações Sem Efeito](#atualizações-sem-efeito)
- [Condição de Corrida TOCTOU](#condição-de-corrida-toctou)
- [Operações Excessivamente Amplas](#operações-excessivamente-amplas)
- [Estado Redundante](#estado-redundante)
- [Checklist Geral de Qualidade](#checklist-geral-de-qualidade)

---

## Revisão de Reuso de Código

Antes de aceitar código novo, procure na base de código existente por utilitários reutilizáveis.

### Procure funções utilitárias existentes

```python
# Lógica de concatenação de caminho recém-escrita — o projeto já tem PathBuilder
def get_config_path(name):
    base = os.environ.get("APP_ROOT", ".")
    return os.path.join(base, "config", name + ".json")

# Usa o PathBuilder existente
def get_config_path(name):
    return PathBuilder.config(f"{name}.json")
```

```javascript
// Debounce escrito manualmente — o projeto já tem lodash ou utils/debounce.ts
function debounce(fn, ms) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

// Usa a função utilitária existente
import { debounce } from "@/utils/debounce";
```

**Pontos de atenção na revisão:**
- A nova função tem o mesmo nome ou sobrepõe funcionalidade com algum utilitário já existente?
- A lógica inline poderia ser extraída para uma chamada a um módulo já existente?
- Verifique arquivos vizinhos e o diretório shared/utils

---

## Explosão de Parâmetros

### Parâmetros de função que só crescem

```python
# Cada novo requisito adiciona um parâmetro
def create_user(name, email, role, team, active, avatar_url, timezone):
    ...

# Usa um objeto de configuração / dataclass
@dataclass
class CreateUserParams:
    name: str
    email: str
    role: Role = Role.MEMBER
    team: str | None = None
    active: bool = True
    avatar_url: str | None = None
    timezone: str = "UTC"

def create_user(params: CreateUserParams) -> User:
    ...
```

```typescript
// 6+ parâmetros posicionais
function renderWidget(
  title: string, width: number, height: number,
  theme: string, collapsible: boolean, icon: string
) { ... }

// Padrão de objeto de opções (options object pattern)
interface WidgetOptions {
  title: string;
  width?: number;
  height?: number;
  theme?: "light" | "dark";
  collapsible?: boolean;
  icon?: string;
}
function renderWidget(options: WidgetOptions) { ... }
```

**Pontos de atenção na revisão:**
- A função tem ≥ 4 parâmetros? Considere um options object / dataclass
- O novo parâmetro é apenas um sinalizador booleano? Considere um enum ou strategy pattern
- Existem parâmetros mutuamente exclusivos como `enable_x`, `disable_y`?

---

## Abstração com Vazamento

### Expondo detalhes internos de implementação

```python
# Retorna objeto ORM interno — o chamador é forçado a conhecer SQLAlchemy
def get_users():
    return session.query(User).filter(User.active == True).all()

# Retorna objeto de domínio, ocultando a camada de persistência
def get_active_users() -> list[UserDTO]:
    rows = user_repo.find_active()
    return [UserDTO.from_row(r) for r in rows]
```

```typescript
// Componente recebe a estrutura bruta da resposta da API
<UserCard user={apiResponse.data.results[0]} />

// Componente recebe tipo de domínio, o adapter lida com o mapeamento
interface UserSummary {
  displayName: string;
  avatarUrl: string;
}
<UserCard user={adaptUser(apiResponse)} />
```

**Pontos de atenção na revisão:**
- O tipo de retorno da função expõe a implementação subjacente (ORM, cliente HTTP, formato de arquivo)?
- O componente/função depende da estrutura de dados de um sistema externo?
- Isso quebra um limite de abstração já existente?

---

## Tipagem por String

### Usando strings brutas em vez de constantes/enums

```python
# Magic strings espalhadas por todo lugar
if status == "active":
    ...
if role == "admin":
    ...

# Usa enum
class Status(StrEnum):
    ACTIVE = "active"
    SUSPENDED = "suspended"
    ARCHIVED = "archived"

if user.status == Status.ACTIVE:
    ...
```

```typescript
// Nomes de evento como string bruta — um erro de digitação não gera erro
emitter.emit("userCreated", data);
emitter.on("usercreated", handler); // bug: erro de digitação (typo)

// Constantes ou branded type
const Events = {
  USER_CREATED: "userCreated",
  USER_SUSPENDED: "userSuspended",
} as const;
emitter.emit(Events.USER_CREATED, data);
```

**Pontos de atenção na revisão:**
- Strings estão sendo usadas em vez de um enum/union type já existente?
- Nomes de evento, action type ou valores de status estão espalhados em vários arquivos?
- A comparação de string é case-sensitive mas isso não foi validado?

---

## Expressões Condicionais Aninhadas

### Cadeias de ternários e if/else aninhados

```python
# Cadeia de ternários difícil de ler
label = (
    "Admin" if role == "admin" else
    "Manager" if role == "manager" else
    "Viewer" if role == "viewer" else
    "Unknown"
)

# Tabela de consulta (lookup table) ou match
ROLE_LABELS = {
    "admin": "Admin",
    "manager": "Manager",
    "viewer": "Viewer",
}
label = ROLE_LABELS.get(role, "Unknown")
```

```typescript
// Ternário aninhado
const bg = isHovered
  ? isSelected ? "blue" : "gray"
  : isSelected ? "navy" : "white";

// Tabela de consulta (lookup map)
const bgMap: Record<string, string> = {
  "true-true": "blue",
  "true-false": "gray",
  "false-true": "navy",
  "false-false": "white",
};
const bg = bgMap[`${isHovered}-${isSelected}`];
```

```python
# if aninhado em 3+ níveis
def process(order):
    if order is not None:
        if order.items:
            for item in order.items:
                if item.price > 0:
                    ...

# Early return + guard clauses
def process(order):
    if not order or not order.items:
        return
    for item in order.items:
        if item.price <= 0:
            continue
        ...
```

**Pontos de atenção na revisão:**
- A expressão ternária está aninhada em ≥ 2 níveis?
- O if/else está aninhado em ≥ 3 níveis?
- Pode ser substituído por uma lookup table, early return ou match?

---

## Variantes de Copiar e Colar

### Blocos de código quase duplicados

```python
# Duas funções quase idênticas, só os nomes dos campos mudam
def format_user(user):
    return f"{user.first_name} {user.last_name} ({user.email})"

def format_employee(emp):
    return f"{emp.first_name} {emp.last_name} ({emp.work_email})"

# Abstração unificada
def format_person(first: str, last: str, email: str) -> str:
    return f"{first} {last} ({email})"
```

```typescript
// Handler copiado e colado, só a URL mudou
async function deletePost(id: string) {
  await fetch(`/api/posts/${id}`, { method: "DELETE" });
  router.push("/posts");
}
async function deleteComment(id: string) {
  await fetch(`/api/comments/${id}`, { method: "DELETE" });
  router.push("/comments");
}

// Parametrizado
async function deleteResource(resource: string, id: string) {
  await fetch(`/api/${resource}/${id}`, { method: "DELETE" });
  router.push(`/${resource}`);
}
```

**Pontos de atenção na revisão:**
- Existem ≥ 2 trechos de código que diferem apenas em nome de variável/URL/string?
- É possível extrair uma função compartilhada e parametrizada?
- É possível eliminar as variantes com um template method ou strategy?

---

## Atualizações Sem Efeito

### Disparando atualização de estado sem condição

```typescript
// Toda vez que faz poll, dispara update — mesmo que os dados não tenham mudado
useEffect(() => {
  const interval = setInterval(() => {
    fetch("/api/status").then(r => r.json()).then(setStatus);
  }, 5000);
  return () => clearInterval(interval);
}, []);

// Atualiza somente quando o valor muda
useEffect(() => {
  const interval = setInterval(() => {
    fetch("/api/status")
      .then(r => r.json())
      .then(data => {
        setStatus(prev => isEqual(prev, data) ? prev : data);
      });
  }, 5000);
  return () => clearInterval(interval);
}, []);
```

```python
# Toda iteração do loop escreve no BD — mesmo que o valor não tenha mudado
for item in items:
    item.status = compute_status(item)
    session.commit()

# Escreve apenas quando há mudança
for item in items:
    new_status = compute_status(item)
    if item.status != new_status:
        item.status = new_status
        session.commit()
```

**Pontos de atenção na revisão:**
- O polling / intervalo / event handler atualiza sem nenhuma condição?
- A função wrapper respeita o retorno por mesma referência (same-reference return)?
- A escrita no banco de dados verifica se houve mudança real?

---

## Condição de Corrida TOCTOU

### Time-of-Check-to-Time-of-Use

```python
# Primeiro verifica, depois opera — o arquivo pode ser apagado/criado nesse intervalo
if os.path.exists(path):
    with open(path) as f:
        data = f.read()

# Opera direto + trata a exceção
try:
    with open(path) as f:
        data = f.read()
except FileNotFoundError:
    data = None
```

```python
# Verificar saldo → debitar é uma operação em duas etapas que não é atômica
if account.balance >= amount:
    account.balance -= amount

# Operação atômica ou lock
with account.lock:
    if account.balance < amount:
        raise InsufficientFundsError()
    account.balance -= amount
```

```typescript
// Check-then-act não é seguro em ambiente assíncrono
if (!fileExists(path)) {
  await writeFile(path, content);
}

// Opera direto + catch
try {
  await writeFile(path, content, { flag: "wx" });
} catch (e) {
  if (e.code === "EEXIST") { /* trata */ }
  else throw e;
}
```

**Pontos de atenção na revisão:**
- O padrão `if exists → operate` pode ser substituído por `try operate → catch`?
- A mudança de estado em várias etapas está dentro de uma transação/lock?
- Em operações assíncronas, existe um `await` entre o check e o act?

---

## Operações Excessivamente Amplas

### Lendo dados em excesso

```python
# Lê o arquivo inteiro só para pegar a primeira linha
content = Path("log.txt").read_text()
first_line = content.split("\n")[0]

# Lê só a primeira linha, sem carregar o arquivo inteiro
with open("log.txt") as f:
    first_line = f.readline()
```

```typescript
// Carrega todos os itens e depois filtra
const allItems = await db.query("SELECT * FROM orders");
const pending = allItems.filter(o => o.status === "pending");

// Filtra na camada do banco de dados
const pending = await db.query(
  "SELECT * FROM orders WHERE status = ?", ["pending"]
);
```

```python
# Lê a lista inteira para encontrar um registro
users = list(User.objects.all())
user = next(u for u in users if u.id == user_id)

# Consulta precisa
user = User.objects.get(id=user_id)
```

**Pontos de atenção na revisão:**
- Está lendo a coleção/arquivo inteiro para usar só uma pequena parte?
- O filtro pode ser delegado à camada de banco de dados/armazenamento?
- A chamada de API suporta parâmetros de pagination/limit?

---

## Estado Redundante

### Estado que pode ser derivado

```typescript
// Armazena fullName e firstName + lastName ao mesmo tempo
interface User {
  firstName: string;
  lastName: string;
  fullName: string;  // redundante
}

// fullName é um valor derivado
interface User {
  firstName: string;
  lastName: string;
}
const fullName = `${user.firstName} ${user.lastName}`;
```

```python
# Valor em cache pode ficar desatualizado quando os dados de origem mudam
class Order:
    total: float
    item_count: int       # redundante se len(items) já dá o mesmo resultado
    items: list[Item]

# Derivado ou property
class Order:
    items: list[Item]

    @property
    def total(self) -> float:
        return sum(item.price for item in self.items)

    @property
    def item_count(self) -> int:
        return len(self.items)
```

**Pontos de atenção na revisão:**
- Existe algum campo que pode ser derivado de outros campos?
- O valor em cache tem mecanismo de invalidação?
- O observer/effect pode ser substituído por uma chamada direta?

---

## Checklist Geral de Qualidade

- [ ] **Revisão de reuso**: buscou por utilitários/helpers já existentes, sem reinventar a roda?
- [ ] **Quantidade de parâmetros**: a função tem ≤ 3 parâmetros? Se passar disso, usa options object / dataclass?
- [ ] **Limite de abstração**: o tipo de retorno não expõe detalhes internos de implementação (ORM, cliente HTTP, formato de arquivo)?
- [ ] **Segurança de tipos**: não há magic strings substituindo um enum/constant/union type já existente?
- [ ] **Profundidade de condicionais**: o ternário aninhado tem ≤ 1 nível? O if/else aninhado tem ≤ 2 níveis?
- [ ] **DRY**: não há copy-paste-with-variation (≥ 2 trechos de código quase idênticos)?
- [ ] **Proteção contra operações sem efeito**: polling / intervalo / event handler tem guard de detecção de mudança?
- [ ] **TOCTOU**: o `if exists → operate` foi substituído por `try operate → catch`?
- [ ] **Precisão dos dados**: não está lendo a coleção/arquivo inteiro só para pegar um subconjunto?
- [ ] **Estado redundante**: não há campos armazenados que poderiam ser derivados de outros campos?
