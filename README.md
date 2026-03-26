# 🚀 BI Platform

Plataforma de dados analíticos com Apache Airflow, ClickHouse, dbt e Apache Superset.

## Stack

| Componente | Tecnologia | Porta local |
|---|---|---|
| Orquestração | Apache Airflow 2.9 | :8080 |
| Data Warehouse | ClickHouse 24.3 | :8123 / :9000 |
| Transformação | dbt-core + dbt-clickhouse | — |
| Visualização | Apache Superset | :8088 |
| Metastore | PostgreSQL 15 | :5432 |
| Cache | Redis 7 | :6379 |

## Início Rápido

```bash
# 1. Clonar e entrar no projeto
git clone https://github.com/empresa/bi-platform.git && cd bi-platform

# 2. Instalar dependências Python
make install

# 3. Configurar git hooks (bloqueia commits ruins)
make git-setup

# 4. Criar .env
make env-setup
# Edite o .env com suas configurações locais

# 5. Subir o stack completo
make dev-up

# Pronto! Acesse:
# Airflow:  http://localhost:8080  (admin/admin)
# Superset: http://localhost:8088  (admin/admin)
```

## Estrutura do Projeto

```
bi-platform/
├── CLAUDE.md              # Memória do projeto (Claude Code)
├── .claude/
│   ├── settings.json      # Hooks e permissões
│   ├── agents/            # Agentes: python, airflow, clickhouse, superset
│   ├── skills/            # Skills: bi-pipeline, data-quality, sql-optimization
│   └── commands/          # Slash commands: /new-dag, /deploy
├── dags/                  # DAGs do Airflow
├── dbt/                   # Modelos dbt
│   ├── models/staging/    # Dados brutos normalizados
│   ├── models/marts/      # Tabelas analíticas finais
│   └── macros/            # Macros reutilizáveis
├── scripts/migration/     # Migrations ClickHouse (Vxxx__descricao.sql)
├── dashboards/superset/   # Exports de dashboards (versionados)
├── tests/                 # Testes automatizados
└── .github/workflows/     # CI (testes) + CD (deploy staging/prod)
```

## Pipelines Ativos

| Pipeline | Frequência | Fonte | Destino | Owner |
|---|---|---|---|---|
| `vendas_ingestao_diaria` | Diária 05:00 | ERP | `analytics.fact_vendas` | time-bi |

## Fluxo Git

```
feature/xxx  ──→  develop  ──→  staging  ──→  main
                                  ↓               ↓
                             (deploy auto)   (deploy auto)
                              staging env    produção
```

- **Branches protegidas**: `main` e `staging` (sem push direto)
- **PRs obrigatórios** com pelo menos 1 aprovação
- **CI automático**: lint + testes + validação DAGs + dbt parse + secret scan

## Convenções de Commit

```
feat: nova funcionalidade
fix: correção de bug
dag: nova ou alteração em DAG
data: mudança em schema ou migration
chore: manutenção, dependências
docs: documentação
```

## Comandos Mais Usados

```bash
make help              # Lista todos os comandos
make dev-up            # Sobe o stack local
make test              # Roda todos os testes
make lint              # Verifica qualidade do código
make fmt               # Auto-formata o código
make ch-tables         # Lista tabelas ClickHouse
make dbt-run           # Executa modelos dbt
make airflow-list      # Lista DAGs
```

## Claude Code

Este projeto usa Claude Code com configuração especializada em BI:

```bash
# Iniciar Claude Code no projeto
claude

# Agentes disponíveis
# - python-expert     → código Python de alta qualidade
# - airflow-expert    → DAGs e orquestração
# - clickhouse-expert → schema e queries
# - superset-expert   → dashboards e datasets

# Slash commands
/new-dag     # Cria nova DAG com wizard interativo
/deploy      # Guia de deploy com checklist de segurança
```
