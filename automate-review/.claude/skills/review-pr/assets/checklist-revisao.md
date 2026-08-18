# Checklist Rápido de Revisão de Código

Lista de referência rápida para revisões de código.

## Pré-Revisão (2 min)

- [ ] Leia a descrição do PR e a issue vinculada
- [ ] Verifique o tamanho do PR (<400 linhas é ideal)
- [ ] Verifique o status do CI/CD (os testes estão passando?)
- [ ] Entenda o requisito de negócio

## Arquitetura e Design (5 min)

- [ ] A solução é adequada ao problema
- [ ] Consistente com os padrões existentes
- [ ] Não existe abordagem mais simples
- [ ] Vai escalar bem?
- [ ] Mudanças estão no local correto

## Lógica e Corretude (10 min)

- [ ] Casos extremos tratados
- [ ] Verificações de null/undefined presentes
- [ ] Erros off-by-one verificados
- [ ] Condições de corrida consideradas
- [ ] Tratamento de erros completo
- [ ] Tipos de dados corretos usados

## Segurança (5 min)

- [ ] Sem segredos hardcoded
- [ ] Entrada validada/sanitizada
- [ ] Injeção SQL prevenida
- [ ] XSS prevenido
- [ ] Verificações de autorização presentes
- [ ] Dados sensíveis protegidos

## Performance (3 min)

- [ ] Sem consultas N+1
- [ ] Operações custosas otimizadas
- [ ] Listas grandes paginadas
- [ ] Sem vazamentos de memória
- [ ] Cache considerado quando apropriado

## Testes (5 min)

- [ ] Existem testes para o código novo
- [ ] Casos extremos testados
- [ ] Casos de erro testados
- [ ] Testes são legíveis
- [ ] Testes são determinísticos

## Qualidade de Código (3 min)

- [ ] Nomes de variáveis/funções claros
- [ ] Sem duplicação de código
- [ ] Funções fazem apenas uma coisa
- [ ] Código complexo comentado
- [ ] Sem números mágicos

## Documentação (2 min)

- [ ] APIs públicas documentadas
- [ ] README atualizado se necessário
- [ ] Breaking changes anotadas
- [ ] Lógica complexa explicada

---

## Marcadores de Severidade

| Marcador | Significado | Ação |
|-------|---------|--------|
| `[bloqueante]` | Precisa ser corrigido | Bloqueia o merge |
| `[importante]` | Deveria ser corrigido | Discuta se houver desacordo |
| `[nit]` | Desejável | Não bloqueante |
| `[sugestão]` | Alternativa | Considere |
| `[aprendizado]` | Comentário educativo | Nenhuma ação necessária |
| `[elogio]` | Bom trabalho | Celebre! |

---

## Matriz de Decisão

| Situação | Decisão |
|-----------|----------|
| Problema crítico de segurança | Bloquear, corrigir imediatamente |
| Breaking change sem migração | Bloquear |
| Tratamento de erro ausente | Deveria corrigir |
| Sem testes para código novo | Deveria corrigir |
| Preferência de estilo | Não bloqueante |
| Melhoria de nomenclatura menor | Não bloqueante |
| Código engenhoso mas funcional | Sugerir algo mais simples |

---

## Orçamento de Tempo

| Tamanho do PR | Tempo Alvo |
|---------|-------------|
| < 100 linhas | 10-15 min |
| 100-400 linhas | 20-40 min |
| > 400 linhas | Peça para dividir |

---

## Sinais de Alerta

Fique atento a estes padrões:

- `// TODO` em código de produção
- `console.log` deixado no código
- Código comentado (deixado morto)
- Tipo `any` em TypeScript
- Blocos catch vazios
- Números/strings mágicos
- Blocos de código copiados e colados
- Verificações de null ausentes
- URLs/credenciais hardcoded
