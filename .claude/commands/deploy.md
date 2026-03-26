---
description: >
  Guia interativo para deploy seguro em staging ou produção.
  Executa checklist automatizado, valida pré-requisitos e orienta o processo.
  Uso: /deploy [staging|production]
---

# Deploy Guiado

Execute o checklist de deploy para o ambiente solicitado.

## Pré-requisitos (verificar automaticamente):
1. Checar se branch atual NÃO é main ou staging (obrigatório ter PR)
2. Rodar `git status` para confirmar que não há arquivos não commitados
3. Rodar `make test` e verificar se todos os testes passam
4. Rodar `make lint` e verificar se não há erros críticos
5. Verificar se existe PR aberto para este branch

## Para deploy em STAGING:
```bash
# 1. Testar localmente
make dev-up
make test
make dbt-test

# 2. Push e abrir PR → staging
git push origin HEAD
# (abrir PR no GitHub)

# 3. Aguardar GitHub Actions (CI)
# CI automaticamente faz deploy em staging após merge
```

## Para deploy em PRODUCTION:
```bash
# Só possível via PR: staging → main
# 1. Verificar se staging está estável (últimas 24h)
# 2. Abrir PR: staging → main no GitHub
# 3. Aguardar aprovação de 1 reviewer obrigatório
# 4. GitHub Actions faz deploy automático após merge
```

## ⚠️ Regras de Segurança:
- NUNCA fazer deploy manual direto em produção
- Sempre usar o fluxo staging → PR → main
- DAGs novas: testar localmente ANTES do deploy
- Migrations ClickHouse: sempre ter rollback preparado
