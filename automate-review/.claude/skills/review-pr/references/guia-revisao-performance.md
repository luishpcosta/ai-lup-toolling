# Guia de Revisão de Performance

Guia de revisão de desempenho, cobrindo front-end, back-end, banco de dados, complexidade de algoritmo e desempenho de API.

## Índice

- [Desempenho de front-end (Core Web Vitals)](#desempenho-de-front-end-core-web-vitals)
- [Desempenho em JavaScript](#desempenho-em-javascript)
- [Gerenciamento de memória](#gerenciamento-de-memória)
- [Desempenho de banco de dados](#desempenho-de-banco-de-dados)
- [Desempenho de API](#desempenho-de-api)
- [Complexidade de algoritmo](#complexidade-de-algoritmo)
- [Checklist de revisão de desempenho](#checklist-de-revisão-de-desempenho)

---

## Desempenho de front-end (Core Web Vitals)

### Métricas centrais de 2024

| Métrica | Nome completo | Valor-alvo | Significado |
|------|------|--------|------|
| **LCP** | Largest Contentful Paint | ≤ 2,5s | Tempo de renderização do maior conteúdo |
| **INP** | Interaction to Next Paint | ≤ 200ms | Tempo de resposta à interação (substituiu o FID em 2024) |
| **CLS** | Cumulative Layout Shift | ≤ 0,1 | Deslocamento cumulativo de layout |
| **FCP** | First Contentful Paint | ≤ 1,8s | Primeira renderização de conteúdo |
| **TBT** | Total Blocking Time | ≤ 200ms | Tempo de bloqueio da thread principal |

### Verificação de otimização de LCP

```javascript
// Carregamento lazy da imagem de LCP - atrasa conteúdo crítico
<img src="hero.jpg" loading="lazy" />

// Carregamento imediato da imagem de LCP
<img src="hero.jpg" fetchpriority="high" />

// Formato de imagem não otimizado
<img src="hero.png" />  // arquivo PNG grande demais

// Formato de imagem moderno + responsivo
<picture>
  <source srcset="hero.avif" type="image/avif" />
  <source srcset="hero.webp" type="image/webp" />
  <img src="hero.jpg" alt="Hero" />
</picture>
```

**Pontos de verificação:**
- [ ] O elemento de LCP tem `fetchpriority="high"` configurado?
- [ ] É usado formato WebP/AVIF?
- [ ] Existe renderização no servidor ou geração estática?
- [ ] O CDN está configurado corretamente?

### Verificação de otimização de FCP

```html
<!-- CSS que bloqueia a renderização -->
<link rel="stylesheet" href="all-styles.css" />

<!-- CSS crítico inline + carregamento assíncrono do restante -->
<style>/* estilos críticos da primeira tela */</style>
<link rel="preload" href="styles.css" as="style" onload="this.onload=null;this.rel='stylesheet'" />

<!-- Fonte que bloqueia a renderização -->
@font-face {
  font-family: 'CustomFont';
  src: url('font.woff2');
}

<!-- Otimização de exibição de fonte -->
@font-face {
  font-family: 'CustomFont';
  src: url('font.woff2');
  font-display: swap;  /* usa a fonte do sistema primeiro, troca após o carregamento */
}
```

### Verificação de otimização de INP

```javascript
// Tarefa longa bloqueia a thread principal
button.addEventListener('click', () => {
  // operação síncrona que demora 500ms
  processLargeData(data);
  updateUI();
});

// Divide a tarefa longa
button.addEventListener('click', async () => {
  // cede o controle da thread principal
  await scheduler.yield?.() ?? new Promise(r => setTimeout(r, 0));

  // processa em lotes
  for (const chunk of chunks) {
    processChunk(chunk);
    await scheduler.yield?.();
  }
  updateUI();
});

// Usa Web Worker para cálculos complexos
const worker = new Worker('heavy-computation.js');
worker.postMessage(data);
worker.onmessage = (e) => updateUI(e.data);
```

### Verificação de otimização de CLS

```css
/* Mídia sem dimensões especificadas */
img { width: 100%; }

/* Reserva espaço */
img {
  width: 100%;
  aspect-ratio: 16 / 9;
}

/* Conteúdo inserido dinamicamente causa deslocamento de layout */
.ad-container { }

/* Reserva altura fixa */
.ad-container {
  min-height: 250px;
}
```

**Checklist de revisão de CLS:**
- [ ] Imagens/vídeos têm width/height ou aspect-ratio definidos?
- [ ] O carregamento de fonte usa `font-display: swap`?
- [ ] Conteúdo dinâmico reserva espaço com antecedência?
- [ ] É evitada a inserção de conteúdo acima de conteúdo já existente?

---

## Desempenho em JavaScript

### Divisão de código e carregamento lazy

```javascript
// Carrega todo o código de uma vez
import { HeavyChart } from './charts';
import { PDFExporter } from './pdf';
import { AdminPanel } from './admin';

// Carregamento sob demanda
const HeavyChart = lazy(() => import('./charts'));
const PDFExporter = lazy(() => import('./pdf'));

// Divisão de código por rota
const routes = [
  {
    path: '/dashboard',
    component: lazy(() => import('./pages/Dashboard')),
  },
  {
    path: '/admin',
    component: lazy(() => import('./pages/Admin')),
  },
];
```

### Otimização de tamanho do bundle

```javascript
// Importa a biblioteca inteira
import _ from 'lodash';
import moment from 'moment';

// Importação sob demanda
import debounce from 'lodash/debounce';
import { format } from 'date-fns';

// Sem Tree Shaking
export default {
  fn1() {},
  fn2() {},  // não usado, mas incluído no bundle
};

// Exportação nomeada permite Tree Shaking
export function fn1() {}
export function fn2() {}
```

**Checklist de revisão de bundle:**
- [ ] É usado import() dinâmico para divisão de código?
- [ ] Bibliotecas grandes são importadas sob demanda?
- [ ] O tamanho do bundle foi analisado? (webpack-bundle-analyzer)
- [ ] Existem dependências não utilizadas?

### Otimização de renderização de listas

```typescript
// Renderiza uma lista grande
@Component({
  template: `
    <ul>
      <li *ngFor="let item of items">{{ item.name }}</li>
    </ul>
  `,  // 10000 itens = 10000 nós DOM
})
class ListComponent {
  @Input() items: Item[];
}

// Lista virtual - renderiza apenas os itens visíveis (Angular CDK)
import { ScrollingModule } from '@angular/cdk/scrolling';

@Component({
  template: `
    <cdk-virtual-scroll-viewport itemSize="35" style="height: 400px">
      <div *cdkVirtualFor="let item of items">{{ item.name }}</div>
    </cdk-virtual-scroll-viewport>
  `,
})
class VirtualListComponent {
  @Input() items: Item[];
}
```

**Pontos de verificação para grandes volumes de dados:**
- [ ] Listas com mais de 100 itens usam scroll virtual?
- [ ] Tabelas suportam paginação ou virtualização?
- [ ] Existe renderização completa desnecessária?

---

## Gerenciamento de memória

### Vazamentos de memória comuns

#### 1. Listeners de evento não removidos

```javascript
// O evento continua sendo escutado após o componente desmontar
useEffect(() => {
  window.addEventListener('resize', handleResize);
}, []);

// Remove o listener de evento
useEffect(() => {
  window.addEventListener('resize', handleResize);
  return () => window.removeEventListener('resize', handleResize);
}, []);
```

#### 2. Timers não limpos

```javascript
// Timer não é limpo
useEffect(() => {
  setInterval(fetchData, 5000);
}, []);

// Limpa o timer
useEffect(() => {
  const timer = setInterval(fetchData, 5000);
  return () => clearInterval(timer);
}, []);
```

#### 3. Referências em closure

```javascript
// A closure mantém referência a um objeto grande
function createHandler() {
  const largeData = new Array(1000000).fill('x');

  return function handler() {
    // largeData é referenciado pela closure e não pode ser coletado
    console.log(largeData.length);
  };
}

// Mantém apenas os dados necessários
function createHandler() {
  const largeData = new Array(1000000).fill('x');
  const length = largeData.length;  // mantém só o valor necessário

  return function handler() {
    console.log(length);
  };
}
```

#### 4. Inscrições (subscriptions) não canceladas

```javascript
// WebSocket/EventSource não é fechado
useEffect(() => {
  const ws = new WebSocket('wss://...');
  ws.onmessage = handleMessage;
}, []);

// Limpa a conexão
useEffect(() => {
  const ws = new WebSocket('wss://...');
  ws.onmessage = handleMessage;
  return () => ws.close();
}, []);
```

### Checklist de revisão de memória

```markdown
- [ ] Todos os useEffect têm função de limpeza?
- [ ] Os listeners de evento são removidos quando o componente desmonta?
- [ ] Os timers são limpos?
- [ ] As conexões WebSocket/SSE são encerradas?
- [ ] Objetos grandes são liberados a tempo?
- [ ] Existe alguma variável global acumulando dados?
```

### Ferramentas de detecção

| Ferramenta | Uso |
|------|------|
| Chrome DevTools Memory | Análise de heap snapshot |
| MemLab (Meta) | Detecção automatizada de vazamento de memória |
| Performance Monitor | Monitoramento de memória em tempo real |

---

## Desempenho de banco de dados

### Problema de consulta N+1

```python
# Problema N+1 - 1 + N consultas
users = User.objects.all()  # 1 consulta
for user in users:
    print(user.profile.bio)  # N consultas (uma para cada usuário)

# Eager Loading - 2 consultas
users = User.objects.select_related('profile').all()
for user in users:
    print(user.profile.bio)  # sem consultas adicionais

# Relações muitos-para-muitos com prefetch_related
posts = Post.objects.prefetch_related('tags').all()
```

```javascript
// Exemplo com TypeORM
// Problema N+1
const users = await userRepository.find();
for (const user of users) {
  const posts = await user.posts;  // consulta a cada iteração do loop
}

// Eager Loading
const users = await userRepository.find({
  relations: ['posts'],
});
```

### Otimização de índices

```sql
-- Varredura completa da tabela (full table scan)
SELECT * FROM orders WHERE status = 'pending';

-- Adiciona um índice
CREATE INDEX idx_orders_status ON orders(status);

-- Índice inutilizado: operação de função na coluna
SELECT * FROM users WHERE YEAR(created_at) = 2024;

-- Consulta por intervalo pode usar índice
SELECT * FROM users
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';

-- Índice inutilizado: wildcard de prefixo em LIKE
SELECT * FROM products WHERE name LIKE '%phone%';

-- Correspondência por prefixo pode usar índice
SELECT * FROM products WHERE name LIKE 'phone%';
```

### Otimização de consultas

```sql
-- SELECT * obtém colunas não necessárias
SELECT * FROM users WHERE id = 1;

-- Consulta apenas as colunas necessárias
SELECT id, name, email FROM users WHERE id = 1;

-- Tabela grande sem LIMIT
SELECT * FROM logs WHERE type = 'error';

-- Consulta paginada
SELECT * FROM logs WHERE type = 'error' LIMIT 100 OFFSET 0;

-- Executa consulta dentro de um loop
for id in user_ids:
    cursor.execute("SELECT * FROM users WHERE id = %s", (id,))

-- Consulta em lote
cursor.execute("SELECT * FROM users WHERE id IN %s", (tuple(user_ids),))
```

### Checklist de revisão de banco de dados

```markdown
Verificação obrigatória:
- [ ] Existe consulta N+1?
- [ ] As colunas da cláusula WHERE têm índice?
- [ ] O SELECT * foi evitado?
- [ ] Consultas em tabelas grandes têm LIMIT?

Verificação recomendada:
- [ ] Foi usado EXPLAIN para analisar o plano de execução?
- [ ] A ordem das colunas no índice composto está correta?
- [ ] Existem índices não utilizados?
- [ ] Há monitoramento de consultas lentas (slow query log)?
```

---

## Desempenho de API

### Implementação de paginação

```javascript
// Retorna todos os dados
app.get('/users', async (req, res) => {
  const users = await User.findAll();  // pode retornar 100000 registros
  res.json(users);
});

// Paginação + limite do número máximo
app.get('/users', async (req, res) => {
  const page = parseInt(req.query.page) || 1;
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);  // máximo 100
  const offset = (page - 1) * limit;

  const { rows, count } = await User.findAndCountAll({
    limit,
    offset,
    order: [['id', 'ASC']],
  });

  res.json({
    data: rows,
    pagination: {
      page,
      limit,
      total: count,
      totalPages: Math.ceil(count / limit),
    },
  });
});
```

### Estratégia de cache

```javascript
// Exemplo de cache com Redis
async function getUser(id) {
  const cacheKey = `user:${id}`;

  // 1. Verifica o cache
  const cached = await redis.get(cacheKey);
  if (cached) {
    return JSON.parse(cached);
  }

  // 2. Consulta o banco de dados
  const user = await db.users.findById(id);

  // 3. Grava no cache (define tempo de expiração)
  await redis.setex(cacheKey, 3600, JSON.stringify(user));

  return user;
}

// Cabeçalhos de cache HTTP
app.get('/static-data', (req, res) => {
  res.set({
    'Cache-Control': 'public, max-age=86400',  // 24 horas
    'ETag': 'abc123',
  });
  res.json(data);
});
```

### Compressão de resposta

```javascript
// Habilita compressão Gzip/Brotli
const compression = require('compression');
app.use(compression());

// Retorna apenas os campos necessários
// requisição: GET /users?fields=id,name,email
app.get('/users', async (req, res) => {
  const fields = req.query.fields?.split(',') || ['id', 'name'];
  const users = await User.findAll({
    attributes: fields,
  });
  res.json(users);
});
```

### Proteção por limitação de taxa

```javascript
// Limitação de taxa (rate limiting)
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({
  windowMs: 60 * 1000,  // 1 minuto
  max: 100,             // no máximo 100 requisições
  message: { error: 'Too many requests, please try again later.' },
});

app.use('/api/', limiter);
```

### Checklist de revisão de API

```markdown
- [ ] Os endpoints de listagem têm paginação?
- [ ] O número máximo de itens por página está limitado?
- [ ] Dados de alta demanda (hot data) têm cache?
- [ ] A compressão de resposta está habilitada?
- [ ] Existe limitação de taxa (rate limiting)?
- [ ] Apenas os campos necessários são retornados?
```

---

## Complexidade de algoritmo

### Comparação de complexidades comuns

| Complexidade | Nome | 10 itens | 1000 itens | 1 milhão de itens | Exemplo |
|--------|------|-------|---------|----------|------|
| O(1) | Constante | 1 | 1 | 1 | Busca em hash |
| O(log n) | Logarítmica | 3 | 10 | 20 | Busca binária |
| O(n) | Linear | 10 | 1000 | 1 milhão | Percorrer um array |
| O(n log n) | Linear-logarítmica | 33 | 10000 | 20 milhões | Quicksort |
| O(n²) | Quadrática | 100 | 1 milhão | 1 trilhão | Loop aninhado |
| O(2ⁿ) | Exponencial | 1024 | ∞ | ∞ | Fibonacci recursivo |

### Identificação durante a revisão de código

```javascript
// O(n²) - loop aninhado
function findDuplicates(arr) {
  const duplicates = [];
  for (let i = 0; i < arr.length; i++) {
    for (let j = i + 1; j < arr.length; j++) {
      if (arr[i] === arr[j]) {
        duplicates.push(arr[i]);
      }
    }
  }
  return duplicates;
}

// O(n) - usando Set
function findDuplicates(arr) {
  const seen = new Set();
  const duplicates = new Set();
  for (const item of arr) {
    if (seen.has(item)) {
      duplicates.add(item);
    }
    seen.add(item);
  }
  return [...duplicates];
}
```

```javascript
// O(n²) - chama includes a cada iteração do loop
function removeDuplicates(arr) {
  const result = [];
  for (const item of arr) {
    if (!result.includes(item)) {  // includes é O(n)
      result.push(item);
    }
  }
  return result;
}

// O(n) - usando Set
function removeDuplicates(arr) {
  return [...new Set(arr)];
}
```

```javascript
// Busca O(n) - percorre a lista toda vez
const users = [{ id: 1, name: 'A' }, { id: 2, name: 'B' }, ...];
function getUser(id) {
  return users.find(u => u.id === id);  // O(n)
}

// Busca O(1) - usando Map
const userMap = new Map(users.map(u => [u.id, u]));

function getUser(id) {
  return userMap.get(id);  // O(1)
}
```

### Considerações sobre complexidade de espaço

```javascript
// Espaço O(n) - cria um novo array
const doubled = arr.map(x => x * 2);

// Espaço O(1) - modificação in-place (se permitido)
for (let i = 0; i < arr.length; i++) {
  arr[i] *= 2;
}

// Profundidade de recursão excessiva pode causar estouro de pilha
function factorial(n) {
  if (n <= 1) return 1;
  return n * factorial(n - 1);  // espaço de pilha O(n)
}

// Versão iterativa com espaço O(1)
function factorial(n) {
  let result = 1;
  for (let i = 2; i <= n; i++) {
    result *= i;
  }
  return result;
}
```

### Perguntas de revisão sobre complexidade

```markdown
"A complexidade desse loop aninhado é O(n²), o que pode causar problemas de desempenho com grandes volumes de dados"
"Aqui é usado Array.includes() dentro de um loop, resultando em O(n²) no total; sugiro usar Set"
"Essa profundidade de recursão pode causar estouro de pilha, sugiro reescrever como iteração ou recursão de cauda"
```

---

## Checklist de revisão de desempenho

### Verificação obrigatória (nível bloqueante)

**Front-end:**
- [ ] A imagem de LCP usa carregamento lazy? (não deveria)
- [ ] Existe `transition: all`?
- [ ] São animadas propriedades como width/height/top/left?
- [ ] Listas com mais de 100 itens são virtualizadas?

**Back-end:**
- [ ] Existe consulta N+1?
- [ ] Os endpoints de listagem têm paginação?
- [ ] Existe SELECT * em tabelas grandes?

**Geral:**
- [ ] Existe loop aninhado O(n²) ou pior?
- [ ] useEffect/listeners de evento têm limpeza?

### Verificação recomendada (nível importante)

**Front-end:**
- [ ] É usada divisão de código?
- [ ] Bibliotecas grandes são importadas sob demanda?
- [ ] As imagens usam WebP/AVIF?
- [ ] Existem dependências não utilizadas?

**Back-end:**
- [ ] Dados de alta demanda (hot data) têm cache?
- [ ] As colunas usadas em WHERE têm índice?
- [ ] Há monitoramento de consultas lentas?

**API:**
- [ ] A compressão de resposta está habilitada?
- [ ] Existe limitação de taxa (rate limiting)?
- [ ] Apenas os campos necessários são retornados?

### Sugestões de otimização (nível sugestão)

- [ ] O tamanho do bundle foi analisado?
- [ ] É usado CDN?
- [ ] Existe monitoramento de desempenho?
- [ ] Foram feitos testes de benchmark de desempenho?

---

## Limites de métricas de desempenho

### Métricas de front-end

| Métrica | Bom | Precisa melhorar | Ruim |
|------|-----|--------|-----|
| LCP | ≤ 2,5s | 2,5-4s | > 4s |
| INP | ≤ 200ms | 200-500ms | > 500ms |
| CLS | ≤ 0,1 | 0,1-0,25 | > 0,25 |
| FCP | ≤ 1,8s | 1,8-3s | > 3s |
| Bundle Size (JS) | < 200KB | 200-500KB | > 500KB |

### Métricas de back-end

| Métrica | Bom | Precisa melhorar | Ruim |
|------|-----|--------|-----|
| Tempo de resposta da API | < 100ms | 100-500ms | > 500ms |
| Consulta ao banco de dados | < 50ms | 50-200ms | > 200ms |
| Carregamento de página | < 3s | 3-5s | > 5s |

---

## Ferramentas recomendadas

### Desempenho de front-end

| Ferramenta | Uso |
|------|------|
| [Lighthouse](https://developer.chrome.com/docs/lighthouse/) | Teste de Core Web Vitals |
| [WebPageTest](https://www.webpagetest.org/) | Análise detalhada de desempenho |
| [webpack-bundle-analyzer](https://github.com/webpack-contrib/webpack-bundle-analyzer) | Análise de bundle |
| [Chrome DevTools Performance](https://developer.chrome.com/docs/devtools/performance/) | Análise de desempenho em tempo de execução |

### Detecção de memória

| Ferramenta | Uso |
|------|------|
| [MemLab](https://github.com/facebookincubator/memlab) | Detecção automatizada de vazamento de memória |
| Chrome Memory Tab | Análise de heap snapshot |

### Desempenho de back-end

| Ferramenta | Uso |
|------|------|
| EXPLAIN | Análise do plano de execução de consultas no banco de dados |
| [pganalyze](https://pganalyze.com/) | Monitoramento de desempenho do PostgreSQL |
| [New Relic](https://newrelic.com/) / [Datadog](https://www.datadoghq.com/) | Monitoramento APM |

---

## Anti-padrões de eficiência de baixo nível

Falhas de eficiência no nível do código, independentes dos problemas de desempenho em nível de arquitetura. Complementa os defeitos de gerenciamento de recursos e concorrência já cobertos em [checklist-bugs-comuns.md](checklist-bugs-comuns.md).

### Trabalho repetido desnecessário

- [ ] A mesma função/consulta é chamada repetidamente dentro do mesmo request/render?
- [ ] Arquivo/configuração é lido repetidamente dentro de um loop (loop-invariant)?
- [ ] O resultado do cálculo pode ser armazenado em cache ou repassado para etapas seguintes?

```typescript
// loop-invariant executado repetidamente dentro do loop
for (const path of paths) {
  const config = JSON.parse(fs.readFileSync("config.json", "utf-8"));
  processFile(path, config);
}

// movido para fora do loop
const config = JSON.parse(fs.readFileSync("config.json", "utf-8"));
for (const path of paths) processFile(path, config);
```

### Oportunidades de concorrência perdidas

- [ ] Operações async independentes são feitas com `await` sequencial?
- [ ] É possível usar `Promise.all` / `asyncio.gather` / `tokio::join!` para concorrência?

```typescript
// await sequencial
const a = await fetchA();
const b = await fetchB();

// concorrente
const [a, b] = await Promise.all([fetchA(), fetchB()]);
```

### Inchaço do caminho crítico (hot path)

- [ ] O código em nível de módulo/import executa operações pesadas (I/O de arquivo, rede, construção de objetos grandes)?
- [ ] O caminho por requisição (per-request) tem inicializações que poderiam ser postergadas?
- [ ] O código de inicialização bloqueia a primeira requisição?

### Estruturas de dados sem limite

> Defeitos relacionados ao ciclo de vida de recursos (conexões não fechadas, listeners não removidos, timers não limpos) estão em [checklist-bugs-comuns.md → Gerenciamento de Recursos](checklist-bugs-comuns.md#gerenciamento-de-recursos). Esta seção foca nos *limites de capacidade*.

- [ ] Dicionários/listas/caches globais têm `max-size` ou TTL?
- [ ] Estruturas de dados cumulativas (filas, logs, buffers de métricas) têm limite máximo?
- [ ] Objetos alocados por requisição mantêm referência persistente que impede o GC?

```python
# cache sem limite
_cache: dict[str, Any] = {}

# LRU com limite
from functools import lru_cache

@lru_cache(maxsize=256)
def get_cached(key: str) -> Any:
    return expensive_computation(key)
```

---

## Recursos de referência

- [Core Web Vitals - web.dev](https://web.dev/articles/vitals)
- [Optimizing Core Web Vitals - Vercel](https://vercel.com/guides/optimizing-core-web-vitals-in-2024)
- [MemLab - Meta Engineering](https://engineering.fb.com/2022/09/12/open-source/memlab/)
- [Big O Cheat Sheet](https://www.bigocheatsheet.com/)
- [N+1 Query Problem - Stack Overflow](https://stackoverflow.com/questions/97197/what-is-the-n1-selects-problem-in-orm-object-relational-mapping)
