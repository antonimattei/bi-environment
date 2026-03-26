---
name: sql-optimization
description: >
  Skill para otimização de queries SQL no ClickHouse e análise de performance.
  Ative quando: uma query estiver lenta, precisar otimizar um dashboard Superset,
  analisar plano de execução, criar índices, projetar particionamento, ou revisar
  queries existentes para performance. Inclui patterns de ClickHouse específicos.
---

# Skill: SQL Optimization para ClickHouse

## Processo de Otimização

### Passo 1 — Medir antes de otimizar
```sql
-- Executar query original e capturar query_id
SELECT ... SETTINGS log_queries=1;

-- Analisar no system.query_log
SELECT
    query_duration_ms,
    read_rows,
    read_bytes,
    memory_usage,
    query
FROM system.query_log
WHERE query_id = 'SEU_QUERY_ID'
ORDER BY event_time DESC LIMIT 1;
```

### Passo 2 — EXPLAIN antes de mudar
```sql
-- Ver árvore de execução
EXPLAIN SELECT ...;

-- Ver pipeline de processamento
EXPLAIN PIPELINE SELECT ...;

-- Ver acesso a índices
EXPLAIN indexes = 1 SELECT ...;
```

## Padrões de Otimização

### 1. Filtros na ORDER BY (índice primário)
```sql
-- ❌ Ruim: filtro fora da ORDER BY
SELECT * FROM fact_vendas WHERE cliente_id = 123;
-- (não usa índice primário se ORDER BY é (loja_id, produto_id, ...))

-- ✅ Bom: incluir colunas da ORDER BY nos filtros
SELECT * FROM fact_vendas
WHERE loja_id = 1 AND cliente_id = 123 AND data_venda >= '2024-01-01';
```

### 2. Prewhere (filtragem antes do decode)
```sql
-- ClickHouse tem PREWHERE para filtros baratos
SELECT valor_liquido
FROM fact_vendas
PREWHERE loja_id = 1  -- filtro leve primeiro (boolean simples)
WHERE data_venda >= today() - 30;  -- filtro mais pesado depois
```

### 3. Sampling para dashboards exploratórios
```sql
-- Para dashboards com bilhões de linhas: usar sample
SELECT
    toStartOfDay(data_venda) AS dia,
    sum(valor_liquido) * 10 AS receita_estimada  -- compensar 10% sample
FROM fact_vendas SAMPLE 0.1
WHERE data_venda >= today() - 90
GROUP BY dia ORDER BY dia;
```

### 4. Joins eficientes
```sql
-- ✅ Sempre colocar tabela maior à esquerda em JOINS
-- ✅ Usar GLOBAL JOIN para tabelas distribuídas
-- ✅ Usar dicionários para lookups de dimensões pequenas

-- Dicionário (melhor que JOIN para dimensões < 10M linhas):
CREATE DICTIONARY dict_lojas (
    loja_id UInt32,
    nome String,
    regiao String
)
PRIMARY KEY loja_id
SOURCE(CLICKHOUSE(TABLE 'dim_lojas' DB 'analytics'))
LIFETIME(300)  -- refresh a cada 5 min
LAYOUT(HASHED());

-- Usar dicionário na query:
SELECT
    dictGet('dict_lojas', 'regiao', loja_id) AS regiao,
    sum(valor_liquido) AS receita
FROM fact_vendas
WHERE data_venda = today()
GROUP BY regiao;
```

### 5. Materialized Views para agregações frequentes
```sql
-- Quando uma query agrega sempre o mesmo nível
-- criar MV que pré-agrega incrementalmente:
CREATE MATERIALIZED VIEW mv_receita_hora
ENGINE = SummingMergeTree()
ORDER BY (loja_id, hora)
AS SELECT
    loja_id,
    toStartOfHour(data_venda_ts) AS hora,
    sum(valor_liquido) AS receita,
    count() AS transacoes
FROM fact_vendas_realtime
GROUP BY loja_id, hora;
```

## Configurações de Performance

```sql
-- Para queries analíticas pesadas:
SELECT ... SETTINGS
    max_threads = 16,           -- usar mais threads
    max_memory_usage = 10000000000,  -- 10GB máx
    read_overflow_mode = 'break';   -- não lançar erro se exceder

-- Para queries em dashboards (timeout):
SELECT ... SETTINGS
    max_execution_time = 30,    -- 30s timeout
    timeout_overflow_mode = 'break';
```

## Checklist de Revisão de Query

Antes de colocar em produção:
- [ ] `EXPLAIN` revisado — sem full table scans desnecessários
- [ ] Partição filtrada (evitar ler todas as partições)
- [ ] Colunas explícitas (sem `SELECT *`)
- [ ] `FINAL` usado apenas onde necessário (ReplacingMergeTree)
- [ ] Tempo < 5s para dashboards interativos
- [ ] Tempo < 60s para relatórios batch
- [ ] Testado com volume real de produção
