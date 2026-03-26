---
name: airflow-patterns
description: >
  Skill com padrões avançados para DAGs Airflow: sensores, branches, callbacks,
  SLAs, dinâmicas, TaskGroups, e integrações com ClickHouse/dbt.
  Ative quando precisar de padrões além do básico: DAG dinâmica, sensor de arquivo,
  XCom avançado, callback de falha, branching condicional, ou TaskGroup.
---

# Skill: Airflow Patterns Avançados

## Pattern 1 — DAG com TaskGroups Organizados

```python
from airflow.utils.task_group import TaskGroup

@dag(dag_id="vendas_pipeline_completo", schedule="0 5 * * *", catchup=False)
def pipeline():

    with TaskGroup("extracao", tooltip="Extração das fontes") as tg_extracao:
        @task()
        def extrair_erp(): ...

        @task()
        def extrair_crm(): ...

    with TaskGroup("transformacao", tooltip="Transformações dbt") as tg_transf:
        @task.bash()
        def dbt_staging(): return "dbt run --select staging.*"

        @task.bash()
        def dbt_marts(): return "dbt run --select marts.*"

        dbt_staging() >> dbt_marts()

    with TaskGroup("qualidade", tooltip="Validações de dados") as tg_quality:
        @task()
        def testes_dbt(): ...

        @task()
        def freshness_check(): ...

    tg_extracao >> tg_transf >> tg_quality
```

## Pattern 2 — Branching Condicional

```python
from airflow.operators.python import BranchPythonOperator

@dag(dag_id="carga_condicional")
def pipeline():

    @task()
    def verificar_volume() -> dict:
        # Verifica se há dados novos para processar
        count = consultar_clickhouse("SELECT count() FROM raw.vendas WHERE processado = 0")
        return {"tem_dados": count > 0, "count": count}

    @task.branch()
    def decidir_processamento(info: dict) -> str:
        if info["tem_dados"]:
            return "processar_dados"
        return "skip_sem_dados"

    @task()
    def processar_dados(info: dict): ...

    @task()
    def skip_sem_dados():
        logger.info("Nenhum dado novo para processar")

    info = verificar_volume()
    branch = decidir_processamento(info)
    branch >> [processar_dados(info), skip_sem_dados()]
```

## Pattern 3 — Callbacks e Alertas

```python
from airflow.utils.email import send_email

def on_failure_callback(context: dict) -> None:
    """Callback executado quando qualquer task falha."""
    dag_id = context["dag"].dag_id
    task_id = context["task_instance"].task_id
    execution_date = context["execution_date"]
    log_url = context["task_instance"].log_url
    exception = context.get("exception", "")

    # Slack notification
    send_slack_alert(
        message=f"❌ Falha em {dag_id}.{task_id}\n"
                f"Data: {execution_date}\n"
                f"Erro: {exception}\n"
                f"Logs: {log_url}"
    )

def on_sla_miss_callback(dag, task_list, blocking_task_list, slas, blocking_tis):
    """Callback quando SLA é violado."""
    send_slack_alert(f"⏰ SLA violado na DAG {dag.dag_id}: {task_list}")

DEFAULT_ARGS = {
    "owner": "data-engineering",
    "on_failure_callback": on_failure_callback,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
}

@dag(
    sla_miss_callback=on_sla_miss_callback,
    default_args=DEFAULT_ARGS,
)
def pipeline_com_alertas():
    @task(sla=timedelta(hours=2))  # SLA por task
    def tarefa_critica(): ...
```

## Pattern 4 — DAG Dinâmica (múltiplos clientes/lojas)

```python
@dag(dag_id="processamento_por_loja", schedule="0 6 * * *")
def pipeline():

    @task()
    def listar_lojas_ativas() -> list[dict]:
        """Retorna lista de lojas para processar."""
        return consultar_clickhouse("""
            SELECT loja_id, nome, timezone
            FROM analytics.dim_lojas
            WHERE ativo = 1
        """)

    @task()
    def processar_loja(loja: dict) -> dict:
        """Processa dados de uma loja específica."""
        logger.info(f"Processando loja {loja['nome']} (id={loja['loja_id']})")
        # lógica específica por loja
        return {"loja_id": loja["loja_id"], "status": "ok"}

    lojas = listar_lojas_ativas()
    # .expand() cria uma task por elemento da lista (dynamic task mapping)
    processar_loja.expand(loja=lojas)
```

## Pattern 5 — Sensor de Disponibilidade de Dados

```python
from airflow.sensors.base import BaseSensorOperator

class ClickHouseSensor(BaseSensorOperator):
    """Aguarda dados no ClickHouse antes de prosseguir."""

    def __init__(self, query: str, conn_id: str = "clickhouse_default", **kwargs):
        super().__init__(**kwargs)
        self.query = query
        self.conn_id = conn_id

    def poke(self, context) -> bool:
        from airflow.hooks.base import BaseHook
        import clickhouse_connect

        conn = BaseHook.get_connection(self.conn_id)
        client = clickhouse_connect.get_client(...)
        result = client.query(self.query)
        count = result.first_row[0]
        self.log.info(f"Sensor check: {count} registros encontrados")
        return count > 0

# Uso na DAG:
aguardar_dados = ClickHouseSensor(
    task_id="aguardar_dados_erp",
    query="SELECT count() FROM raw.vendas WHERE data_carga = today()",
    poke_interval=300,   # checar a cada 5 min
    timeout=7200,        # timeout em 2h
    mode="reschedule",   # libera worker enquanto espera
)
```

## Pattern 6 — Carga Incremental com Watermark

```python
@task()
def extrair_incremental(ti=None) -> dict:
    """Extrai dados desde o último processamento."""
    from airflow.models import Variable

    # Recuperar último watermark (ou default)
    last_watermark = Variable.get(
        "vendas_last_watermark",
        default_var="2020-01-01T00:00:00"
    )

    dados = consultar_fonte_externa(f"""
        SELECT * FROM vendas
        WHERE atualizado_em > '{last_watermark}'
        ORDER BY atualizado_em
        LIMIT 100000
    """)

    return {"dados": dados, "watermark_anterior": last_watermark}

@task()
def atualizar_watermark(resultado: dict) -> None:
    """Atualiza watermark após carga bem-sucedida."""
    from airflow.models import Variable
    import datetime

    novo_watermark = datetime.datetime.utcnow().isoformat()
    Variable.set("vendas_last_watermark", novo_watermark)
    logger.info(f"Watermark atualizado: {novo_watermark}")
```

## Debugging Rápido

```bash
# Ver últimas execuções de uma DAG
airflow dags list-runs -d nome_dag --limit 10

# Limpar e re-executar tasks com falha
airflow tasks clear nome_dag -t nome_task --start-date 2024-01-01

# Forçar execução agora
airflow dags trigger nome_dag

# Ver XCom de uma task
airflow tasks xcom-get nome_dag nome_task 2024-01-01 --key return_value
```
