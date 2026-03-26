---
name: bi-pipeline
description: >
  Skill para criação de pipelines BI end-to-end: desde ingestão até dashboard.
  Ative quando o usuário pedir para criar um novo pipeline de dados, implementar
  uma nova fonte de dados, construir um fluxo ETL/ELT completo, ou estruturar
  uma nova área de negócio no DW. Cobre: DAG Airflow + modelo dbt + tabela ClickHouse + dataset Superset.
---

# Skill: BI Pipeline End-to-End

## Quando Usar
Criação de novos pipelines que cobrem todo o fluxo:
Fonte → Ingestão (Airflow) → Staging (ClickHouse raw) → Transformação (dbt) → Mart → Dashboard (Superset)

## Fase 1 — ASSESS: Entender o Negócio

Antes de escrever código, levantar:
1. **Fonte dos dados**: API REST? Banco relacional? Arquivo CSV/SFTP? Outro ClickHouse?
2. **Granularidade**: Qual é o nível de detalhe? (evento, transação, diário, etc.)
3. **Volume**: Quantas linhas/dia? Crescimento esperado?
4. **Frequência de atualização**: Tempo real, horário, diário?
5. **Domínio de negócio**: Vendas, financeiro, operações, marketing?
6. **KPIs esperados**: Quais métricas o dashboard deve mostrar?
7. **Audiência**: Quem vai consumir? C-level, analistas, operacional?

## Fase 2 — ANALYZE: Modelagem de Dados

### Estrutura de camadas (Medallion adaptado):
```
raw.*          → Dados exatos da fonte (sem transformação)
staging.*      → Normalizado, tipos corretos, deduplicado
analytics.*    → Fatos e dimensões para consumo BI
```

### Nomear entidades:
- Tabela raw: `raw.{dominio}_{entidade}` → `raw.crm_contatos`
- Tabela staging: `stg_{fonte}_{entidade}` (dbt) → `stg_crm__contatos`
- Tabela mart: `dim_{entidade}` ou `fact_{evento}` → `dim_contatos`, `fact_oportunidades`

## Fase 3 — PLAN: Estrutura de Arquivos

```
dags/{dominio}_pipeline.py         # DAG principal
dbt/models/staging/stg_{fonte}__{entidade}.sql
dbt/models/staging/schema.yml      # Testes e docs
dbt/models/marts/{fato_ou_dim}.sql
dbt/models/marts/schema.yml
```

## Fase 4 — EXECUTE: Templates

### DAG de Ingestão:
```python
@dag(
    dag_id="{dominio}_ingestao_{frequencia}",
    schedule="0 5 * * *",  # ajustar
    catchup=False,
    tags=["{dominio}", "{frequencia}", "owner:{time}"],
)
def pipeline():
    @task()
    def extrair() -> dict:
        # lógica de extração
        pass

    @task()
    def inserir_raw(dados: dict) -> int:
        # insert em raw.{tabela}
        pass

    @task.bash()
    def executar_dbt() -> str:
        return "dbt run --select stg_{fonte}__{entidade}+ --profiles-dir /opt/airflow/dbt"

    extrair_dados = extrair()
    rows = inserir_raw(extrair_dados)
    executar_dbt()
```

### Modelo dbt Staging:
```sql
-- stg_{fonte}__{entidade}.sql
WITH source AS (
    SELECT * FROM {{ source('{fonte}', '{entidade}') }}
),
renamed AS (
    SELECT
        id::UInt64 AS {entidade}_id,
        nome::String AS nome,
        criado_em::DateTime AS criado_em,
        -- ... demais colunas
        now() AS _dbt_updated_at
    FROM source
)
SELECT * FROM renamed
```

### schema.yml para staging:
```yaml
version: 2
models:
  - name: stg_{fonte}__{entidade}
    description: "Dados normalizados de {entidade} vindos de {fonte}"
    columns:
      - name: {entidade}_id
        description: "Identificador único"
        tests:
          - not_null
          - unique
      - name: nome
        tests:
          - not_null
```

## Fase 5 — VALIDATE: Checklist

- [ ] DAG testada localmente (`airflow tasks test`)
- [ ] Modelos dbt rodando (`dbt run --select modelo`)
- [ ] Testes dbt passando (`dbt test --select modelo`)
- [ ] Dataset criado no Superset
- [ ] Query do dataset executando < 5s
- [ ] Pelo menos 1 chart criado para validação
- [ ] Documentação atualizada no `schema.yml`
- [ ] PR aberto com descrição do pipeline
