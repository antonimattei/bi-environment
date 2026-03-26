-- models/staging/stg_erp__vendas.sql
-- Camada staging: normaliza dados brutos de vendas do ERP
-- Fonte: raw.vendas (ingerido pelo Airflow)
-- Sem lógica de negócio — apenas tipagem e renomeação

{{
    config(
        materialized='view',
        tags=['staging', 'erp', 'vendas'],
    )
}}

WITH source AS (
    SELECT *
    FROM {{ source('erp_raw', 'vendas') }}

),

renamed AS (
    SELECT
        -- Chaves
        CAST(venda_id AS UInt64)        AS venda_id,
        CAST(cliente_id AS UInt32)      AS cliente_id,
        CAST(produto_id AS UInt32)      AS produto_id,
        CAST(loja_id AS UInt16)         AS loja_id,

        -- Datas
        CAST(data_venda AS Date)        AS data_venda,

        -- Métricas
        CAST(quantidade AS Float32)             AS quantidade,
        CAST(valor_bruto AS Decimal(15, 2))     AS valor_bruto,
        CAST(desconto AS Decimal(15, 2))        AS desconto,
        CAST(valor_liquido AS Decimal(15, 2))   AS valor_liquido,

        -- Metadados de pipeline
        _inserted_at,
        _source,
        _batch_id

    FROM source

    -- Filtrar registros obviamente inválidos
    WHERE venda_id IS NOT NULL
      AND valor_liquido >= 0

)

SELECT * FROM renamed
