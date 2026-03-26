---
name: data-quality
description: >
  Skill para validação, testes e monitoramento de qualidade de dados.
  Ative quando precisar: adicionar testes dbt, criar validações de pipeline,
  investigar anomalias em dados, implementar monitoramento de freshness,
  criar alertas de qualidade, ou auditar dados de uma tabela existente.
---

# Skill: Data Quality

## Dimensões de Qualidade

1. **Completude**: campos obrigatórios não nulos
2. **Unicidade**: PKs sem duplicatas
3. **Consistência**: valores dentro de domínios esperados
4. **Atualidade (Freshness)**: dados atualizados no prazo
5. **Referencial**: FKs existentes nas dimensões
6. **Acurácia**: valores fazem sentido (negativo, outlier)

## Testes dbt (padrão do projeto)

### schema.yml completo:
```yaml
version: 2

models:
  - name: fact_vendas
    description: "Tabela fato de vendas — granularidade transação"
    meta:
      owner: time-bi
      freshness_sla_hours: 24
    columns:
      - name: venda_id
        description: "ID único da transação"
        tests:
          - not_null
          - unique

      - name: data_venda
        description: "Data da venda (sem hora)"
        tests:
          - not_null
          - dbt_utils.accepted_range:
              min_value: "'2020-01-01'"
              max_value: "current_date"

      - name: valor_liquido
        description: "Valor após descontos"
        tests:
          - not_null
          - dbt_utils.accepted_range:
              min_value: 0
              inclusive: true

      - name: cliente_id
        tests:
          - not_null
          - relationships:
              to: ref('dim_clientes')
              field: cliente_id

      - name: status
        tests:
          - accepted_values:
              values: ['aprovado', 'cancelado', 'pendente', 'estornado']
```

## Testes Customizados (macros dbt)

### dbt/macros/tests/test_freshness_check.sql
```sql
{% test freshness_check(model, column_name, max_hours=24) %}
SELECT COUNT(*) AS stale_rows
FROM {{ model }}
WHERE {{ column_name }} < now() - interval {{ max_hours }} hour
HAVING COUNT(*) > 0
{% endtest %}
```

### dbt/macros/tests/test_no_future_dates.sql
```sql
{% test no_future_dates(model, column_name) %}
SELECT {{ column_name }}
FROM {{ model }}
WHERE {{ column_name }} > today()
{% endtest %}
```

## Validações em Python (pipeline)

```python
from dataclasses import dataclass
from typing import Any
import pandas as pd
import logging

logger = logging.getLogger(__name__)

@dataclass
class QualityRule:
    name: str
    check: callable
    severity: str  # "error" | "warning"

def validate_dataframe(df: pd.DataFrame, rules: list[QualityRule]) -> dict:
    """Valida DataFrame contra lista de regras de qualidade."""
    results = {"passed": [], "warnings": [], "errors": []}

    for rule in rules:
        try:
            passed = rule.check(df)
            if passed:
                results["passed"].append(rule.name)
                logger.info(f"✅ {rule.name}")
            else:
                bucket = "errors" if rule.severity == "error" else "warnings"
                results[bucket].append(rule.name)
                logger.warning(f"{'❌' if rule.severity == 'error' else '⚠️'} {rule.name}")
        except Exception as e:
            results["errors"].append(f"{rule.name}: {e}")

    if results["errors"]:
        raise ValueError(f"Falhas de qualidade: {results['errors']}")

    return results

# Uso:
REGRAS_VENDAS = [
    QualityRule("sem_valores_nulos_id", lambda df: df["venda_id"].notna().all(), "error"),
    QualityRule("ids_unicos", lambda df: not df["venda_id"].duplicated().any(), "error"),
    QualityRule("valor_positivo", lambda df: (df["valor_liquido"] >= 0).all(), "error"),
    QualityRule("data_valida", lambda df: (df["data_venda"] <= pd.Timestamp.today()).all(), "warning"),
]
```

## Monitoramento de Freshness (DAG)

```python
@task()
def verificar_freshness_clickhouse() -> dict:
    """Verifica se as tabelas principais estão atualizadas."""
    from clickhouse_connect import get_client
    import os

    client = get_client(host=os.environ["CLICKHOUSE_HOST"], ...)

    tabelas = [
        ("analytics.fact_vendas", "data_venda", 24),
        ("analytics.dim_clientes", "atualizado_em", 48),
    ]

    alertas = []
    for tabela, col, sla_horas in tabelas:
        result = client.query(f"""
            SELECT dateDiff('hour', max({col}), now()) AS horas_atras
            FROM {tabela}
        """)
        horas = result.first_row[0]
        if horas > sla_horas:
            alertas.append(f"{tabela}: {horas}h sem atualização (SLA: {sla_horas}h)")
            logger.warning(f"Freshness violation: {tabela}")

    if alertas:
        raise ValueError(f"Freshness SLA violado: {alertas}")

    return {"status": "ok", "checadas": len(tabelas)}
```

## Checklist de Data Quality

Antes de promover dados para produção:
- [ ] Testes dbt passando (not_null, unique, relationships)
- [ ] Nenhum valor fora do domínio esperado
- [ ] Volume razoável (comparar com dia/semana anterior)
- [ ] Freshness dentro do SLA
- [ ] Nenhuma FK quebrada
- [ ] Auditoria de contagem: fonte vs destino
