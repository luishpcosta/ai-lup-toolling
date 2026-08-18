# Guia de Revisão de Segurança

Checklist de revisão de código focado em segurança, baseado no OWASP Top 10 e em boas práticas.

## Autenticação e Autorização

### Autenticação
- [ ] Senhas com hash usando algoritmo forte (bcrypt, argon2)
- [ ] Requisitos de complexidade de senha aplicados
- [ ] Bloqueio de conta após tentativas falhas
- [ ] Fluxo seguro de redefinição de senha
- [ ] Autenticação multifator para operações sensíveis
- [ ] Tokens de sessão criptograficamente aleatórios
- [ ] Timeout de sessão implementado

### Autorização
- [ ] Verificações de autorização em toda requisição
- [ ] Princípio do menor privilégio aplicado
- [ ] Controle de acesso baseado em papéis (RBAC) implementado corretamente
- [ ] Sem caminhos de escalonamento de privilégio
- [ ] Verificações de referência direta a objeto (prevenção de IDOR)
- [ ] Endpoints de API protegidos adequadamente

### Segurança de JWT
```typescript
// Configuração insegura de JWT
jwt.sign(payload, 'weak-secret');

// Configuração segura de JWT
jwt.sign(payload, process.env.JWT_SECRET, {
  algorithm: 'RS256',
  expiresIn: '15m',
  issuer: 'your-app',
  audience: 'your-api'
});

// Não verificando o JWT corretamente
const decoded = jwt.decode(token);  // Sem verificação de assinatura!

// Verifica assinatura e claims
const decoded = jwt.verify(token, publicKey, {
  algorithms: ['RS256'],
  issuer: 'your-app',
  audience: 'your-api'
});
```

## Validação de Entrada

### Prevenção de Injeção SQL
```python
# Vulnerável a injeção SQL
query = f"SELECT * FROM users WHERE id = {user_id}"

# Use consultas parametrizadas
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))

# Use ORM com escaping adequado
User.objects.filter(id=user_id)
```

### Prevenção de XSS
```typescript
// Vulnerável a XSS
element.innerHTML = userInput;

// Use textContent para texto puro
element.textContent = userInput;

// Use DOMPurify para HTML
element.innerHTML = DOMPurify.sanitize(userInput);

// O Angular faz escape automaticamente na interpolação de templates
// (mas cuidado com [innerHTML] e bypassSecurityTrustHtml)
template: `<div>{{ userInput }}</div>`  // Seguro
template: `<div [innerHTML]="userInput"></div>`  // Perigoso sem sanitização!
```

### Prevenção de Injeção de Comando
```python
# Vulnerável a injeção de comando
os.system(f"convert {filename} output.png")

# Use subprocess com argumentos em lista
subprocess.run(['convert', filename, 'output.png'], check=True)

# Valide e sanitize a entrada
import shlex
safe_filename = shlex.quote(filename)
```

### Prevenção de Path Traversal
```typescript
// Vulnerável a path traversal
const filePath = `./uploads/${req.params.filename}`;

// Valide e sanitize o caminho
const path = require('path');
const safeName = path.basename(req.params.filename);
const uploadsDir = path.resolve('./uploads');
const filePath = path.resolve(uploadsDir, safeName);

// Verifica se ainda está dentro do diretório uploads (ambos os lados absolutos)
if (!filePath.startsWith(uploadsDir + path.sep)) {
  throw new Error('Invalid path');
}
```

## Proteção de Dados

### Tratamento de Dados Sensíveis
- [ ] Nenhum segredo no código-fonte
- [ ] Segredos armazenados em variáveis de ambiente ou gerenciador de segredos
- [ ] Dados sensíveis criptografados em repouso
- [ ] Dados sensíveis criptografados em trânsito (HTTPS)
- [ ] PII tratada de acordo com regulações (GDPR etc.)
- [ ] Dados sensíveis não registrados em log
- [ ] Exclusão segura de dados quando necessário

