---
description: >
  Cria uma nova DAG Airflow completa com estrutura padrão do projeto.
  Uso: /new-dag <dominio> <acao> <frequencia>
  Exemplo: /new-dag vendas sincronizacao_erp diaria
---

# Novo Pipeline DAG

Você vai criar uma nova DAG Airflow seguindo exatamente os padrões do projeto.

## Parâmetros solicitados (se não fornecidos, perguntar):
1. **Domínio** (ex: vendas, financeiro, marketing)
2. **Ação** (ex: ingestao_erp, sincronizacao_api, carga_csv)
3. **Frequência** (diaria, horaria, semanal, mensal)
4. **Fonte de dados** (API REST, banco PostgreSQL, arquivo S3, etc.)
5. **Destino** (nome da tabela ClickHouse)
6. **Responsável** (email ou nome do time)

## Após coletar informações:
1. Ler `.claude/agents/airflow-expert.md` para seguir os padrões
2. Criar `dags/{dominio}_{acao}_{frequencia}.py`
3. Criar testes em `tests/unit/test_{dominio}_{acao}.py`
4. Adicionar entrada na tabela de pipelines do README
5. Exibir checklist de validação antes do deploy
