#!/bin/bash
set -e

echo "==> Running Superset DB upgrade..."
superset db upgrade

echo "==> Creating admin user (if not exists)..."
superset fab create-admin \
  --username admin \
  --firstname Admin \
  --lastname User \
  --email admin@dev.local \
  --password admin \
  || echo "Admin user already exists, skipping."

echo "==> Initializing Superset..."
superset init

echo "==> Starting Superset with Gunicorn..."
exec gunicorn \
  --bind 0.0.0.0:8088 \
  --workers 2 \
  --timeout 120 \
  --access-logfile - \
  --error-logfile - \
  "superset.app:create_app()"
