"""
Migration runner para ClickHouse.

Aplica migrations SQL em ordem, rastreando quais já foram executadas.
Uso:
    python scripts/migration/run_migrations.py --env local
    python scripts/migration/run_migrations.py --env staging --host ch.staging.com
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import os
import sys
from datetime import datetime
from pathlib import Path

import clickhouse_connect

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

MIGRATIONS_DIR = Path(__file__).parent / "sql"
MIGRATION_TABLE = "system_migrations"
MIGRATION_DB = "bi_meta"


def get_client(env: str, host: str | None = None) -> clickhouse_connect.driver.Client:
    """Cria cliente ClickHouse para o ambiente especificado."""
    configs = {
        "local": {
            "host": host or os.getenv("CLICKHOUSE_HOST", "localhost"),
            "port": int(os.getenv("CLICKHOUSE_PORT", "8123")),
            "username": os.getenv("CLICKHOUSE_USER", "clickhouse"),
            "password": os.getenv("CLICKHOUSE_PASSWORD", "clickhouse"),
        },
        "staging": {
            "host": host or os.environ["CLICKHOUSE_HOST"],
            "port": int(os.getenv("CLICKHOUSE_PORT", "8123")),
            "username": os.environ["CLICKHOUSE_USER"],
            "password": os.environ["CLICKHOUSE_PASSWORD"],
        },
        "production": {
            "host": host or os.environ["CLICKHOUSE_HOST"],
            "port": int(os.getenv("CLICKHOUSE_PORT", "8443")),
            "username": os.environ["CLICKHOUSE_USER"],
            "password": os.environ["CLICKHOUSE_PASSWORD"],
            "secure": True,
        },
    }
    if env not in configs:
        raise ValueError(f"Ambiente inválido: {env}. Use: {list(configs.keys())}")

    logger.info(f"Conectando ao ClickHouse [{env}]: {configs[env]['host']}")
    return clickhouse_connect.get_client(**configs[env])


def ensure_migration_table(client: clickhouse_connect.driver.Client) -> None:
    """Garante que a tabela de controle de migrations existe."""
    client.command(f"CREATE DATABASE IF NOT EXISTS {MIGRATION_DB}")
    client.command(f"""
        CREATE TABLE IF NOT EXISTS {MIGRATION_DB}.{MIGRATION_TABLE}
        (
            migration_id    String,
            filename        String,
            checksum        String,
            applied_at      DateTime DEFAULT now(),
            applied_by      String DEFAULT currentUser(),
            success         UInt8
        )
        ENGINE = MergeTree()
        ORDER BY (applied_at, migration_id)
    """)


def get_applied_migrations(client: clickhouse_connect.driver.Client) -> set[str]:
    """Retorna IDs das migrations já aplicadas com sucesso."""
    result = client.query(f"""
        SELECT migration_id
        FROM {MIGRATION_DB}.{MIGRATION_TABLE}
        WHERE success = 1
    """)
    return {row[0] for row in result.result_rows}


def get_pending_migrations() -> list[Path]:
    """Retorna lista de arquivos de migration pendentes, em ordem."""
    if not MIGRATIONS_DIR.exists():
        logger.warning(f"Diretório de migrations não encontrado: {MIGRATIONS_DIR}")
        return []

    migrations = sorted(
        [f for f in MIGRATIONS_DIR.glob("V*.sql") if not f.name.endswith(".down.sql")],
        key=lambda f: f.name,
    )
    return migrations


def get_file_checksum(path: Path) -> str:
    """Calcula MD5 do arquivo de migration."""
    return hashlib.md5(path.read_bytes()).hexdigest()


def apply_migration(
    client: clickhouse_connect.driver.Client,
    migration_file: Path,
    dry_run: bool = False,
) -> bool:
    """Aplica uma migration SQL."""
    migration_id = migration_file.stem
    checksum = get_file_checksum(migration_file)
    sql = migration_file.read_text(encoding="utf-8")

    logger.info(f"  Aplicando: {migration_file.name}")

    if dry_run:
        logger.info(f"  [DRY RUN] Seria executado:\n{sql[:200]}...")
        return True

    try:
        # Executar cada statement separadamente (ClickHouse não suporta multi-statement)
        statements = [s.strip() for s in sql.split(";") if s.strip() and not s.strip().startswith("--")]
        for stmt in statements:
            if stmt:
                client.command(stmt)

        # Registrar sucesso
        client.insert(
            f"{MIGRATION_DB}.{MIGRATION_TABLE}",
            [[migration_id, migration_file.name, checksum, datetime.utcnow(), "migration_runner", 1]],
            column_names=["migration_id", "filename", "checksum", "applied_at", "applied_by", "success"],
        )
        logger.info(f"  ✅ {migration_file.name}")
        return True

    except Exception as e:
        logger.error(f"  ❌ Falha em {migration_file.name}: {e}")
        # Registrar falha
        client.insert(
            f"{MIGRATION_DB}.{MIGRATION_TABLE}",
            [[migration_id, migration_file.name, checksum, datetime.utcnow(), "migration_runner", 0]],
            column_names=["migration_id", "filename", "checksum", "applied_at", "applied_by", "success"],
        )
        return False


def run_migrations(env: str, host: str | None = None, dry_run: bool = False) -> int:
    """
    Executa todas as migrations pendentes.

    Returns:
        Número de migrations aplicadas.
    """
    client = get_client(env, host)
    ensure_migration_table(client)

    applied = get_applied_migrations(client)
    pending = get_pending_migrations()

    to_apply = [m for m in pending if m.stem not in applied]

    if not to_apply:
        logger.info("✅ Nenhuma migration pendente.")
        return 0

    logger.info(f"📦 {len(to_apply)} migration(s) pendente(s):")
    for m in to_apply:
        logger.info(f"  - {m.name}")

    if dry_run:
        logger.info("🔍 Modo DRY RUN — nenhuma alteração será feita.")

    success_count = 0
    for migration in to_apply:
        if apply_migration(client, migration, dry_run=dry_run):
            success_count += 1
        else:
            logger.error(f"❌ Migration falhou: {migration.name}. Interrompendo.")
            sys.exit(1)

    logger.info(f"\n🎉 {success_count} migration(s) aplicada(s) com sucesso!")
    return success_count


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ClickHouse Migration Runner")
    parser.add_argument("--env", default="local", choices=["local", "staging", "production"])
    parser.add_argument("--host", default=None, help="Override do host ClickHouse")
    parser.add_argument("--dry-run", action="store_true", help="Simula sem executar")
    args = parser.parse_args()

    run_migrations(env=args.env, host=args.host, dry_run=args.dry_run)
