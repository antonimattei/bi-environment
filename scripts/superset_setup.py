"""Script para criar dataset, charts e dashboard no Superset."""

import json

from superset import create_app

app = create_app()
with app.app_context():
    from superset.connectors.sqla.models import SqlaTable
    from superset.extensions import db
    from superset.models.core import Database
    from superset.models.dashboard import Dashboard
    from superset.models.slice import Slice

    database = db.session.query(Database).filter_by(id=1).first()
    if not database:
        print("ERRO: Database ID=1 nao encontrado.")
        exit(1)

    # ── Dataset ──────────────────────────────────────────────────────
    dataset = (
        db.session.query(SqlaTable).filter_by(table_name="fact_vendas", schema="analytics").first()
    )
    if not dataset:
        dataset = SqlaTable(
            table_name="fact_vendas",
            schema="analytics",
            database_id=database.id,
            main_dttm_col="data_venda",
            filter_select_enabled=True,
        )
        db.session.add(dataset)
        db.session.commit()
        print(f"Dataset criado, ID: {dataset.id}")
    else:
        print(f"Dataset existente, ID: {dataset.id}")

    DS = f"{dataset.id}__table"

    def metric(col, agg, label):
        return {
            "expressionType": "SIMPLE",
            "column": {"column_name": col},
            "aggregate": agg,
            "label": label,
        }

    # ── Charts ───────────────────────────────────────────────────────
    charts_def = [
        {
            "slice_name": "Receita Total",
            "viz_type": "big_number_total",
            "params": {
                "datasource": DS,
                "viz_type": "big_number_total",
                "metric": metric("valor_liquido", "SUM", "Receita Total"),
                "subheader": "Receita Liquida Acumulada",
                "y_axis_format": "SMART_NUMBER",
            },
        },
        {
            "slice_name": "Total de Pedidos",
            "viz_type": "big_number_total",
            "params": {
                "datasource": DS,
                "viz_type": "big_number_total",
                "metric": metric("venda_id", "COUNT", "Pedidos"),
                "subheader": "Total de Transacoes",
                "y_axis_format": "SMART_NUMBER",
            },
        },
        {
            "slice_name": "Vendas por Loja",
            "viz_type": "pie",
            "params": {
                "datasource": DS,
                "viz_type": "pie",
                "groupby": ["loja_id"],
                "metric": metric("valor_liquido", "SUM", "Receita"),
                "row_limit": 10,
                "color_scheme": "supersetColors",
                "show_legend": True,
                "show_labels": True,
                "label_type": "key_percent",
                "donut": True,
            },
        },
        {
            "slice_name": "Receita Liquida por Mes",
            "viz_type": "echarts_timeseries_bar",
            "params": {
                "datasource": DS,
                "viz_type": "echarts_timeseries_bar",
                "x_axis": "data_venda",
                "time_grain_sqla": "P1M",
                "metrics": [metric("valor_liquido", "SUM", "Receita Liquida")],
                "groupby": [],
                "row_limit": 100,
                "color_scheme": "supersetColors",
                "show_legend": True,
                "rich_tooltip": True,
            },
        },
        {
            "slice_name": "Receita por Produto",
            "viz_type": "echarts_timeseries_bar",
            "params": {
                "datasource": DS,
                "viz_type": "echarts_timeseries_bar",
                "x_axis": "data_venda",
                "time_grain_sqla": "P1M",
                "metrics": [metric("valor_liquido", "SUM", "Receita")],
                "groupby": ["produto_id"],
                "row_limit": 10,
                "color_scheme": "supersetColors",
                "show_legend": True,
            },
        },
    ]

    slices = []
    for cd in charts_def:
        existing = db.session.query(Slice).filter_by(slice_name=cd["slice_name"]).first()
        if existing:
            db.session.delete(existing)
            db.session.commit()
        s = Slice(
            slice_name=cd["slice_name"],
            viz_type=cd["viz_type"],
            datasource_type="table",
            datasource_id=dataset.id,
            params=json.dumps(cd["params"]),
        )
        db.session.add(s)
        db.session.flush()
        slices.append(s)
        print(f"  Chart criado: '{s.slice_name}' (ID: {s.id})")

    db.session.commit()

    # ── Dashboard ─────────────────────────────────────────────────────
    c_receita, c_pedidos, c_loja, c_mes, c_produto = slices

    position = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID": {"type": "ROOT", "id": "ROOT_ID", "children": ["GRID_ID"]},
        "GRID_ID": {
            "type": "GRID",
            "id": "GRID_ID",
            "children": ["ROW_KPI", "ROW_CHARTS"],
            "parents": ["ROOT_ID"],
        },
        "ROW_KPI": {
            "type": "ROW",
            "id": "ROW_KPI",
            "children": ["COL_RECEITA", "COL_PEDIDOS", "COL_LOJA"],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "ROW_CHARTS": {
            "type": "ROW",
            "id": "ROW_CHARTS",
            "children": ["COL_MES", "COL_PRODUTO"],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        },
        "COL_RECEITA": {
            "type": "CHART",
            "id": "COL_RECEITA",
            "children": [],
            "parents": ["ROOT_ID", "GRID_ID", "ROW_KPI"],
            "meta": {"chartId": c_receita.id, "width": 8, "height": 10},
        },
        "COL_PEDIDOS": {
            "type": "CHART",
            "id": "COL_PEDIDOS",
            "children": [],
            "parents": ["ROOT_ID", "GRID_ID", "ROW_KPI"],
            "meta": {"chartId": c_pedidos.id, "width": 8, "height": 10},
        },
        "COL_LOJA": {
            "type": "CHART",
            "id": "COL_LOJA",
            "children": [],
            "parents": ["ROOT_ID", "GRID_ID", "ROW_KPI"],
            "meta": {"chartId": c_loja.id, "width": 8, "height": 10},
        },
        "COL_MES": {
            "type": "CHART",
            "id": "COL_MES",
            "children": [],
            "parents": ["ROOT_ID", "GRID_ID", "ROW_CHARTS"],
            "meta": {"chartId": c_mes.id, "width": 12, "height": 14},
        },
        "COL_PRODUTO": {
            "type": "CHART",
            "id": "COL_PRODUTO",
            "children": [],
            "parents": ["ROOT_ID", "GRID_ID", "ROW_CHARTS"],
            "meta": {"chartId": c_produto.id, "width": 12, "height": 14},
        },
    }

    existing_dash = db.session.query(Dashboard).filter_by(slug="vendas").first()
    if existing_dash:
        db.session.delete(existing_dash)
        db.session.commit()

    dash = Dashboard(
        dashboard_title="BI Platform - Vendas",
        slug="vendas",
        position_json=json.dumps(position),
        published=True,
    )
    dash.slices = slices
    db.session.add(dash)
    db.session.commit()

    print(f"\nDashboard criado: '{dash.dashboard_title}' (ID: {dash.id})")
    print("Acesse: http://localhost:8088/superset/dashboard/vendas/")
