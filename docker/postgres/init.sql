-- init.sql — Inicialização do PostgreSQL
-- Executado automaticamente pelo postgres:15-alpine na primeira inicialização.
-- O banco "airflow" já é criado via POSTGRES_DB=airflow no docker-compose.
-- Este script cria os bancos e usuários adicionais necessários.

-- Banco de dados do Superset (metastore separado do Airflow)
SELECT 'CREATE DATABASE superset'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'superset'
)\gexec

-- Garantir que o usuário airflow tenha acesso total ao banco superset
GRANT ALL PRIVILEGES ON DATABASE superset TO airflow;
