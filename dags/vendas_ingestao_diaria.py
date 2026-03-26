"""
DAG de exemplo: Vendas — Ingestão Diária
========================================
Demonstra os padrões do projeto: TaskFlow API, callbacks,
conexão com ClickHouse, integração dbt e data quality.

Owner: time-bi
Frequência: Diária às 05:00
SLA: 07:00 (2h após início)
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta

from airflow.decorators import dag, task

logger = logging.getLogger(__name__)

DEFAULT_ARGS = {
    "owner": "time-bi",
    "depends_on_past": False,
    "email_on_failure": True,
    "email_on_retry": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(hours=1),
}


@dag(
    dag_id="vendas_ingestao_diaria",
    description="Ingestão diária de transações de venda para ClickHouse",
    schedule="0 5 * * *",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["vendas", "diario", "owner:time-bi"],
    max_active_runs=1,
    doc_md="""
    ## Vendas — Ingestão Diária

    **Objetivo**: Extrai transações de venda do ERP e carrega no ClickHouse.

    **Fonte**: ERP (PostgreSQL — `erp_db`)
    **Destino**: `raw.vendas` → `analytics.fact_vendas` (via dbt)
    **SLA**: Dados disponíveis até 07:00

    **Fluxo**:
    1. Extrai transações do dia anterior do ERP
    2. Valida qualidade dos dados
    3. Insere em `raw.vendas` no ClickHouse
    4. Executa modelos dbt (staging → marts)
    5. Roda testes dbt
    6. Verifica freshness final

    **Owner**: time-bi@empresa.com
    """,
)
def vendas_ingestao_diaria():

    @task()
    def extrair_vendas_erp() -> dict:
        """Extrai vendas do dia anterior do ERP."""
        from airflow.hooks.base import BaseHook

        conn = BaseHook.get_connection("erp_postgres")
        logger.info(f"Extraindo vendas de {conn.host}")

        # Simulação — substituir por query real ao ERP
        dados = [
            {
                "venda_id": 1001,
                "data_venda": "2024-01-15",
                "cliente_id": 42,
                "produto_id": 7,
                "loja_id": 3,
                "quantidade": 2.0,
                "valor_bruto": 150.00,
                "desconto": 15.00,
                "valor_liquido": 135.00,
            }
        ]

        logger.info(f"Extraídas {len(dados)} transações")
        return {"dados": dados, "count": len(dados)}

    @task()
    def validar_dados(extracao: dict) -> dict:
        """Valida qualidade dos dados extraídos antes de inserir."""
        dados = extracao["dados"]

        if not dados:
            raise ValueError("Extração retornou 0 registros — verificar pipeline ERP")

        # Validações básicas
        for i, row in enumerate(dados):
            if row.get("valor_liquido", -1) < 0:
                raise ValueError(f"Valor negativo na linha {i}: {row}")
            if not row.get("venda_id"):
                raise ValueError(f"venda_id ausente na linha {i}")

        ids = [r["venda_id"] for r in dados]
        if len(ids) != len(set(ids)):
            raise ValueError("IDs duplicados detectados na extração")

        logger.info(f"✅ Validação OK — {len(dados)} registros válidos")
        return extracao

    @task()
    def inserir_clickhouse(extracao: dict) -> int:
        """Insere dados validados em raw.vendas no ClickHouse."""
        import os

        import clickhouse_connect

        client = clickhouse_connect.get_client(
            host=os.getenv("CLICKHOUSE_HOST", "clickhouse"),
            port=int(os.getenv("CLICKHOUSE_HTTP_PORT", "8123")),
            username=os.getenv("CLICKHOUSE_USER", "clickhouse"),
            password=os.getenv("CLICKHOUSE_PASSWORD", "clickhouse"),
        )

        dados = extracao["dados"]
        if not dados:
            logger.warning("Nenhum dado para inserir")
            return 0

        columns = list(dados[0].keys())
        rows = [[row[c] for c in columns] for row in dados]

        client.insert("raw.vendas", rows, column_names=columns)
        logger.info(f"✅ {len(rows)} linhas inseridas em raw.vendas")
        return len(rows)

    @task.bash()
    def executar_dbt_staging() -> str:
        """Executa modelos dbt da camada staging."""
        return (
            "dbt run "
            "--project-dir /opt/airflow/dbt "
            "--profiles-dir /opt/airflow/dbt "
            "--profile staging "
            "--select staging.stg_erp__vendas "
            "--no-partial-parse"
        )

    @task.bash()
    def executar_dbt_marts() -> str:
        """Executa modelos dbt da camada marts (fact_vendas)."""
        return (
            "dbt run "
            "--project-dir /opt/airflow/dbt "
            "--profiles-dir /opt/airflow/dbt "
            "--profile staging "
            "--select marts.fact_vendas+ "
        )

    @task.bash()
    def executar_testes_dbt() -> str:
        """Roda testes de qualidade dbt."""
        return (
            "dbt test "
            "--project-dir /opt/airflow/dbt "
            "--profiles-dir /opt/airflow/dbt "
            "--profile staging "
            "--select marts.fact_vendas "
        )

    @task()
    def verificar_freshness() -> dict:
        """Verifica se os dados foram carregados corretamente."""
        import os

        import clickhouse_connect

        client = clickhouse_connect.get_client(
            host=os.getenv("CLICKHOUSE_HOST", "clickhouse"),
            port=int(os.getenv("CLICKHOUSE_HTTP_PORT", "8123")),
            username=os.getenv("CLICKHOUSE_USER", "clickhouse"),
            password=os.getenv("CLICKHOUSE_PASSWORD", "clickhouse"),
        )

        result = client.query("""
            SELECT
                count() AS total_hoje,
                max(data_venda) AS ultima_data,
                dateDiff('hour', max(_inserted_at), now()) AS horas_atras
            FROM analytics.fact_vendas
            WHERE data_venda = today() - 1
        """)

        row = result.first_row
        total, ultima_data, horas = row[0], row[1], row[2]

        logger.info(
            f"Freshness check: {total} registros, última data: {ultima_data}, {horas}h atrás"
        )

        if horas > 3:
            raise ValueError(f"Dados com mais de 3h de atraso: {horas}h")

        return {"total": total, "ultima_data": str(ultima_data), "horas_atras": horas}

    # ─── Definição do Fluxo ──────────────────────────────────────────
    extraido = extrair_vendas_erp()
    validado = validar_dados(extraido)
    rows = inserir_clickhouse(validado)

    staging = executar_dbt_staging()
    marts = executar_dbt_marts()
    testes = executar_testes_dbt()
    freshness = verificar_freshness()

    # Ordem: insert → dbt staging → dbt marts → testes → freshness
    rows >> staging >> marts >> testes >> freshness


# Instanciar a DAG
dag_instance = vendas_ingestao_diaria()
