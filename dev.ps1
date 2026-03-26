param(
    [Parameter(Position = 0)]
    [string]$Command = "help",
    [string]$Dag,
    [string]$Task,
    [string]$Date = "2024-01-01",
    [string]$Sql,
    [string]$Model,
    [string]$Dash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$COMPOSE_FILE = "docker-compose.dev.yml"

function Write-Header($msg) { Write-Host ""; Write-Host $msg -ForegroundColor Cyan }
function Write-Ok($msg)     { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg)   { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)    { Write-Host "  [ERR]  $msg" -ForegroundColor Red }

function Invoke-Compose {
    param([string[]]$ComposeArgs)
    docker compose -f $COMPOSE_FILE @ComposeArgs
    if ($LASTEXITCODE -ne 0) { Write-Err "docker compose falhou (exit $LASTEXITCODE)"; exit $LASTEXITCODE }
}

function Assert-Param($value, $name, $example) {
    if (-not $value) { Write-Err "Parametro -$name obrigatorio. Ex: .\dev.ps1 $Command $example"; exit 1 }
}

# --- Help -------------------------------------------------------------------

function Show-Help {
    Write-Host ""
    Write-Host "BI Platform - Comandos disponiveis" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Desenvolvimento Local:" -ForegroundColor White
    Write-Host "  .\dev.ps1 dev-up              Sobe todo o stack (Airflow + ClickHouse + Superset)"
    Write-Host "  .\dev.ps1 dev-down            Derruba todo o stack"
    Write-Host "  .\dev.ps1 dev-restart         Reinicia o stack"
    Write-Host "  .\dev.ps1 dev-status          Status dos servicos"
    Write-Host "  .\dev.ps1 dev-logs            Logs de todos os servicos"
    Write-Host ""
    Write-Host "Airflow:" -ForegroundColor White
    Write-Host "  .\dev.ps1 airflow-up          Sobe apenas o Airflow"
    Write-Host "  .\dev.ps1 airflow-down        Para o Airflow"
    Write-Host "  .\dev.ps1 airflow-logs        Logs do scheduler"
    Write-Host "  .\dev.ps1 airflow-list        Lista todas as DAGs"
    Write-Host "  .\dev.ps1 airflow-test -Dag nome -Task nome [-Date YYYY-MM-DD]"
    Write-Host "  .\dev.ps1 airflow-validate    Valida imports de todas as DAGs"
    Write-Host ""
    Write-Host "ClickHouse:" -ForegroundColor White
    Write-Host "  .\dev.ps1 ch-shell            Abre shell interativo"
    Write-Host "  .\dev.ps1 ch-query -Sql 'SELECT 1'"
    Write-Host "  .\dev.ps1 ch-migrate          Aplica migrations pendentes"
    Write-Host "  .\dev.ps1 ch-tables           Lista tabelas do schema analytics"
    Write-Host "  .\dev.ps1 ch-status           Status do ClickHouse"
    Write-Host ""
    Write-Host "dbt:" -ForegroundColor White
    Write-Host "  .\dev.ps1 dbt-run             Executa todos os modelos"
    Write-Host "  .\dev.ps1 dbt-test            Roda todos os testes"
    Write-Host "  .\dev.ps1 dbt-docs            Gera e abre documentacao"
    Write-Host "  .\dev.ps1 dbt-fresh           Full refresh de todos os modelos"
    Write-Host "  .\dev.ps1 dbt-select -Model stg_crm__contatos"
    Write-Host "  .\dev.ps1 dbt-lint            Valida SQL dos modelos"
    Write-Host ""
    Write-Host "Superset:" -ForegroundColor White
    Write-Host "  .\dev.ps1 superset-up         Sobe apenas o Superset"
    Write-Host "  .\dev.ps1 superset-import -Dash dashboards/superset/arquivo.zip"
    Write-Host "  .\dev.ps1 superset-export     Exporta todos os dashboards"
    Write-Host ""
    Write-Host "Qualidade:" -ForegroundColor White
    Write-Host "  .\dev.ps1 test               Roda todos os testes com cobertura"
    Write-Host "  .\dev.ps1 test-unit          Apenas testes unitarios"
    Write-Host "  .\dev.ps1 test-integration   Apenas testes de integracao"
    Write-Host "  .\dev.ps1 lint               Linting completo (ruff)"
    Write-Host "  .\dev.ps1 fmt                Auto-formata codigo (black + ruff)"
    Write-Host "  .\dev.ps1 typecheck          Verificacao de tipos (mypy)"
    Write-Host "  .\dev.ps1 check              lint + typecheck + test (pre-PR)"
    Write-Host ""
    Write-Host "Setup:" -ForegroundColor White
    Write-Host "  .\dev.ps1 install            Instala dependencias de desenvolvimento"
    Write-Host "  .\dev.ps1 env-setup          Cria .env a partir do .env.example"
    Write-Host ""
}

# --- Dev Stack --------------------------------------------------------------

function Invoke-DevUp {
    Write-Header "Subindo BI Platform..."
    if (-not (Test-Path ".env")) {
        Copy-Item ".env.example" ".env"
        Write-Warn ".env criado a partir do .env.example - revise as variaveis antes de usar."
    }
    Invoke-Compose "up", "-d"
    Write-Host ""
    Write-Host "Stack disponivel em:" -ForegroundColor Cyan
    Write-Host "  * Airflow:    http://localhost:8080  (admin/admin)"
    Write-Host "  * Superset:   http://localhost:8088  (admin/admin)"
    Write-Host "  * ClickHouse: http://localhost:8123"
    Write-Host ""
}

function Invoke-DevDown    { Write-Header "Derrubando stack..."; Invoke-Compose "down" }
function Invoke-DevRestart { Invoke-DevDown; Invoke-DevUp }
function Invoke-DevStatus  { Invoke-Compose "ps" }
function Invoke-DevLogs    { Invoke-Compose "logs", "-f", "--tail=50" }

# --- Airflow ----------------------------------------------------------------

function Invoke-AirflowUp {
    Write-Header "Subindo Airflow..."
    Invoke-Compose "up", "-d", "airflow-webserver", "airflow-scheduler", "postgres"
}

function Invoke-AirflowDown { Invoke-Compose "stop", "airflow-webserver", "airflow-scheduler" }
function Invoke-AirflowLogs { Invoke-Compose "logs", "-f", "airflow-scheduler" }
function Invoke-AirflowList { Invoke-Compose "exec", "airflow-scheduler", "airflow", "dags", "list" }

function Invoke-AirflowTest {
    Assert-Param $Dag "Dag" "-Dag vendas_ingestao_diaria -Task extrair_dados"
    $taskName = if ($Task) { $Task } else { "extrair_dados" }
    Invoke-Compose "exec", "airflow-scheduler", "airflow", "tasks", "test", $Dag, $taskName, $Date
}

function Invoke-AirflowValidate {
    Write-Header "Validando DAGs..."
    $pyLines = @(
        "import os, importlib.util, sys",
        "errors = []",
        "for root, dirs, files in os.walk('dags'):",
        "    for f in files:",
        "        if not f.endswith('.py') or f.startswith('_'): continue",
        "        path = os.path.join(root, f)",
        "        try:",
        "            spec = importlib.util.spec_from_file_location('m', path)",
        "            mod  = importlib.util.module_from_spec(spec)",
        "            spec.loader.exec_module(mod)",
        "            print('OK  ' + path)",
        "        except Exception as e:",
        "            print('FAIL ' + path + ': ' + str(e))",
        "            errors.append(path)",
        "sys.exit(len(errors))"
    )
    $pyScript = $pyLines -join "`n"
    python -c $pyScript
    if ($LASTEXITCODE -eq 0) { Write-Ok "Todas as DAGs validas" }
    else { Write-Err "DAGs com erro de importacao detectadas"; exit 1 }
}

# --- ClickHouse -------------------------------------------------------------

function Invoke-ChShell {
    Invoke-Compose "exec", "clickhouse", "clickhouse-client", "--user=clickhouse", "--password=clickhouse"
}

function Invoke-ChQuery {
    Assert-Param $Sql "Sql" "-Sql 'SELECT 1'"
    Invoke-Compose "exec", "clickhouse", "clickhouse-client",
        "--user=clickhouse", "--password=clickhouse", "--query=$Sql"
}

function Invoke-ChMigrate {
    Write-Header "Rodando migrations ClickHouse..."
    python scripts/migration/run_migrations.py --env local
}

function Invoke-ChTables {
    $Sql = "SELECT database, name, engine, formatReadableSize(total_bytes) AS size" +
           " FROM system.tables WHERE database NOT IN ('system','information_schema')" +
           " ORDER BY database, name"
    Invoke-ChQuery
}

function Invoke-ChStatus {
    $Sql = "SELECT version(), uptime() AS uptime_seconds FROM system.asynchronous_metrics LIMIT 1"
    Invoke-ChQuery
}

# --- dbt --------------------------------------------------------------------

$DBT_ARGS = @("--project-dir", "dbt", "--profiles-dir", "dbt", "--profile", "local")

function Invoke-DbtRun   { dbt run   @DBT_ARGS }
function Invoke-DbtTest  { dbt test  @DBT_ARGS }
function Invoke-DbtFresh { dbt run   @DBT_ARGS --full-refresh }
function Invoke-DbtLint  { dbt parse @DBT_ARGS; Write-Ok "dbt: SQL valido" }

function Invoke-DbtDocs {
    dbt docs generate @DBT_ARGS
    dbt docs serve @DBT_ARGS
}

function Invoke-DbtSelect {
    Assert-Param $Model "Model" "-Model stg_crm__contatos"
    dbt run @DBT_ARGS --select "$Model+"
}

# --- Superset ---------------------------------------------------------------

function Invoke-SupersetUp {
    Write-Header "Subindo Superset..."
    Invoke-Compose "up", "-d", "superset", "redis", "postgres"
}

function Invoke-SupersetImport {
    Assert-Param $Dash "Dash" "-Dash dashboards/superset/arquivo.zip"
    $fileName = Split-Path $Dash -Leaf
    Invoke-Compose "exec", "superset", "superset", "import-dashboards",
        "-p", "/app/superset_home/exports/$fileName"
}

function Invoke-SupersetExport {
    $dateStr = Get-Date -Format "yyyyMMdd"
    Invoke-Compose "exec", "superset", "superset", "export-dashboards",
        "-f", "/app/superset_home/exports/export_$dateStr.zip"
    Write-Ok "Exportado: dashboards/superset/export_$dateStr.zip"
}

# --- Qualidade --------------------------------------------------------------

function Invoke-Test {
    Write-Header "Rodando testes..."
    pytest tests/ --cov=dags --cov=scripts --cov-report=term-missing "--cov-report=html:htmlcov" --cov-fail-under=70 -v
}

function Invoke-TestUnit        { pytest tests/unit/ -v }
function Invoke-TestIntegration { pytest tests/integration/ -v -m integration }

function Invoke-Lint {
    Write-Header "Executando linting..."
    ruff check .
    Write-Ok "Ruff: OK"
}

function Invoke-Fmt {
    Write-Header "Formatando codigo..."
    black .
    ruff check --fix .
    Write-Ok "Formatacao concluida"
}

function Invoke-Typecheck {
    Write-Header "Verificando tipos..."
    mypy dags/ scripts/ --ignore-missing-imports
    Write-Ok "Tipos: OK"
}

function Invoke-Check {
    Invoke-Lint
    Invoke-Typecheck
    Invoke-Test
    Write-Host ""
    Write-Ok "Todos os checks passaram! Pronto para PR."
}

# --- Setup ------------------------------------------------------------------

function Invoke-Install {
    Write-Header "Instalando dependencias..."
    pip install -r requirements.txt
    pip install -r requirements-dev.txt
    Push-Location dbt; dbt deps; Pop-Location
    Write-Ok "Dependencias instaladas"
}

function Invoke-EnvSetup {
    if (Test-Path ".env") {
        Write-Warn ".env ja existe - nao sobrescrevendo."
    } else {
        Copy-Item ".env.example" ".env"
        Write-Warn ".env criado. Preencha as variaveis antes de usar."
    }
}

# --- Dispatcher -------------------------------------------------------------

switch ($Command) {
    "help"              { Show-Help }
    "dev-up"            { Invoke-DevUp }
    "dev-down"          { Invoke-DevDown }
    "dev-restart"       { Invoke-DevRestart }
    "dev-status"        { Invoke-DevStatus }
    "dev-logs"          { Invoke-DevLogs }
    "airflow-up"        { Invoke-AirflowUp }
    "airflow-down"      { Invoke-AirflowDown }
    "airflow-logs"      { Invoke-AirflowLogs }
    "airflow-list"      { Invoke-AirflowList }
    "airflow-test"      { Invoke-AirflowTest }
    "airflow-validate"  { Invoke-AirflowValidate }
    "ch-shell"          { Invoke-ChShell }
    "ch-query"          { Invoke-ChQuery }
    "ch-migrate"        { Invoke-ChMigrate }
    "ch-tables"         { Invoke-ChTables }
    "ch-status"         { Invoke-ChStatus }
    "dbt-run"           { Invoke-DbtRun }
    "dbt-test"          { Invoke-DbtTest }
    "dbt-docs"          { Invoke-DbtDocs }
    "dbt-fresh"         { Invoke-DbtFresh }
    "dbt-select"        { Invoke-DbtSelect }
    "dbt-lint"          { Invoke-DbtLint }
    "superset-up"       { Invoke-SupersetUp }
    "superset-import"   { Invoke-SupersetImport }
    "superset-export"   { Invoke-SupersetExport }
    "test"              { Invoke-Test }
    "test-unit"         { Invoke-TestUnit }
    "test-integration"  { Invoke-TestIntegration }
    "lint"              { Invoke-Lint }
    "fmt"               { Invoke-Fmt }
    "typecheck"         { Invoke-Typecheck }
    "check"             { Invoke-Check }
    "install"           { Invoke-Install }
    "env-setup"         { Invoke-EnvSetup }
    default {
        Write-Err "Comando desconhecido: '$Command'"
        Write-Host "Execute '.\dev.ps1 help' para ver os comandos disponiveis."
        exit 1
    }
}
