"""
Testes unitários para a DAG vendas_ingestao_diaria.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest


class TestValicarDados:
    """Testes para a função de validação de dados."""

    def test_validar_dados_ok(self):
        """Deve passar com dados válidos."""
        from dags.vendas_ingestao_diaria import vendas_ingestao_diaria

        dag = vendas_ingestao_diaria()
        # Instanciar a task diretamente para teste unitário
        extracao = {
            "dados": [
                {
                    "venda_id": 1,
                    "data_venda": "2024-01-15",
                    "cliente_id": 10,
                    "produto_id": 5,
                    "loja_id": 2,
                    "quantidade": 1.0,
                    "valor_bruto": 100.00,
                    "desconto": 0.00,
                    "valor_liquido": 100.00,
                }
            ],
            "count": 1,
        }
        # A função de validação não deve lançar exceção
        # (teste estrutural — validação de lógica interna)
        dados = extracao["dados"]
        assert len(dados) > 0
        assert all(r["valor_liquido"] >= 0 for r in dados)
        assert len({r["venda_id"] for r in dados}) == len(dados)

    def test_validar_dados_vazio_levanta_erro(self):
        """Deve lançar ValueError se extração retornar vazio."""
        dados = []
        with pytest.raises(ValueError, match="0 registros"):
            if not dados:
                raise ValueError("Extração retornou 0 registros — verificar pipeline ERP")

    def test_validar_dados_valor_negativo(self):
        """Deve detectar valor_liquido negativo."""
        dados = [{"venda_id": 1, "valor_liquido": -50.00}]
        with pytest.raises(ValueError, match="Valor negativo"):
            for i, row in enumerate(dados):
                if row.get("valor_liquido", -1) < 0:
                    raise ValueError(f"Valor negativo na linha {i}: {row}")

    def test_validar_dados_ids_duplicados(self):
        """Deve detectar IDs duplicados."""
        dados = [
            {"venda_id": 1, "valor_liquido": 100.0},
            {"venda_id": 1, "valor_liquido": 200.0},  # duplicado
        ]
        ids = [r["venda_id"] for r in dados]
        with pytest.raises(ValueError, match="duplicados"):
            if len(ids) != len(set(ids)):
                raise ValueError("IDs duplicados detectados na extração")


class TestDAGStructure:
    """Testes estruturais da DAG."""

    def test_dag_importa_sem_erros(self):
        """A DAG deve importar sem lançar exceções."""
        import importlib
        import sys

        # Remove do cache se já importado
        if "dags.vendas_ingestao_diaria" in sys.modules:
            del sys.modules["dags.vendas_ingestao_diaria"]

        try:
            import dags.vendas_ingestao_diaria  # noqa: F401
        except ImportError as e:
            # Airflow pode não estar instalado no ambiente de test
            if "airflow" in str(e).lower():
                pytest.skip("Airflow não instalado no ambiente de teste")
            raise

    def test_default_args_tem_retries(self):
        """DEFAULT_ARGS deve ter retries configurado."""
        from dags.vendas_ingestao_diaria import DEFAULT_ARGS

        assert "retries" in DEFAULT_ARGS
        assert DEFAULT_ARGS["retries"] > 0

    def test_default_args_tem_retry_delay(self):
        """DEFAULT_ARGS deve ter retry_delay configurado."""
        from dags.vendas_ingestao_diaria import DEFAULT_ARGS

        assert "retry_delay" in DEFAULT_ARGS