### Segurança de Configuração
```yaml
# Segredos em arquivos de configuração
database:
  password: "super-secret-password"

# Referencia variáveis de ambiente
database:
  password: ${DATABASE_PASSWORD}
```

### Mensagens de Erro
```typescript
// Vazando informação sensível
catch (error) {
  return res.status(500).json({
    error: error.stack,  // Expõe detalhes internos
    query: sqlQuery      // Expõe a estrutura do banco de dados
  });
}

// Mensagens de erro genéricas
catch (error) {
  logger.error('Database error', { error, userId });  // Loga internamente
  return res.status(500).json({
    error: 'An unexpected error occurred'
  });
}
```

## Segurança de API

### Rate Limiting
- [ ] Rate limiting em todos os endpoints públicos
- [ ] Limites mais estritos em endpoints de autenticação
- [ ] Limites por usuário e por IP
- [ ] Tratamento adequado quando os limites são excedidos

### Configuração de CORS
```typescript
// CORS excessivamente permissivo
app.use(cors({ origin: '*' }));

// CORS restritivo
app.use(cors({
  origin: ['https://your-app.com'],
  methods: ['GET', 'POST'],
  credentials: true
}));
```

### Cabeçalhos HTTP
```typescript
// Cabeçalhos de segurança a configurar
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
    }
  },
  hsts: { maxAge: 31536000, includeSubDomains: true },
  noSniff: true,
  xssFilter: true,
  frameguard: { action: 'deny' }
}));
```

## Criptografia

### Práticas Seguras
- [ ] Uso de algoritmos consolidados (AES-256, RSA-2048+)
- [ ] Não implementar criptografia própria (custom)
- [ ] Uso de geração de números aleatórios criptograficamente segura
- [ ] Gerenciamento e rotação adequados de chaves
- [ ] Armazenamento seguro de chaves (HSM, KMS)

### Erros Comuns
```typescript
// Geração de aleatoriedade fraca
const token = Math.random().toString(36);

// Aleatoriedade criptograficamente segura
const crypto = require('crypto');
const token = crypto.randomBytes(32).toString('hex');

// MD5/SHA1 para senhas
const hash = crypto.createHash('md5').update(password).digest('hex');

// Use bcrypt ou argon2
const bcrypt = require('bcrypt');
const hash = await bcrypt.hash(password, 12);
```

## Segurança de Dependências

### Checklist
- [ ] Dependências apenas de fontes confiáveis
- [ ] Sem vulnerabilidades conhecidas (npm audit)
- [ ] Dependências mantidas atualizadas
- [ ] Lock files versionados (package-lock.json)
- [ ] Uso mínimo de dependências
- [ ] Conformidade de licença verificada

### Comandos de Auditoria
```bash
# Node.js
npm audit
npm audit fix

# Python
pip-audit
safety check

# Geral
snyk test
```

## Logging e Monitoramento

### Logging Seguro
- [ ] Nenhum dado sensível em logs (senhas, tokens, PII)
- [ ] Logs protegidos contra adulteração
- [ ] Retenção de log adequada
- [ ] Eventos de segurança registrados (tentativas de login, mudanças de permissão)
- [ ] Injeção de log prevenida

```typescript
// Registrando dados sensíveis em log
logger.info(`User login: ${email}, password: ${password}`);

// Logging seguro
logger.info('User login attempt', { email, success: true });
```

## Níveis de Severidade da Revisão de Segurança

| Severidade | Descrição | Ação |
|----------|-------------|--------|
| **Crítica** | Exploração imediata possível, risco de violação de dados | Bloquear o merge, corrigir imediatamente |
| **Alta** | Vulnerabilidade significativa, requer condições específicas | Bloquear o merge, corrigir antes do release |
| **Média** | Risco moderado, preocupação de defesa em profundidade | Deveria corrigir, pode mergear com acompanhamento |
| **Baixa** | Problema menor, violação de boa prática | Bom corrigir, não bloqueante |
| **Informativa** | Sugestão de melhoria | Melhoria opcional |
