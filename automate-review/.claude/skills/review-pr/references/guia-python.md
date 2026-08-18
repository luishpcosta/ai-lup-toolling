# Guia de Revisão de Código Python

> Guia de revisão de código Python, cobrindo anotações de tipo, async/await, testes, tratamento de exceções, otimização de performance e outros temas centrais.

## Índice

- [Anotações de Tipo](#anotações-de-tipo)
- [Programação Assíncrona](#programação-assíncrona)
- [Tratamento de Exceções](#tratamento-de-exceções)
- [Armadilhas Comuns](#armadilhas-comuns)
- [Boas Práticas de Teste](#boas-práticas-de-teste)
- [Otimização de Performance](#otimização-de-performance)
- [Estilo de Código](#estilo-de-código)
- [Checklist de Revisão](#checklist-de-revisão)

---

## Anotações de Tipo

### Anotações de tipo básicas

```python
# Sem anotação de tipo, a IDE não consegue ajudar
def process_data(data, count):
    return data[:count]

# Usando anotação de tipo
def process_data(data: str, count: int) -> str:
    return data[:count]

# Tipos complexos usando o módulo typing
from typing import Optional, Union

def find_user(user_id: int) -> Optional[User]:
    """Retorna o usuário ou None"""
    return db.get(user_id)

def handle_input(value: Union[str, int]) -> str:
    """Aceita string ou inteiro"""
    return str(value)
```

### Anotações de tipos de container

```python
from typing import List, Dict, Set, Tuple, Sequence

# Tipo impreciso
def get_names(users: list) -> list:
    return [u.name for u in users]

# Tipo de container preciso (no Python 3.9+ pode usar list[User] diretamente)
def get_names(users: List[User]) -> List[str]:
    return [u.name for u in users]

# Use Sequence para sequências somente leitura (mais flexível)
def process_items(items: Sequence[str]) -> int:
    return len(items)

# Tipo de dicionário
def count_words(text: str) -> Dict[str, int]:
    words: Dict[str, int] = {}
    for word in text.split():
        words[word] = words.get(word, 0) + 1
    return words

# Tupla (tamanho e tipos fixos)
def get_point() -> Tuple[float, float]:
    return (1.0, 2.0)

# Tupla de tamanho variável
def get_scores() -> Tuple[int, ...]:
    return (90, 85, 92, 88)
```

### Generics e TypeVar

```python
from typing import TypeVar, Generic, List, Callable

T = TypeVar('T')
K = TypeVar('K')
V = TypeVar('V')

# Função genérica
def first(items: List[T]) -> T | None:
    return items[0] if items else None

# TypeVar com restrição
from typing import Hashable
H = TypeVar('H', bound=Hashable)

def dedupe(items: List[H]) -> List[H]:
    return list(set(items))

# Classe genérica
class Cache(Generic[K, V]):
    def __init__(self) -> None:
        self._data: Dict[K, V] = {}

    def get(self, key: K) -> V | None:
        return self._data.get(key)

    def set(self, key: K, value: V) -> None:
        self._data[key] = value
```

### Callable e funções de callback

```python
from typing import Callable, Awaitable

# Anotação de tipo de função
Handler = Callable[[str, int], bool]

def register_handler(name: str, handler: Handler) -> None:
    handlers[name] = handler

# Callback assíncrono
AsyncHandler = Callable[[str], Awaitable[dict]]

async def fetch_with_handler(
    url: str,
    handler: AsyncHandler
) -> dict:
    return await handler(url)

# Função que retorna função
def create_multiplier(factor: int) -> Callable[[int], int]:
    def multiplier(x: int) -> int:
        return x * factor
    return multiplier
```

### TypedDict e dados estruturados

```python
from typing import TypedDict, Required, NotRequired

# Define a estrutura do dicionário
class UserDict(TypedDict):
    id: int
    name: str
    email: str
    age: NotRequired[int]  # Python 3.11+

def create_user(data: UserDict) -> User:
    return User(**data)

# Campos parcialmente obrigatórios
class ConfigDict(TypedDict, total=False):
    debug: bool
    timeout: int
    host: Required[str]  # este é obrigatório
```

### Protocol e tipagem estrutural

```python
from typing import Protocol, runtime_checkable

# Define um protocolo (verificação de tipo para duck typing)
class Readable(Protocol):
    def read(self, size: int = -1) -> bytes: ...

class Closeable(Protocol):
    def close(self) -> None: ...

# combinando protocolos
class ReadableCloseable(Readable, Closeable, Protocol):
    pass

def process_stream(stream: Readable) -> bytes:
    return stream.read()

# Protocolo verificável em tempo de execução
@runtime_checkable
class Drawable(Protocol):
    def draw(self) -> None: ...

def render(obj: object) -> None:
    if isinstance(obj, Drawable):  # verificação em tempo de execução
        obj.draw()
```

---

## Programação Assíncrona

### Fundamentos de async/await

```python
import asyncio

# Chamada síncrona bloqueante
def fetch_all_sync(urls: list[str]) -> list[str]:
    results = []
    for url in urls:
        results.append(requests.get(url).text)  # execução serial
    return results

# Chamada assíncrona concorrente
async def fetch_url(url: str) -> str:
    async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
            return await response.text()

async def fetch_all(urls: list[str]) -> list[str]:
    tasks = [fetch_url(url) for url in urls]
    return await asyncio.gather(*tasks)  # execução concorrente
```

### Gerenciadores de contexto assíncronos

```python
from contextlib import asynccontextmanager
from typing import AsyncIterator

# Classe de gerenciador de contexto assíncrono
class AsyncDatabase:
    async def __aenter__(self) -> 'AsyncDatabase':
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        await self.disconnect()

# Usando o decorator
@asynccontextmanager
async def get_connection() -> AsyncIterator[Connection]:
    conn = await create_connection()
    try:
        yield conn
    finally:
        await conn.close()

async def query_data():
    async with get_connection() as conn:
        return await conn.fetch("SELECT * FROM users")
```

### Iteradores assíncronos

```python
from typing import AsyncIterator

# Gerador assíncrono
async def fetch_pages(url: str) -> AsyncIterator[dict]:
    page = 1
    while True:
        data = await fetch_page(url, page)
        if not data['items']:
            break
        yield data
        page += 1

# Usando iteração assíncrona
async def process_all_pages():
    async for page in fetch_pages("https://api.example.com"):
        await process_page(page)
```

### Gerenciamento e cancelamento de tasks

```python
import asyncio

# Esquecer de tratar o cancelamento
async def bad_worker():
    while True:
        await do_work()  # não pode ser cancelado corretamente

# Tratamento correto do cancelamento
async def good_worker():
    try:
        while True:
            await do_work()
    except asyncio.CancelledError:
        await cleanup()  # limpa os recursos
        raise  # relança, para que o chamador saiba que foi cancelado

# Controle de timeout
async def fetch_with_timeout(url: str) -> str:
    try:
        async with asyncio.timeout(10):  # Python 3.11+
            return await fetch_url(url)
    except asyncio.TimeoutError:
        return ""

# Grupo de tasks (Python 3.11+)
async def fetch_multiple():
    async with asyncio.TaskGroup() as tg:
        task1 = tg.create_task(fetch_url("url1"))
        task2 = tg.create_task(fetch_url("url2"))
    # espera automaticamente todas as tasks terminarem; exceções são propagadas
    return task1.result(), task2.result()
```

### Combinando código síncrono e assíncrono

```python
import asyncio
from concurrent.futures import ThreadPoolExecutor

# Executar uma função síncrona dentro de código assíncrono
async def run_sync_in_async():
    loop = asyncio.get_event_loop()
    # usa um thread pool para executar operações bloqueantes
    result = await loop.run_in_executor(
        None,  # thread pool padrão
        blocking_io_function,
        arg1, arg2
    )
    return result

# Executar uma função assíncrona dentro de código síncrono
def run_async_in_sync():
    return asyncio.run(async_function())

# Não use time.sleep dentro de código assíncrono
async def bad_delay():
    time.sleep(1)  # bloqueia todo o event loop!

# Use asyncio.sleep
async def good_delay():
    await asyncio.sleep(1)
```

### Semáforos e limitação de taxa

```python
import asyncio

# Usando semáforo para limitar a concorrência
async def fetch_with_limit(urls: list[str], max_concurrent: int = 10):
    semaphore = asyncio.Semaphore(max_concurrent)

    async def fetch_one(url: str) -> str:
        async with semaphore:
            return await fetch_url(url)

    return await asyncio.gather(*[fetch_one(url) for url in urls])

# Usando asyncio.Queue para implementar produtor-consumidor
async def producer_consumer():
    queue: asyncio.Queue[str] = asyncio.Queue(maxsize=100)

    async def producer():
        for item in items:
            await queue.put(item)
        await queue.put(None)  # sinal de término

    async def consumer():
        while True:
            item = await queue.get()
            if item is None:
                break
            await process(item)
            queue.task_done()

    await asyncio.gather(producer(), consumer())
```

---

## Tratamento de Exceções

### Boas práticas de captura de exceções

```python
# Captura demasiadamente ampla
try:
    result = risky_operation()
except:  # captura tudo, até KeyboardInterrupt!
    pass

# Captura Exception mas não trata
try:
    result = risky_operation()
except Exception:
    pass  # engole todas as exceções, dificultando a depuração

# Capture exceções específicas
try:
    result = risky_operation()
except ValueError as e:
    logger.error(f"Invalid value: {e}")
    raise
except IOError as e:
    logger.error(f"IO error: {e}")
    return default_value

# Múltiplos tipos de exceção
try:
    result = parse_and_process(data)
except (ValueError, TypeError, KeyError) as e:
    logger.error(f"Data error: {e}")
    raise DataProcessingError(str(e)) from e
```

### Cadeia de exceções

```python
# Perde a informação da exceção original
try:
    result = external_api.call()
except APIError as e:
    raise RuntimeError("API failed")  # perde a causa original

# Use from para preservar a cadeia de exceções
try:
    result = external_api.call()
except APIError as e:
    raise RuntimeError("API failed") from e

# Quebrar explicitamente a cadeia de exceções (caso raro)
try:
    result = external_api.call()
except APIError:
    raise RuntimeError("API failed") from None
```

### Exceções personalizadas

```python
# Defina uma hierarquia de exceções de negócio
class AppError(Exception):
    """Exceção base da aplicação"""
    pass

class ValidationError(AppError):
    """Erro de validação de dados"""
    def __init__(self, field: str, message: str):
        self.field = field
        self.message = message
        super().__init__(f"{field}: {message}")

class NotFoundError(AppError):
    """Recurso não encontrado"""
    def __init__(self, resource: str, id: str | int):
        self.resource = resource
        self.id = id
        super().__init__(f"{resource} with id {id} not found")

# uso
def get_user(user_id: int) -> User:
    user = db.get(user_id)
    if not user:
        raise NotFoundError("User", user_id)
    return user
```

### Exceções em gerenciadores de contexto

```python
from contextlib import contextmanager

# Trate corretamente exceções em gerenciadores de contexto
@contextmanager
def transaction():
    conn = get_connection()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

# Usando ExceptionGroup (Python 3.11+)
def process_batch(items: list) -> None:
    errors = []
    for item in items:
        try:
            process(item)
        except Exception as e:
            errors.append(e)

    if errors:
        raise ExceptionGroup("Batch processing failed", errors)
```

---

## Armadilhas Comuns

### Argumento padrão mutável

```python
# Argumento padrão mutável
def add_item(item, items=[]):  # bug! compartilhado entre chamadas
    items.append(item)
    return items

# demonstração do problema
add_item(1)  # [1]
add_item(2)  # [1, 2] em vez de [2]!

# Use None como padrão
def add_item(item, items=None):
    if items is None:
        items = []
    items.append(item)
    return items

# Ou use o field de dataclass
from dataclasses import dataclass, field

@dataclass
class Container:
    items: list = field(default_factory=list)
```

### Atributos de classe mutáveis

```python
# Usando atributos de classe mutáveis
class User:
    permissions = []  # compartilhado entre todas as instâncias!

# demonstração do problema
u1 = User()
u2 = User()
u1.permissions.append("admin")
print(u2.permissions)  # ["admin"] - compartilhado de forma inesperada!

# Inicialize dentro do __init__
class User:
    def __init__(self):
        self.permissions = []

# Usando dataclass
@dataclass
class User:
    permissions: list = field(default_factory=list)
```

### Closures dentro de loops

```python
# O closure captura a variável do loop
funcs = []
for i in range(3):
    funcs.append(lambda: i)

print([f() for f in funcs])  # [2, 2, 2] em vez de [0, 1, 2]!

# Use um argumento padrão para capturar o valor
funcs = []
for i in range(3):
    funcs.append(lambda i=i: i)

print([f() for f in funcs])  # [0, 1, 2]

# Usando functools.partial
from functools import partial

funcs = [partial(lambda x: x, i) for i in range(3)]
```

### is vs ==

```python
# Usando is para comparar valores
if x is 1000:  # pode não funcionar!
    pass

# o Python armazena em cache inteiros pequenos (-5 a 256)
a = 256
b = 256
a is b  # True

a = 257
b = 257
a is b  # False!

# Use == para comparar valores
if x == 1000:
    pass

# Use is apenas para None e singletons
if x is None:
    pass

if x is True:  # verificação estrita de booleano
    pass
```

### Performance de concatenação de strings

```python
# Concatenar strings dentro de um loop
result = ""
for item in large_list:
    result += str(item)  # complexidade O(n²)

# Use join
result = "".join(str(item) for item in large_list)  # O(n)

# Use StringIO para construir strings grandes
from io import StringIO

buffer = StringIO()
for item in large_list:
    buffer.write(str(item))
result = buffer.getvalue()
```

---

## Boas Práticas de Teste

### Fundamentos do pytest

```python
import pytest

# Nomenclatura clara de testes
def test_user_creation_with_valid_email():
    user = User(email="test@example.com")
    assert user.email == "test@example.com"

def test_user_creation_with_invalid_email_raises_error():
    with pytest.raises(ValidationError):
        User(email="invalid")

# Usando testes parametrizados
@pytest.mark.parametrize("input,expected", [
    ("hello", "HELLO"),
    ("World", "WORLD"),
    ("", ""),
    ("123", "123"),
])
def test_uppercase(input: str, expected: str):
    assert input.upper() == expected

# Testando exceções
def test_division_by_zero():
    with pytest.raises(ZeroDivisionError) as exc_info:
        1 / 0
    assert "division by zero" in str(exc_info.value)
```

### Fixtures

```python
import pytest
from typing import Generator

# Fixture básica
@pytest.fixture
def user() -> User:
    return User(name="Test User", email="test@example.com")

def test_user_name(user: User):
    assert user.name == "Test User"

# Fixture com limpeza
@pytest.fixture
def database() -> Generator[Database, None, None]:
    db = Database()
    db.connect()
    yield db
    db.disconnect()  # limpeza após o teste

# Fixture assíncrona
@pytest.fixture
async def async_client() -> AsyncGenerator[AsyncClient, None]:
    async with AsyncClient() as client:
        yield client

# Fixture compartilhada (conftest.py)
# conftest.py
@pytest.fixture(scope="session")
def app():
    """Instância de app compartilhada por toda a sessão de testes"""
    return create_app()

@pytest.fixture(scope="module")
def db(app):
    """Conexão de banco de dados compartilhada por cada módulo de teste"""
    return app.db
```

### Mock e Patch

```python
from unittest.mock import Mock, patch, AsyncMock

# Mock de dependências externas
def test_send_email():
    mock_client = Mock()
    mock_client.send.return_value = True

    service = EmailService(client=mock_client)
    result = service.send_welcome_email("user@example.com")

    assert result is True
    mock_client.send.assert_called_once_with(
        to="user@example.com",
        subject="Welcome!",
        body=ANY,
    )

# Patch de função em nível de módulo
@patch("myapp.services.external_api.call")
def test_with_patched_api(mock_call):
    mock_call.return_value = {"status": "ok"}

    result = process_data()

    assert result["status"] == "ok"

# Mock assíncrono
async def test_async_function():
    mock_fetch = AsyncMock(return_value={"data": "test"})

    with patch("myapp.client.fetch", mock_fetch):
        result = await get_data()

    assert result == {"data": "test"}
```

### Organização de testes

```python
# Use classes para organizar testes relacionados
class TestUserAuthentication:
    """Testes relacionados à autenticação de usuário"""

    def test_login_with_valid_credentials(self, user):
        assert authenticate(user.email, "password") is True

    def test_login_with_invalid_password(self, user):
        assert authenticate(user.email, "wrong") is False

    def test_login_locks_after_failed_attempts(self, user):
        for _ in range(5):
            authenticate(user.email, "wrong")
        assert user.is_locked is True

# Use marks para marcar testes
@pytest.mark.slow
def test_large_data_processing():
    pass

@pytest.mark.integration
def test_database_connection():
    pass

# executar testes com uma marca específica: pytest -m "not slow"
```

### Cobertura e qualidade

```python
# pytest.ini ou pyproject.toml
[tool.pytest.ini_options]
addopts = "--cov=myapp --cov-report=term-missing --cov-fail-under=80"
testpaths = ["tests"]

# Teste casos extremos
def test_empty_input():
    assert process([]) == []

def test_none_input():
    with pytest.raises(TypeError):
        process(None)

def test_large_input():
    large_data = list(range(100000))
    result = process(large_data)
    assert len(result) == 100000
```

---

## Otimização de Performance

### Escolha de estrutura de dados

```python
# Busca em lista O(n)
if item in large_list:  # lento
    pass

# Busca em set O(1)
large_set = set(large_list)
if item in large_set:  # rápido
    pass

# Usando o módulo collections
from collections import Counter, defaultdict, deque

# contagem
word_counts = Counter(words)
most_common = word_counts.most_common(10)

# dicionário com valor padrão
graph = defaultdict(list)
graph[node].append(neighbor)

# deque (operações O(1) em ambas as extremidades)
queue = deque()
queue.appendleft(item)  # O(1) vs list.insert(0, item) O(n)
```

### Geradores e iteradores

```python
# Carrega todos os dados de uma vez
def get_all_users():
    return [User(row) for row in db.fetch_all()]  # alto consumo de memória

# Use um gerador
def get_all_users():
    for row in db.fetch_all():
        yield User(row)  # carregamento sob demanda (lazy)

# Expressão geradora
sum_of_squares = sum(x**2 for x in range(1000000))  # não cria uma lista

# Módulo itertools
from itertools import islice, chain, groupby

# pega apenas os primeiros 10
first_10 = list(islice(infinite_generator(), 10))

# encadeia múltiplos iteradores
all_items = chain(list1, list2, list3)

# agrupamento
for key, group in groupby(sorted(items, key=get_key), key=get_key):
    process_group(key, list(group))
```

### Cache

```python
from functools import lru_cache, cache

# Cache LRU
@lru_cache(maxsize=128)
def expensive_computation(n: int) -> int:
    return sum(i**2 for i in range(n))

# Cache ilimitado (Python 3.9+)
@cache
def fibonacci(n: int) -> int:
    if n < 2:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

# Cache manual (quando é necessário mais controle)
class DataService:
    def __init__(self):
        self._cache: dict[str, Any] = {}
        self._cache_ttl: dict[str, float] = {}

    def get_data(self, key: str) -> Any:
        if key in self._cache:
            if time.time() < self._cache_ttl[key]:
                return self._cache[key]

        data = self._fetch_data(key)
        self._cache[key] = data
        self._cache_ttl[key] = time.time() + 300  # 5 minutos
        return data
```

### Processamento paralelo

```python
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor

# Use thread pool para tarefas com gargalo em I/O
def fetch_all_urls(urls: list[str]) -> list[str]:
    with ThreadPoolExecutor(max_workers=10) as executor:
        results = list(executor.map(fetch_url, urls))
    return results

# Use process pool para tarefas com gargalo em CPU
def process_large_dataset(data: list) -> list:
    with ProcessPoolExecutor() as executor:
        results = list(executor.map(heavy_computation, data))
    return results

# Use as_completed para obter os resultados conforme terminam
from concurrent.futures import as_completed

with ThreadPoolExecutor() as executor:
    futures = {executor.submit(fetch, url): url for url in urls}
    for future in as_completed(futures):
        url = futures[future]
        try:
            result = future.result()
        except Exception as e:
            print(f"{url} failed: {e}")
```

---

## Estilo de Código

### Pontos-chave do PEP 8

```python
# Convenções de nomenclatura
class MyClass:  # nome de classe em PascalCase
    MAX_SIZE = 100  # constante em UPPER_SNAKE_CASE

    def method_name(self):  # método em snake_case
        local_var = 1  # variável em snake_case

# Ordem dos imports
# 1. biblioteca padrão
import os
import sys
from typing import Optional

# 2. bibliotecas de terceiros
import numpy as np
import pandas as pd

# 3. módulos locais
from myapp import config
from myapp.utils import helper

# Limite de comprimento de linha (79 ou 88 caracteres)
# quebra de linha para expressões longas
result = (
    long_function_name(arg1, arg2, arg3)
    + another_long_function(arg4, arg5)
)

# Convenções de linhas em branco
class MyClass:
    """Docstring da classe"""

    def method_one(self):
        pass

    def method_two(self):  # uma linha em branco entre métodos
        pass


def top_level_function():  # duas linhas em branco entre definições de nível superior
    pass
```

### Docstrings

```python
# Docstring no estilo Google
def calculate_area(width: float, height: float) -> float:
    """Calcula a área de um retângulo.

    Args:
        width: A largura do retângulo (deve ser positiva).
        height: A altura do retângulo (deve ser positiva).

    Returns:
        A área do retângulo.

    Raises:
        ValueError: Se width ou height forem negativos.

    Example:
        >>> calculate_area(3, 4)
        12.0
    """
    if width < 0 or height < 0:
        raise ValueError("Dimensions must be positive")
    return width * height

# Docstring de classe
class DataProcessor:
    """Classe utilitária para processar e transformar dados.

    Attributes:
        source: Caminho da fonte de dados.
        format: Formato de saída ('json' ou 'csv').

    Example:
        >>> processor = DataProcessor("data.csv")
        >>> processor.process()
    """
```

### Recursos modernos do Python

```python
# f-string (Python 3.6+)
name = "World"
print(f"Hello, {name}!")

# com expressão
print(f"Result: {1 + 2 = }")  # "Result: 1 + 2 = 3"

# Operador walrus (Python 3.8+)
if (n := len(items)) > 10:
    print(f"List has {n} items")

# Separador de parâmetros posicionais (Python 3.8+)
def greet(name, /, greeting="Hello", *, punctuation="!"):
    """name só pode ser passado por posição, punctuation só por nome (keyword)"""
    return f"{greeting}, {name}{punctuation}"

# Pattern matching (Python 3.10+)
def handle_response(response: dict):
    match response:
        case {"status": "ok", "data": data}:
            return process_data(data)
        case {"status": "error", "message": msg}:
            raise APIError(msg)
        case _:
            raise ValueError("Unknown response format")
```

---

## Checklist de Revisão

### Segurança de tipos
- [ ] As funções têm anotações de tipo (parâmetros e retorno)
- [ ] Uso de `Optional` para indicar explicitamente possível None
- [ ] Tipos genéricos usados corretamente
- [ ] A verificação do mypy passa (sem erros)
- [ ] Evita o uso de `Any`; quando necessário, adiciona comentário explicativo

### Código assíncrono
- [ ] async/await usados em pares corretamente
- [ ] Nenhuma chamada bloqueante usada dentro de código assíncrono
- [ ] `CancelledError` tratado corretamente
- [ ] Uso de `asyncio.gather` ou `TaskGroup` para execução concorrente
- [ ] Recursos limpos corretamente (gerenciador de contexto assíncrono)

### Tratamento de exceções
- [ ] Captura tipos de exceção específicos, sem usar `except:` genérico
- [ ] Cadeia de exceções preservada com `from`
- [ ] Exceções personalizadas herdam de uma classe base adequada
- [ ] Mensagens de exceção são significativas e facilitam a depuração

### Estruturas de dados
- [ ] Nenhum argumento padrão mutável usado (list, dict, set)
- [ ] Atributos de classe não são objetos mutáveis
- [ ] Estrutura de dados correta escolhida (busca em set vs list)
- [ ] Conjuntos de dados grandes usam geradores em vez de listas

### Testes
- [ ] Cobertura de testes adequada (recomendado ≥80%)
- [ ] Nomenclatura dos testes descreve claramente o cenário testado
- [ ] Casos extremos têm cobertura de teste
- [ ] Mock isola corretamente as dependências externas
- [ ] Código assíncrono tem os testes assíncronos correspondentes

### Estilo de código
- [ ] Segue o guia de estilo PEP 8
- [ ] Funções e classes têm docstring
- [ ] Ordem dos imports está correta (biblioteca padrão, terceiros, local)
- [ ] Nomenclatura consistente e significativa
- [ ] Uso de recursos modernos do Python (f-string, operador walrus, etc.)

### Performance
- [ ] Evita criar objetos repetidamente dentro de loops
- [ ] Concatenação de strings usa join
- [ ] Uso adequado de cache (@lru_cache)
- [ ] Tarefas com gargalo em I/O/CPU usam o método de paralelismo adequado
