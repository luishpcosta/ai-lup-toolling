# Modelo de Revisão de PR

Copie e use este modelo para suas revisões de código.

---

## Resumo

[Visão geral breve do que foi revisado - 1-2 frases]

**Tamanho do PR:** [Pequeno/Médio/Grande] (~X linhas)
**Tempo de Revisão:** [X minutos]

## Pontos Fortes

- [O que foi bem feito]
- [Bons padrões ou abordagens utilizadas]
- [Melhorias em relação ao código anterior]

## Mudanças Obrigatórias

**[bloqueante]** [Descrição do problema]
> [Local do código ou exemplo]
> [Correção sugerida ou explicação]

**[bloqueante]** [Descrição do problema]
> [Detalhes]

## Sugestões Importantes

**[importante]** [Descrição do problema]
> [Por que isso importa]
> [Abordagem sugerida]

## Sugestões Menores

**[nit]** [Sugestão de melhoria menor]

**[sugestão]** [Abordagem alternativa a considerar]

## Notas de Aprendizado

[Contexto educativo que vale compartilhar sobre X]

[Histórico por trás da decisão de design Y]

## Considerações de Segurança

- [ ] Sem segredos hardcoded
- [ ] Validação de entrada presente
- [ ] Verificações de autorização implementadas
- [ ] Sem riscos de injeção SQL/XSS

## Cobertura de Testes

- [ ] Testes unitários adicionados/atualizados
- [ ] Casos extremos cobertos
- [ ] Casos de erro testados

## Veredito

**[ ] Aprovar** - Pronto para merge
**[ ] Comentar** - Sugestões menores, pode fazer merge
**[ ] Solicitar Mudanças** - Precisa resolver problemas bloqueantes

---

## Modelos de Cópia Rápida

### Problema Bloqueante
```
**[bloqueante]** [Título]

[Descrição do problema]

**Local:** `file.ts:123`

**Correção sugerida:**
\`\`\`typescript
// Seu código sugerido
\`\`\`
```

### Sugestão Importante
```
**[importante]** [Título]

[Por que isso é importante]

**Considere:**
- Opção A: [descrição]
- Opção B: [descrição]
```

### Sugestão Menor
```
**[nit]** [Sugestão]

Não é bloqueante, mas considere [melhoria].
```

### Elogio
```
**[elogio]** Ótimo trabalho em [algo específico]!

[Por que isso é bom]
```

### Aprendizado
```
**[aprendizado]** [Nota educativa]

Para contexto, [X] funciona dessa forma porque [Y]. Nenhuma ação necessária — apenas compartilhando.
```
