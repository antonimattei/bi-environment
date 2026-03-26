# 🧠 BI Platform — Claude Code Memory

## Stack Principal
- **Orquestração**: Apache Airflow 2.x
- **Data Warehouse**: ClickHouse (OLAP, colunar)
- **Transformação**: dbt-core + dbt-clickhouse
- **Visualização**: Apache Superset
- **Linguagem principal**: Python 3.11+
- **Containerização**: Docker + Docker Compose
- **CI/CD**: GitHub Actions
- **Controle de versão**: Git (Gitflow)

---

## Estrutura do Projeto
```
bi-platform/
├── CLAUDE.md                  # Este arquivo (memória do projeto)
├── .claude/
│   ├── settings.json          # Hooks + permissões
│   ├── agents/                # Agentes especializados
│   ├── skills/                # Skills por domínio
│   └── commands/              # Slash commands /custom
├── dags/                      # DAGs do Airflow
│   ├── ingestion/             # Ingestão de dados
│   ├── transformation/        # Transformações
│   └── orchestration/         # DAGs de orquestração
├── dbt/                       # Modelos dbt
│   ├── models/staging/        # Camada bruta normalizada
│   ├── models/intermediate/   # Lógica de negócio intermediária
│   ├── models/marts/          # Tabelas analíticas finais
│   └── macros/                # Macros reutilizáveis
├── dashboards/superset/       # Exports JSON de dashboards
├── docker/                    # Dockerfiles customizados
├── scripts/                   # Utilitários de manutenção
├── tests/                     # Testes automatizados
└── .github/workflows/         # Pipelines CI/CD
```

---

## Convenções de Código

### Python
- Seguir PEP8 + Black formatter (linha máx: 100 chars)
- Type hints obrigatórios em funções públicas
- Docstrings no padrão Google Style
- Testes: pytest + pytest-airflow para DAGs
- Logging: sempre usar `logging.getLogger(__name__)`

### DAGs Airflow
- Nomenclatura: `{domínio}_{ação}_{frequência}` → `vendas_ingestao_diaria`
- Sempre definir `default_args` com `retries`, `retry_delay` e `email_on_failure`
- Usar `@dag` e `@task` decorators (TaskFlow API)
- Separar lógica de negócio da lógica de orquestração
- Conexões via Airflow Connections (nunca hardcode credenciais)
- Tags obrigatórias: domínio, frequência, responsável

### ClickHouse
- Tabelas de fato: `ENGINE = MergeTree` ou `ReplacingMergeTree`
- Tabelas de dimensão: `ENGINE = ReplacingMergeTree` com `ver`
- Naming: `schema.tipo_nome` → `analytics.fact_vendas`
- Índices: sempre definir `ORDER BY` pensando nas queries mais comuns
- Particionamento: `PARTITION BY toYYYYMM(data)` para tabelas históricas
- Evitar `SELECT *` — sempre especificar colunas

### dbt
- Staging: prefixo `stg_`, fonte única, sem lógica de negócio
- Intermediate: prefixo `int_`, joins e transformações
- Marts: sem prefixo, orientados ao negócio (ex: `dim_clientes`)
- Testes: `not_null`, `unique`, `accepted_values` em todas as PKs
- Documentação: toda coluna documentada no `schema.yml`

### Superset
- Datasets: sempre conectados via SQLAlchemy URI
- Filtros nativos nas queries (não em Python)
- Caches configurados para dashboards públicos

---

## Comandos Úteis
```bash
# Airflow
make airflow-up          # Sobe Airflow local
make airflow-test DAG=nome_dag   # Testa DAG específica
make airflow-logs DAG=nome_dag   # Ver logs

# ClickHouse
make ch-query SQL="SELECT 1"     # Executa query
make ch-migrate                  # Roda migrations pendentes

# dbt
make dbt-run                     # Executa todos os modelos
make dbt-test                    # Roda testes
make dbt-docs                    # Gera documentação

# Superset
make superset-up                 # Sobe Superset local
make superset-import DASH=arquivo.json  # Importa dashboard

# Dev
make dev-up                      # Sobe todo o stack local
make dev-down                    # Derruba stack
make test                        # Roda todos os testes
make lint                        # Linting completo
```

---

## Variáveis de Ambiente
Arquivo `.env` (nunca commitado — ver `.env.example`):
- `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`
- `AIRFLOW_FERNET_KEY`, `AIRFLOW_SECRET_KEY`
- `SUPERSET_SECRET_KEY`
- `POSTGRES_USER`, `POSTGRES_PASSWORD` (metastore)

---

## Branches e Fluxo Git
- `main` — produção (protegida, deploy automático)
- `staging` — homologação (deploy automático)
- `develop` — integração de features
- `feature/xxx` — novas funcionalidades
- `hotfix/xxx` — correções urgentes em produção

Commits: Conventional Commits (`feat:`, `fix:`, `chore:`, `data:`, `dag:`)

---

## Skills Disponíveis
- `bi-pipeline`: Criação de pipelines end-to-end BI
- `data-quality`: Validação e testes de qualidade de dados
- `sql-optimization`: Otimização de queries ClickHouse
- `airflow-patterns`: Padrões e boas práticas para DAGs

---

## Agentes Disponíveis
- `python-expert`: Código Python de alta qualidade, typing, testes
- `airflow-expert`: DAGs, operadores, TaskFlow, debugging
- `clickhouse-expert`: Schema design, queries, performance tuning
- `superset-expert`: Dashboards, datasets, charts, segurança

---

## Regras de Segurança (CRÍTICO)
- NUNCA commitar arquivos `.env` ou credenciais
- NUNCA executar comandos destrutivos em produção sem aprovação
- SEMPRE criar migration reversa junto com migration de schema
- SEMPRE testar DAGs em ambiente local antes de deploy
- Branches protegidas: `main` e `staging` — nunca editar diretamente
