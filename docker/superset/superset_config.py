"""
superset_config.py — Configuração do Apache Superset para o BI Platform.
Montado em: /app/pythonpath/superset_config.py
"""

import os

# ─── Segurança ────────────────────────────────────────────────────────
SECRET_KEY = os.environ["SUPERSET_SECRET_KEY"]

# HTTPS em produção
ENABLE_PROXY_FIX = True
SESSION_COOKIE_SECURE = os.getenv("ENV", "local") == "production"
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"

# ─── Banco de Dados (Metastore) ───────────────────────────────────────
SQLALCHEMY_DATABASE_URI = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg2://airflow:airflow@postgres/superset",
)

# ─── Cache (Redis) ────────────────────────────────────────────────────
CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 300,  # 5 minutos padrão
    "CACHE_KEY_PREFIX": "superset_",
    "CACHE_REDIS_URL": os.getenv("REDIS_URL", "redis://redis:6379/0"),
}

# Cache separado para dados (queries dos dashboards)
DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 600,  # 10 minutos para dados
    "CACHE_KEY_PREFIX": "superset_data_",
    "CACHE_REDIS_URL": os.getenv("REDIS_URL", "redis://redis:6379/1"),
}

# ─── Performance ──────────────────────────────────────────────────────
# Limite de linhas retornadas em queries exploratórias
ROW_LIMIT = 50_000
VIZ_ROW_LIMIT = 10_000

# Timeout de queries SQL (segundos)
SQLLAB_TIMEOUT = 300
SUPERSET_WEBSERVER_TIMEOUT = 300

# ─── Features ─────────────────────────────────────────────────────────
FEATURE_FLAGS = {
    "ENABLE_TEMPLATE_PROCESSING": True,  # Jinja2 em SQL ({{ from_dttm }})
    "DASHBOARD_NATIVE_FILTERS": True,  # Filtros nativos modernos
    "DASHBOARD_CROSS_FILTERS": True,  # Cross-filtering entre charts
    "ALERT_REPORTS": True,  # Alertas e relatórios agendados
    "DRILL_BY": True,  # Drill-down por dimensão
    "EMBEDDABLE_CHARTS": True,  # Embed de charts via iFrame
    "HORIZONTAL_FILTER_BAR": True,  # Filtros horizontais
    "SSH_TUNNELING": False,  # Desabilitado por segurança
}

# ─── Alertas e Reports ────────────────────────────────────────────────
ALERT_REPORTS_NOTIFICATION_DRY_RUN = os.getenv("ENV", "local") != "production"

SMTP_HOST = os.getenv("SMTP_HOST", "localhost")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_STARTTLS = True
SMTP_SSL = False
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
SMTP_MAIL_FROM = os.getenv("SMTP_USER", "superset@empresa.com")

# ─── Segurança de dados ───────────────────────────────────────────────
# Permitir apenas DBs listados (em produção, desabilitar SQLite)
PREVENT_UNSAFE_DB_CONNECTIONS = True

# ─── Aparência ────────────────────────────────────────────────────────
APP_NAME = "BI Platform"
APP_ICON = "/static/assets/images/logo.png"

# Tema padrão: limpo e profissional
THEME_OVERRIDES = {
    "borderRadius": 4,
    "colors": {
        "primary": {
            "base": "#1890FF",
            "dark1": "#0067CC",
            "dark2": "#004999",
            "light1": "#69BAFF",
            "light2": "#A3D4FF",
            "light3": "#D3EAFF",
            "light4": "#E8F4FF",
            "light5": "#F0F8FF",
        },
    },
}
