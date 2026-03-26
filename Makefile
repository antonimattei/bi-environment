.PHONY: help dev-up dev-down dev-restart \
        airflow-up airflow-down airflow-logs airflow-test \
        ch-query ch-migrate ch-shell \
        dbt-run dbt-test dbt-docs dbt-fresh \
        superset-up superset-import \
        test lint fmt typecheck \
        git-setup pre-commit install

# ─── Cores ────────────────────────────────────────────────────────────
BOLD  := \033[1m
GREEN := \033[32m
YELLOW:= \033[33m
BLUE  := \033[34m
RESET := \033[0m

## help: Lista todos os comandos disponíveis
help:
	@echo ""
	@echo "$(BOLD)$(BLUE)🚀 BI Platform — Comandos$(RESET)"
	@echo ""
	@echo "$(BOLD)Desenvolvimento Local:$(RESET)"
	@echo "  $(GREEN)make dev-up$(RESET)               Sobe todo o stack (Airflow + ClickHouse + Superset)"
	@echo "  $(GREEN)make dev-down$(RESET)             Derruba todo o stack"
	@echo "  $(GREEN)make dev-restart$(RESET)          Reinicia o stack"
	@echo ""
	@echo "$(BOLD)Airflow:$(RESET)"
	@echo "  $(GREEN)make airflow-up$(RESET)           Sobe apenas o Airflow"
	@echo "  $(GREEN)make airflow-logs$(RESET)         Logs do scheduler"
	@echo "  $(GREEN)make airflow-test DAG=nome$(RESET) Testa uma DAG específica"
	@echo "  $(GREEN)make airflow-list$(RESET)         Lista todas as DAGs"
	@echo ""
	@echo "$(BOLD)ClickHouse:$(RESET)"
	@echo "  $(GREEN)make ch-query SQL='...'$(RESET)   Executa query SQL"
	@echo "  $(GREEN)make ch-migrate$(RESET)           Aplica migrations pendentes"
	@echo "  $(GREEN)make ch-shell$(RESET)             Abre shell interativo"
	@echo "  $(GREEN)make ch-tables$(RESET)            Lista tabelas do schema analytics"
	@echo ""
	@echo "$(BOLD)dbt:$(RESET)"
	@echo "  $(GREEN)make dbt-run$(RESET)              Executa todos os modelos"
	@echo "  $(GREEN)make dbt-test$(RESET)             Roda todos os testes"
	@echo "  $(GREEN)make dbt-docs$(RESET)             Gera e abre documentação"
	@echo "  $(GREEN)make dbt-fresh$(RESET)            Full refresh de todos os modelos"
	@echo ""
	@echo "$(BOLD)Superset:$(RESET)"
	@echo "  $(GREEN)make superset-up$(RESET)          Sobe apenas o Superset"
	@echo "  $(GREEN)make superset-import DASH=f.zip$(RESET) Importa dashboard"
	@echo ""
	@echo "$(BOLD)Qualidade:$(RESET)"
	@echo "  $(GREEN)make test$(RESET)                 Roda todos os testes"
	@echo "  $(GREEN)make lint$(RESET)                 Linting completo"
	@echo "  $(GREEN)make fmt$(RESET)                  Auto-formata código"
	@echo "  $(GREEN)make typecheck$(RESET)            Verificação de tipos"
	@echo ""
	@echo "$(BOLD)Setup:$(RESET)"
	@echo "  $(GREEN)make install$(RESET)              Instala dependências de desenvolvimento"
	@echo "  $(GREEN)make git-setup$(RESET)            Configura hooks Git locais"
	@echo ""

# ─── Dev Stack ───────────────────────────────────────────────────────

## dev-up: Sobe todo o stack de desenvolvimento
dev-up:
	@echo "$(BOLD)$(GREEN)🚀 Subindo BI Platform...$(RESET)"
	@cp -n .env.example .env 2>/dev/null || true
	docker compose -f docker-compose.dev.yml up -d
	@echo ""
	@echo "$(BOLD)✅ Stack disponível em:$(RESET)"
	@echo "  • Airflow:    http://localhost:8080  (admin/admin)"
	@echo "  • Superset:   http://localhost:8088  (admin/admin)"
	@echo "  • ClickHouse: http://localhost:8123"
	@echo ""

## dev-down: Derruba todo o stack
dev-down:
	docker compose -f docker-compose.dev.yml down

## dev-restart: Reinicia o stack
dev-restart: dev-down dev-up

## dev-status: Status dos serviços
dev-status:
	docker compose -f docker-compose.dev.yml ps

## dev-logs: Todos os logs
dev-logs:
	docker compose -f docker-compose.dev.yml logs -f --tail=50

# ─── Airflow ─────────────────────────────────────────────────────────

## airflow-up: Sobe apenas serviços Airflow
airflow-up:
	docker compose -f docker-compose.dev.yml up -d airflow-webserver airflow-scheduler postgres

## airflow-down: Para o Airflow
airflow-down:
	docker compose -f docker-compose.dev.yml stop airflow-webserver airflow-scheduler

## airflow-logs: Logs do scheduler
airflow-logs:
	docker compose -f docker-compose.dev.yml logs -f airflow-scheduler

## airflow-list: Lista DAGs
airflow-list:
	docker compose -f docker-compose.dev.yml exec airflow-scheduler \
		airflow dags list

## airflow-test: Testa task específica (DAG= e TASK= obrigatórios)
airflow-test:
ifndef DAG
	$(error ❌ Use: make airflow-test DAG=nome_dag TASK=nome_task DATE=2024-01-01)
endif
	docker compose -f docker-compose.dev.yml exec airflow-scheduler \
		airflow tasks test $(DAG) $(or $(TASK),extrair_dados) $(or $(DATE),2024-01-01)

## airflow-validate: Valida imports de todas as DAGs
airflow-validate:
	@echo "$(BOLD)🔍 Validando DAGs...$(RESET)"
	@python -c "\
import os, importlib.util, sys; \
errs=[]; \
[errs.append(f) or print(f'❌ {f}') \
  if not (lambda s,m: (s.loader.exec_module(m), print(f'✅ {f}')))(importlib.util.spec_from_file_location('m',f),importlib.util.module_from_spec(importlib.util.spec_from_file_location('m',f))) \
  else None \
  for r,d,fs in os.walk('dags') for f in fs if f.endswith('.py') and not f.startswith('_')]; \
sys.exit(len(errs))"

# ─── ClickHouse ──────────────────────────────────────────────────────

## ch-shell: Abre shell interativo no ClickHouse
ch-shell:
	docker compose -f docker-compose.dev.yml exec clickhouse \
		clickhouse-client --user=clickhouse --password=clickhouse

## ch-query: Executa query SQL (SQL='SELECT 1')
ch-query:
ifndef SQL
	$(error ❌ Use: make ch-query SQL="SELECT 1")
endif
	docker compose -f docker-compose.dev.yml exec clickhouse \
		clickhouse-client --user=clickhouse --password=clickhouse \
		--query="$(SQL)"

## ch-migrate: Aplica migrations pendentes
ch-migrate:
	@echo "$(BOLD)🗄️  Rodando migrations ClickHouse...$(RESET)"
	python scripts/migration/run_migrations.py --env local

## ch-tables: Lista tabelas do schema analytics
ch-tables:
	@make ch-query SQL="SELECT database, name, engine, formatReadableSize(total_bytes) AS size FROM system.tables WHERE database NOT IN ('system','information_schema') ORDER BY database, name"

## ch-status: Status do ClickHouse
ch-status:
	@make ch-query SQL="SELECT version(), uptime() AS uptime_seconds, formatReadableSize(memory_usage) AS memory FROM system.asynchronous_metrics LIMIT 1"

# ─── dbt ─────────────────────────────────────────────────────────────

DBT_FLAGS = --project-dir dbt --profiles-dir dbt --profile local

## dbt-run: Executa todos os modelos dbt
dbt-run:
	dbt run $(DBT_FLAGS)

## dbt-test: Roda testes dbt
dbt-test:
	dbt test $(DBT_FLAGS)

## dbt-docs: Gera documentação e abre no browser
dbt-docs:
	dbt docs generate $(DBT_FLAGS)
	dbt docs serve $(DBT_FLAGS)

## dbt-fresh: Full refresh de todos os modelos
dbt-fresh:
	dbt run $(DBT_FLAGS) --full-refresh

## dbt-select: Roda modelo específico (MODEL=nome)
dbt-select:
ifndef MODEL
	$(error ❌ Use: make dbt-select MODEL=stg_crm__contatos)
endif
	dbt run $(DBT_FLAGS) --select $(MODEL)+

## dbt-lint: Valida SQL dos modelos
dbt-lint:
	dbt parse $(DBT_FLAGS)
	@echo "$(GREEN)✅ dbt: SQL válido$(RESET)"

# ─── Superset ────────────────────────────────────────────────────────

## superset-up: Sobe apenas o Superset
superset-up:
	docker compose -f docker-compose.dev.yml up -d superset redis postgres

## superset-import: Importa dashboard (DASH=arquivo.zip)
superset-import:
ifndef DASH
	$(error ❌ Use: make superset-import DASH=dashboards/superset/arquivo.zip)
endif
	docker compose -f docker-compose.dev.yml exec superset \
		superset import-dashboards -p /app/superset_home/exports/$(notdir $(DASH))

## superset-export: Exporta todos os dashboards
superset-export:
	docker compose -f docker-compose.dev.yml exec superset \
		superset export-dashboards -f /app/superset_home/exports/export_$(shell date +%Y%m%d).zip
	@echo "$(GREEN)✅ Exportado para dashboards/superset/export_$(shell date +%Y%m%d).zip$(RESET)"

# ─── Qualidade de Código ─────────────────────────────────────────────

## test: Roda todos os testes com cobertura
test:
	@echo "$(BOLD)🧪 Rodando testes...$(RESET)"
	pytest tests/ \
		--cov=dags \
		--cov=scripts \
		--cov-report=term-missing \
		--cov-report=html:htmlcov \
		--cov-fail-under=70 \
		-v

## test-unit: Apenas testes unitários
test-unit:
	pytest tests/unit/ -v

## test-integration: Apenas testes de integração
test-integration:
	pytest tests/integration/ -v -m integration

## lint: Linting completo
lint:
	@echo "$(BOLD)🔍 Executando linting...$(RESET)"
	ruff check .
	@echo "$(GREEN)✅ Ruff: OK$(RESET)"

## fmt: Auto-formata todo o código
fmt:
	@echo "$(BOLD)✨ Formatando código...$(RESET)"
	black .
	ruff check --fix .
	@echo "$(GREEN)✅ Formatação concluída$(RESET)"

## typecheck: Verificação de tipos com mypy
typecheck:
	@echo "$(BOLD)🔎 Verificando tipos...$(RESET)"
	mypy dags/ scripts/ --ignore-missing-imports
	@echo "$(GREEN)✅ Tipos: OK$(RESET)"

## check: Roda lint + typecheck + testes (pré-PR)
check: lint typecheck test
	@echo ""
	@echo "$(BOLD)$(GREEN)🎉 Todos os checks passaram! Pronto para PR.$(RESET)"

# ─── Setup ───────────────────────────────────────────────────────────

## install: Instala dependências de desenvolvimento
install:
	@echo "$(BOLD)📦 Instalando dependências...$(RESET)"
	pip install -r requirements.txt
	pip install -r requirements-dev.txt
	cd dbt && dbt deps
	@echo "$(GREEN)✅ Dependências instaladas$(RESET)"

## git-setup: Configura git hooks locais (pre-commit)
git-setup:
	@echo "$(BOLD)🔧 Configurando Git hooks...$(RESET)"
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit
	@echo "$(GREEN)✅ Git hooks configurados$(RESET)"
	@echo "  Branch protection: main e staging são protegidas"

## env-setup: Cria .env a partir do .env.example
env-setup:
	@cp -n .env.example .env
	@echo "$(YELLOW)⚠️  Arquivo .env criado. Preencha as variáveis antes de usar.$(RESET)"
