# Guia de Revisão de Código TypeScript/JavaScript

> Guia de revisão de código TypeScript, cobrindo sistema de tipos, generics, tipos condicionais, modo strict, padrões de async/await como temas centrais.

## Índice

- [Fundamentos de Segurança de Tipos](#fundamentos-de-segurança-de-tipos)
- [Padrões de Generics](#padrões-de-generics)
- [Tipos Avançados](#tipos-avançados)
- [Configuração do Modo Strict](#configuração-do-modo-strict)
- [Tratamento de Assíncrono](#tratamento-de-assíncrono)
- [Imutabilidade](#imutabilidade)
- [Regras de ESLint](#regras-de-eslint)
- [Checklist de Revisão](#checklist-de-revisão)

---

## Fundamentos de Segurança de Tipos

### Evite usar any

```typescript
// Usar any anula a segurança de tipos
function processData(data: any) {
  return data.value;  // sem verificação de tipo, pode quebrar em tempo de execução
}

// Use tipos adequados
interface DataPayload {
  value: string;
}
function processData(data: DataPayload) {
  return data.value;
}

// Para tipos desconhecidos, use unknown + type guard
function processUnknown(data: unknown) {
  if (typeof data === 'object' && data !== null && 'value' in data) {
    return (data as { value: string }).value;
  }
  throw new Error('Invalid data');
}
```

### Estreitamento de tipos (narrowing)

```typescript
// Asserção de tipo insegura
function getLength(value: string | string[]) {
  return (value as string[]).length;  // dá erro se for string
}

// Use type guards
function getLength(value: string | string[]): number {
  if (Array.isArray(value)) {
    return value.length;
  }
  return value.length;
}

// Use o operador in
interface Dog { bark(): void }
interface Cat { meow(): void }

function speak(animal: Dog | Cat) {
  if ('bark' in animal) {
    animal.bark();
  } else {
    animal.meow();
  }
}
```

### Tipos literais e as const

```typescript
// Tipo demasiado amplo
const config = {
  endpoint: '/api',
  method: 'GET'  // o tipo é string
};

// Use as const para obter o tipo literal
const config = {
  endpoint: '/api',
  method: 'GET'
} as const;  // o tipo de method é 'GET'

// Aplicado a parâmetros de função
function request(method: 'GET' | 'POST', url: string) { ... }
request(config.method, config.endpoint);  // correto!
```

---

## Padrões de Generics

### Generics básicos

```typescript
// Código duplicado
function getFirstString(arr: string[]): string | undefined {
  return arr[0];
}
function getFirstNumber(arr: number[]): number | undefined {
  return arr[0];
}

// Use generics
function getFirst<T>(arr: T[]): T | undefined {
  return arr[0];
}
```

### Restrições de generics

```typescript
// Generic sem restrição, não é possível acessar a propriedade
function getProperty<T>(obj: T, key: string) {
  return obj[key];  // Erro: não é possível indexar
}

// Use a restrição keyof
function getProperty<T, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}

const user = { name: 'Alice', age: 30 };
getProperty(user, 'name');  // o tipo de retorno é string
getProperty(user, 'age');   // o tipo de retorno é number
getProperty(user, 'foo');   // Erro: 'foo' não está em keyof User
```

### Valores padrão de generics

```typescript
// Forneça um tipo padrão razoável
interface ApiResponse<T = unknown> {
  data: T;
  status: number;
  message: string;
}

// pode ser usado sem especificar o parâmetro genérico
const response: ApiResponse = { data: null, status: 200, message: 'OK' };
// ou também pode ser especificado
const userResponse: ApiResponse<User> = { ... };
```

### Tipos utilitários genéricos comuns

```typescript
// Aproveite bem os tipos utilitários nativos
interface User {
  id: number;
  name: string;
  email: string;
}

type PartialUser = Partial<User>;         // todas as propriedades opcionais
type RequiredUser = Required<User>;       // todas as propriedades obrigatórias
type ReadonlyUser = Readonly<User>;       // todas as propriedades somente leitura
type UserKeys = keyof User;               // 'id' | 'name' | 'email'
type NameOnly = Pick<User, 'name'>;       // { name: string }
type WithoutId = Omit<User, 'id'>;        // { name: string; email: string }
type UserRecord = Record<string, User>;   // { [key: string]: User }
```

---

## Tipos Avançados

### Tipos condicionais

```typescript
// Retorna tipos diferentes de acordo com o tipo de entrada
type IsString<T> = T extends string ? true : false;

type A = IsString<string>;  // true
type B = IsString<number>;  // false

// Extrai o tipo do elemento de um array
type ElementType<T> = T extends (infer U)[] ? U : never;

type Elem = ElementType<string[]>;  // string

// Extrai o tipo de retorno de uma função (ReturnType nativo)
type MyReturnType<T> = T extends (...args: any[]) => infer R ? R : never;
```

### Tipos mapeados

```typescript
// Transforma todas as propriedades de um tipo de objeto
type Nullable<T> = {
  [K in keyof T]: T[K] | null;
};

interface User {
  name: string;
  age: number;
}

type NullableUser = Nullable<User>;
// { name: string | null; age: number | null }

// Adiciona um prefixo
type Getters<T> = {
  [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K];
};

type UserGetters = Getters<User>;
// { getName: () => string; getAge: () => number }
```

### Tipos literais de template

```typescript
// Nomes de eventos com segurança de tipos
type EventName = 'click' | 'focus' | 'blur';
type HandlerName = `on${Capitalize<EventName>}`;
// 'onClick' | 'onFocus' | 'onBlur'

// Tipo para rotas de API
type ApiRoute = `/api/${string}`;
const route: ApiRoute = '/api/users';  // OK
const badRoute: ApiRoute = '/users';   // Erro
```

### Discriminated Unions

```typescript
// Use uma propriedade discriminante para obter segurança de tipos
type Result<T, E> =
  | { success: true; data: T }
  | { success: false; error: E };

function handleResult(result: Result<User, Error>) {
  if (result.success) {
    console.log(result.data.name);  // o TypeScript sabe que data existe
  } else {
    console.log(result.error.message);  // o TypeScript sabe que error existe
  }
}

// Padrão de Action do Redux
type Action =
  | { type: 'INCREMENT'; payload: number }
  | { type: 'DECREMENT'; payload: number }
  | { type: 'RESET' };

function reducer(state: number, action: Action): number {
  switch (action.type) {
    case 'INCREMENT':
      return state + action.payload;  // o tipo de payload já é conhecido
    case 'DECREMENT':
      return state - action.payload;
    case 'RESET':
      return 0;  // aqui não há payload
  }
}
```

---

## Configuração do Modo Strict

### tsconfig.json recomendado

```json
{
  "compilerOptions": {
    // Opções strict que devem obrigatoriamente ser habilitadas
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "strictBindCallApply": true,
    "strictPropertyInitialization": true,
    "noImplicitThis": true,
    "useUnknownInCatchVariables": true,

    // Opções extras recomendadas
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "exactOptionalPropertyTypes": true,
    "noPropertyAccessFromIndexSignature": true
  }
}
```

### Impacto do noUncheckedIndexedAccess

```typescript
// tsconfig: "noUncheckedIndexedAccess": true

const arr = [1, 2, 3];
const first = arr[0];  // o tipo é number | undefined

// Usar diretamente pode dar erro
console.log(first.toFixed(2));  // Erro: pode ser undefined

// Verifique antes
if (first !== undefined) {
  console.log(first.toFixed(2));
}

// Ou use asserção de não nulo (quando tiver certeza)
console.log(arr[0]!.toFixed(2));
```

---

## Tratamento de Assíncrono

### Tratamento de erros em Promise

```typescript
// Não tratar erros assíncronos
async function fetchUser(id: string) {
  const response = await fetch(`/api/users/${id}`);
  return response.json();  // erro de rede não tratado
}

// Trate os erros corretamente
async function fetchUser(id: string): Promise<User> {
  try {
    const response = await fetch(`/api/users/${id}`);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    return await response.json();
  } catch (error) {
    if (error instanceof Error) {
      throw new Error(`Failed to fetch user: ${error.message}`);
    }
    throw error;
  }
}
```

### Promise.all vs Promise.allSettled

```typescript
// Em Promise.all, se uma falhar, todas falham
async function fetchAllUsers(ids: string[]) {
  const users = await Promise.all(ids.map(fetchUser));
  return users;  // se uma falhar, todas falham
}

// Promise.allSettled obtém todos os resultados
async function fetchAllUsers(ids: string[]) {
  const results = await Promise.allSettled(ids.map(fetchUser));

  const users: User[] = [];
  const errors: Error[] = [];

  for (const result of results) {
    if (result.status === 'fulfilled') {
      users.push(result.value);
    } else {
      errors.push(result.reason);
    }
  }

  return { users, errors };
}
```

### Tratamento de condição de corrida

```typescript
// Condição de corrida: uma requisição antiga pode sobrescrever uma mais nova
function useSearch() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);

  useEffect(() => {
    fetch(`/api/search?q=${query}`)
      .then(r => r.json())
      .then(setResults);  // a requisição antiga pode retornar depois!
  }, [query]);
}

// Use AbortController
function useSearch() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);

  useEffect(() => {
    const controller = new AbortController();

    fetch(`/api/search?q=${query}`, { signal: controller.signal })
      .then(r => r.json())
      .then(setResults)
      .catch(e => {
        if (e.name !== 'AbortError') throw e;
      });

    return () => controller.abort();
  }, [query]);
}
```

---

## Imutabilidade

### Readonly e ReadonlyArray

```typescript
// Parâmetro mutável pode ser modificado por acidente
function processUsers(users: User[]) {
  users.sort((a, b) => a.name.localeCompare(b.name));  // modificou o array original!
  return users;
}

// Use readonly para evitar modificações
function processUsers(users: readonly User[]): User[] {
  return [...users].sort((a, b) => a.name.localeCompare(b.name));
}

// Somente leitura em profundidade
type DeepReadonly<T> = {
  readonly [K in keyof T]: T[K] extends object ? DeepReadonly<T[K]> : T[K];
};
```

### Parâmetros de função invariantes

```typescript
// Use as const e readonly para proteger os dados
function createConfig<T extends readonly string[]>(routes: T) {
  return routes;
}

const routes = createConfig(['home', 'about', 'contact'] as const);
// o tipo é readonly ['home', 'about', 'contact']
```

---

## Regras de ESLint

### Regras recomendadas do @typescript-eslint

```javascript
// eslint.config.js (flat config, typescript-eslint v8)
import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  eslint.configs.recommended,
  // conjunto de regras que exige informação de tipos, equivalente ao antigo recommended-requiring-type-checking
  tseslint.configs.recommendedTypeChecked,
  tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        // permite que as regras com tipagem encontrem automaticamente o tsconfig correspondente
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // Segurança de tipos
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unsafe-assignment': 'error',
      '@typescript-eslint/no-unsafe-member-access': 'error',
      '@typescript-eslint/no-unsafe-call': 'error',
      '@typescript-eslint/no-unsafe-return': 'error',

      // Boas práticas
      '@typescript-eslint/explicit-function-return-type': 'warn',
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/await-thenable': 'error',
      '@typescript-eslint/no-misused-promises': 'error',

      // Estilo de código
      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/prefer-nullish-coalescing': 'error',
      '@typescript-eslint/prefer-optional-chain': 'error',
    },
  },
);
```

### Correções comuns de erros de ESLint

```typescript
// no-floating-promises: a Promise precisa ser tratada
async function save() { ... }
save();  // Erro: Promise não tratada

// Trate explicitamente
await save();
// ou
save().catch(console.error);
// ou ignore explicitamente
void save();

// no-misused-promises: não é possível usar Promise em posição não async
const items = [1, 2, 3];
items.forEach(async (item) => {  // Erro!
  await processItem(item);
});

// Use for...of
for (const item of items) {
  await processItem(item);
}
// ou Promise.all
await Promise.all(items.map(processItem));
```

---

## Checklist de Revisão

### Sistema de Tipos
- [ ] Não usa `any` (usa `unknown` + type guard no lugar)
- [ ] Interfaces e tipos definidos com nomes completos e significativos
- [ ] Usa generics para aumentar a reutilização de código
- [ ] Union types têm o estreitamento de tipo (narrowing) correto
- [ ] Aproveita bem os tipos utilitários (Partial, Pick, Omit etc.)

### Generics
- [ ] Generics têm restrições adequadas (extends)
- [ ] Parâmetros genéricos têm valores padrão razoáveis
- [ ] Evita generics excessivos (princípio KISS)

### Modo Strict
- [ ] tsconfig.json tem strict: true habilitado
- [ ] noUncheckedIndexedAccess habilitado
- [ ] Não usa @ts-ignore (usa @ts-expect-error em vez disso)

### Código Assíncrono
- [ ] Funções async têm tratamento de erros
- [ ] Rejeições de Promise são tratadas corretamente
- [ ] Sem floating promises (Promises não tratadas)
- [ ] Requisições concorrentes usam Promise.all ou Promise.allSettled
- [ ] Condições de corrida tratadas com AbortController

### Imutabilidade
- [ ] Não modifica diretamente os parâmetros da função
- [ ] Usa o operador spread para criar novos objetos/arrays
- [ ] Considera usar o modificador readonly

### ESLint
- [ ] Usa @typescript-eslint/recommended
- [ ] Sem avisos ou erros de ESLint
- [ ] Usa consistent-type-imports
