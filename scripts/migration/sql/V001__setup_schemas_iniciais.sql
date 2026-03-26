-- ════════════════════════════════════════════════════════════════════
-- V001__setup_schemas_iniciais.sql
-- Criação dos schemas base da plataforma BI
-- Author: time-bi
-- Date: 2024-01-01
-- ════════════════════════════════════════════════════════════════════

-- Schema para dados brutos (sem transformação)
CREATE DATABASE IF NOT EXISTS raw;

-- Schema para dados analíticos (fatos e dimensões)
CREATE DATABASE IF NOT EXISTS analytics;

-- Schema para views e agregações materializadas
CREATE DATABASE IF NOT EXISTS reporting;

-- ─── Tabela de Auditoria de Pipeline ─────────────────────────────────
CREATE TABLE IF NOT EXISTS analytics.pipeline_audit
(
    run_id          UUID DEFAULT generateUUIDv4(),
    dag_id          LowCardinality(String),
    task_id         LowCardinality(String),
    execution_date  DateTime,
    start_time      DateTime DEFAULT now(),
    end_time        Nullable(DateTime),
    status          LowCardinality(String) DEFAULT 'running',
    rows_processed  UInt64 DEFAULT 0,
    error_message   Nullable(String),
    metadata        String DEFAULT '{}'
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(execution_date)
ORDER BY (dag_id, execution_date, run_id)
SETTINGS index_granularity = 8192;

-- ─── Tabela de Metadados de Fontes ───────────────────────────────────
CREATE TABLE IF NOT EXISTS analytics.source_metadata
(
    source_id       UInt32,
    source_name     LowCardinality(String),
    source_type     LowCardinality(String),  -- 'database', 'api', 'file'
    connection_id   String,
    schema_name     String,
    table_name      String,
    last_synced_at  Nullable(DateTime),
    row_count       UInt64 DEFAULT 0,
    active          UInt8 DEFAULT 1,
    created_at      DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(created_at)
ORDER BY (source_id)
SETTINGS index_granularity = 8192;
