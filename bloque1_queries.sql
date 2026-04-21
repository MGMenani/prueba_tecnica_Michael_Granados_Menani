-- =============================================================
-- BLOQUE 1 — SQL Avanzado
-- Base de datos: BigQuery SQL
-- Dataset: prueba_tecnica (retail multiformato, Centroamérica)
-- Período: Enero 2024 – Junio 2025 (547 días)
--
-- Notas generales:
--   - Se excluyen: TX con total_amount = 0, Tienda 37 (pre-apertura),
--     Tiendas 8 y 37 del análisis A/B (asignadas a ambos grupos).
--   - Se usa total_amount como monto oficial de cada transacción.
--   - Las tablas se referencian como si estuvieran en el mismo dataset.
-- =============================================================


-- =============================================================
-- QUERY 1 — Ventas Comparables (Comp Sales) YoY
-- Métrica estándar de retail
--
-- Lógica:
--   - Solo tiendas abiertas hace más de 13 meses (operando en ambos períodos).
--   - Comparación: H1 2025 (ene–jun 2025) vs H1 2024 (ene–jun 2024).
--   - Resultado: GMV por año, Comp Sales Growth %, ranking por formato.
-- =============================================================

WITH store_tenure AS (
  -- Filtra tiendas con al menos 13 meses de operación antes del período actual
  SELECT
    store_id,
    opening_date
  FROM 'stores'
  WHERE opening_date <= DATE_SUB('2025-01-01', INTERVAL 13 MONTH)
    AND store_id NOT IN ('TIENDA_037')  -- excluida en integridad temporal
),

sales_by_period AS (
  -- Agrega GMV por tienda y año (mismo rango de meses para comparar)
  SELECT
    t.store_id,
    EXTRACT(YEAR FROM t.transaction_date) AS year,
    SUM(t.total_amount)                   AS gmv
  FROM `transactions` t
  INNER JOIN store_tenure st ON t.store_id = st.store_id
  WHERE t.total_amount > 0
    AND t.status = 'COMPLETED'
    -- Mismo bloque de meses: enero a junio en ambos años
    AND EXTRACT(MONTH FROM t.transaction_date) BETWEEN 1 AND 6
    AND EXTRACT(YEAR  FROM t.transaction_date) IN (2024, 2025)
  GROUP BY t.store_id, year
),

pivot AS (
  -- Pivotea los años en columnas
  SELECT
    store_id,
    SUM(CASE WHEN year = 2024 THEN gmv ELSE 0 END) AS gmv_2024,
    SUM(CASE WHEN year = 2025 THEN gmv ELSE 0 END) AS gmv_2025
  FROM sales_by_period
  GROUP BY store_id
),

comp_sales AS (
  SELECT
    p.store_id,
    s.country,
    s.format,
    s.store_name,
    ROUND(p.gmv_2024, 2)                                        AS gmv_anio_anterior,
    ROUND(p.gmv_2025, 2)                                        AS gmv_anio_actual,
    ROUND(SAFE_DIVIDE(p.gmv_2025 - p.gmv_2024, p.gmv_2024) * 100, 2) AS comp_sales_growth_pct
  FROM pivot p
  INNER JOIN `stores` s ON p.store_id = s.store_id
)

SELECT
  *,
  RANK() OVER (
    PARTITION BY format
    ORDER BY comp_sales_growth_pct DESC
  ) AS ranking_en_formato
FROM comp_sales
ORDER BY format, ranking_en_formato;


-- =============================================================
-- QUERY 2 — Productividad por Metro Cuadrado
-- KPI operativo — último trimestre disponible (Q2 2025: abr–jun 2025)
--
-- Lógica:
--   - GMV total del trimestre por tienda.
--   - GMV/m², transacciones/m², ticket promedio.
--   - Ranking dentro del formato.
--   - Tiendas bajo el percentil 25 de GMV/m² → BAJO_RENDIMIENTO.
-- =============================================================

WITH last_quarter AS (
  SELECT
    t.store_id,
    COUNT(DISTINCT t.transaction_id) AS num_transacciones,
    SUM(t.total_amount)              AS gmv_trimestre
  FROM `transactions` t
  WHERE t.transaction_date BETWEEN '2025-04-01' AND '2025-06-30'
    AND t.total_amount > 0
    AND t.status = 'COMPLETED'
    AND t.store_id NOT IN ('TIENDA_037')
  GROUP BY t.store_id
),

store_kpis AS (
  SELECT
    lq.store_id,
    s.store_name,
    s.country,
    s.format,
    s.size_sqm,
    ROUND(lq.gmv_trimestre, 2)                                   AS gmv_trimestre,
    ROUND(SAFE_DIVIDE(lq.gmv_trimestre, s.size_sqm), 2)          AS gmv_por_m2,
    ROUND(SAFE_DIVIDE(lq.num_transacciones, s.size_sqm), 4)      AS transacciones_por_m2,
    ROUND(SAFE_DIVIDE(lq.gmv_trimestre, lq.num_transacciones), 2) AS ticket_promedio,
    lq.num_transacciones
  FROM last_quarter lq
  INNER JOIN `stores` s ON lq.store_id = s.store_id
),

with_percentile AS (
  SELECT
    *,
    RANK() OVER (PARTITION BY format ORDER BY gmv_por_m2 DESC) AS ranking_en_formato,
    PERCENTILE_CONT(gmv_por_m2, 0.25) OVER (PARTITION BY format) AS p25_gmv_m2
  FROM store_kpis
)

SELECT
  store_id,
  store_name,
  country,
  format,
  size_sqm,
  gmv_trimestre,
  gmv_por_m2,
  transacciones_por_m2,
  ticket_promedio,
  num_transacciones,
  ranking_en_formato,
  CASE
    WHEN gmv_por_m2 < p25_gmv_m2 THEN 'BAJO_RENDIMIENTO'
    ELSE 'NORMAL'
  END AS estado_rendimiento
FROM with_percentile
ORDER BY format, ranking_en_formato;


-- =============================================================
-- QUERY 3 — Cohortes de Clientes con Tarjeta de Lealtad
-- Retención mensual + evolución de ticket promedio
--
-- Lógica:
--   - Solo clientes con loyalty_card = TRUE (customer_id identificado).
--   - Cohorte = mes de la primera transacción del cliente.
--   - Retención: % que regresó en los meses 1, 2, 3 y 6 post-primera compra.
--   - Ticket promedio por cohorte en cada período.
-- =============================================================

WITH first_purchase AS (
  -- Primer mes de compra por cliente
  SELECT
    customer_id,
    DATE_TRUNC(MIN(transaction_date), MONTH) AS cohort_month
  FROM `transactions`
  WHERE loyalty_card = TRUE
    AND customer_id IS NOT NULL
    AND total_amount > 0
    AND status = 'COMPLETED'
  GROUP BY customer_id
),

monthly_activity AS (
  -- Actividad mensual de cada cliente
  SELECT
    t.customer_id,
    DATE_TRUNC(t.transaction_date, MONTH) AS activity_month,
    SUM(t.total_amount)                   AS monthly_spend,
    COUNT(t.transaction_id)               AS num_transactions
  FROM `transactions` t
  WHERE t.loyalty_card = TRUE
    AND t.customer_id IS NOT NULL
    AND t.total_amount > 0
    AND t.status = 'COMPLETED'
  GROUP BY t.customer_id, activity_month
),

cohort_activity AS (
  -- Cruza actividad mensual con la cohorte del cliente
  SELECT
    fp.cohort_month,
    ma.customer_id,
    ma.activity_month,
    ma.monthly_spend,
    DATE_DIFF(ma.activity_month, fp.cohort_month, MONTH) AS months_since_first
  FROM first_purchase fp
  INNER JOIN monthly_activity ma ON fp.customer_id = ma.customer_id
),

cohort_sizes AS (
  SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
  FROM first_purchase
  GROUP BY cohort_month
),

retention_pivot AS (
  SELECT
    ca.cohort_month,
    cs.cohort_size,
    -- Retención: % de clientes que volvieron en cada período
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_first = 0 THEN ca.customer_id END) / cs.cohort_size, 1) AS mes_0_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_first = 1 THEN ca.customer_id END) / cs.cohort_size, 1) AS mes_1_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_first = 2 THEN ca.customer_id END) / cs.cohort_size, 1) AS mes_2_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_first = 3 THEN ca.customer_id END) / cs.cohort_size, 1) AS mes_3_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_first = 6 THEN ca.customer_id END) / cs.cohort_size, 1) AS mes_6_pct,
    -- Ticket promedio por período
    ROUND(AVG(CASE WHEN months_since_first = 0 THEN monthly_spend END), 2) AS ticket_mes_0,
    ROUND(AVG(CASE WHEN months_since_first = 1 THEN monthly_spend END), 2) AS ticket_mes_1,
    ROUND(AVG(CASE WHEN months_since_first = 2 THEN monthly_spend END), 2) AS ticket_mes_2,
    ROUND(AVG(CASE WHEN months_since_first = 3 THEN monthly_spend END), 2) AS ticket_mes_3,
    ROUND(AVG(CASE WHEN months_since_first = 6 THEN monthly_spend END), 2) AS ticket_mes_6
  FROM cohort_activity ca
  INNER JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
  GROUP BY ca.cohort_month, cs.cohort_size
)

SELECT *
FROM retention_pivot
ORDER BY cohort_month;


-- =============================================================
-- QUERY 4 — GMROI por Proveedor y Categoría
-- Gross Margin Return on Investment
--
-- GMROI = Margen Bruto / Costo Total
-- Lógica:
--   - GMV = sum(unit_price * quantity) desde transaction_items.
--   - Costo total = sum(cost * quantity) desde products.
--   - Margen bruto = GMV - Costo total.
--   - SKUs activos = productos con al menos 1 venta en el período.
--   - Velocidad = unidades vendidas / días del período (547).
-- =============================================================

WITH item_sales AS (
  SELECT
    ti.item_id,
    SUM(ti.quantity)                    AS total_units,
    SUM(ti.unit_price * ti.quantity)    AS gmv,
    SUM(p.cost * ti.quantity)           AS costo_total
  FROM `transaction_items` ti
  INNER JOIN `products` p ON ti.item_id = p.item_id
  INNER JOIN `transactions` t ON ti.transaction_id = t.transaction_id
  WHERE t.total_amount > 0
    AND t.status = 'COMPLETED'
    AND t.store_id NOT IN ('TIENDA_037')
  GROUP BY ti.item_id
),

vendor_category_agg AS (
  SELECT
    COALESCE(v.vendor_name, 'Vendor Desconocido') AS vendor_name,
    p.vendor_id,
    p.category,
    COUNT(DISTINCT p.item_id)             AS skus_activos,
    SUM(s.total_units)                    AS total_units,
    ROUND(SUM(s.gmv), 2)                  AS gmv_total,
    ROUND(SUM(s.costo_total), 2)          AS costo_total,
    ROUND(SUM(s.gmv) - SUM(s.costo_total), 2)   AS margen_bruto,
    ROUND(SAFE_DIVIDE(SUM(s.gmv) - SUM(s.costo_total), SUM(s.costo_total)), 4) AS gmroi,
    ROUND(SAFE_DIVIDE(SUM(s.total_units), 547), 2) AS velocidad_uds_dia
  FROM item_sales s
  INNER JOIN `products` p ON s.item_id = p.item_id
  LEFT JOIN  `vendors` v  ON p.vendor_id = v.vendor_id
  GROUP BY v.vendor_name, p.vendor_id, p.category
)

SELECT
  *,
  CASE WHEN gmroi < 1 THEN 'GMROI_BAJO' ELSE 'OK' END AS alerta_gmroi
FROM vendor_category_agg
ORDER BY gmroi ASC;


-- =============================================================
-- QUERY 5 — Detección de Posibles Quiebres de Stock
-- Un gap = 3+ días consecutivos sin venta de un ítem en una
-- tienda donde históricamente sí se vendía.
--
-- Lógica:
--   1. Genera el calendario de ventas por tienda-ítem.
--   2. Identifica gaps usando LAG para encontrar la venta anterior.
--   3. Filtra gaps >= 3 días.
--   4. Calcula ventas promedio diarias previas al gap.
--   5. Estima GMV perdido = avg_daily_gmv * duración_gap.
-- =============================================================

WITH daily_sales AS (
  -- Ventas diarias por tienda e ítem
  SELECT
    t.store_id,
    ti.item_id,
    t.transaction_date                    AS sale_date,
    SUM(ti.quantity)                      AS units_sold,
    SUM(ti.unit_price * ti.quantity)      AS gmv_day
  FROM `transaction_items` ti
  INNER JOIN `transactions` t ON ti.transaction_id = t.transaction_id
  WHERE t.total_amount > 0
    AND t.status = 'COMPLETED'
    AND t.store_id NOT IN ('TIENDA_037')
  GROUP BY t.store_id, ti.item_id, t.transaction_date
),

with_prev_sale AS (
  -- Fecha de la venta anterior para calcular el gap
  SELECT
    *,
    LAG(sale_date) OVER (
      PARTITION BY store_id, item_id
      ORDER BY sale_date
    ) AS prev_sale_date
  FROM daily_sales
),

gaps AS (
  -- Identifica gaps de 3+ días consecutivos sin venta
  SELECT
    store_id,
    item_id,
    prev_sale_date         AS gap_start,
    sale_date              AS gap_end,
    DATE_DIFF(sale_date, prev_sale_date, DAY) - 1 AS gap_days
  FROM with_prev_sale
  WHERE DATE_DIFF(sale_date, prev_sale_date, DAY) - 1 >= 3
),

pre_gap_avg AS (
  -- Promedio diario de ventas antes del gap (últimos 30 días previos)
  SELECT
    g.store_id,
    g.item_id,
    g.gap_start,
    g.gap_end,
    g.gap_days,
    ROUND(AVG(ds.units_sold), 2)  AS avg_daily_units,
    ROUND(AVG(ds.gmv_day), 2)     AS avg_daily_gmv
  FROM gaps g
  INNER JOIN daily_sales ds
    ON  g.store_id = ds.store_id
    AND g.item_id  = ds.item_id
    AND ds.sale_date BETWEEN DATE_SUB(g.gap_start, INTERVAL 30 DAY) AND g.gap_start
  GROUP BY g.store_id, g.item_id, g.gap_start, g.gap_end, g.gap_days
)

SELECT
  pga.store_id,
  pga.item_id,
  p.item_name,
  p.category,
  pga.gap_start,
  pga.gap_end,
  pga.gap_days,
  pga.avg_daily_units,
  pga.avg_daily_gmv,
  ROUND(pga.avg_daily_gmv * pga.gap_days, 2) AS gmv_estimado_perdido
FROM pre_gap_avg pga
INNER JOIN `products` p ON pga.item_id = p.item_id
ORDER BY gmv_estimado_perdido DESC;


-- =============================================================
-- QUERY 6 — Impacto de Promociones en Ticket y Volumen
-- Basket Analysis
--
-- Lógica:
--   - Clasifica cada transacción: con ítems en promo vs. sin ítems en promo.
--   - Por categoría, compara ticket promedio y unidades promedio.
--   - El "basket uplift" se mide como la diferencia entre ambos grupos.
-- =============================================================

WITH tx_promo_flag AS (
  -- Identifica si cada transacción tiene al menos 1 ítem en promo
  SELECT
    transaction_id,
    MAX(CASE WHEN was_on_promo = TRUE THEN 1 ELSE 0 END) AS tiene_promo
  FROM `transaction_items`
  GROUP BY transaction_id
),

item_detail AS (
  -- Une ítems con categoría y flag de promo a nivel transacción
  SELECT
    ti.transaction_id,
    ti.item_id,
    p.category,
    ti.quantity,
    ti.unit_price,
    ti.unit_price * ti.quantity AS line_total,
    tf.tiene_promo
  FROM `transaction_items` ti
  INNER JOIN `products` p       ON ti.item_id = p.item_id
  INNER JOIN tx_promo_flag tf   ON ti.transaction_id = tf.transaction_id
  INNER JOIN `transactions` t   ON ti.transaction_id = t.transaction_id
  WHERE t.total_amount > 0
    AND t.status = 'COMPLETED'
    AND t.store_id NOT IN ('TIENDA_037')
),

category_metrics AS (
  SELECT
    category,
    tiene_promo,
    COUNT(DISTINCT transaction_id)                         AS num_transacciones,
    ROUND(SUM(line_total) / COUNT(DISTINCT transaction_id), 2)  AS ticket_promedio,
    ROUND(SUM(quantity)   / COUNT(DISTINCT transaction_id), 2)  AS unidades_promedio
  FROM item_detail
  GROUP BY category, tiene_promo
)

SELECT
  con_promo.category,
  con_promo.num_transacciones                               AS tx_con_promo,
  sin_promo.num_transacciones                               AS tx_sin_promo,
  con_promo.ticket_promedio                                 AS ticket_con_promo,
  sin_promo.ticket_promedio                                 AS ticket_sin_promo,
  ROUND(con_promo.ticket_promedio - sin_promo.ticket_promedio, 2)  AS uplift_ticket_abs,
  ROUND(SAFE_DIVIDE(con_promo.ticket_promedio - sin_promo.ticket_promedio,
        sin_promo.ticket_promedio) * 100, 1)                AS uplift_ticket_pct,
  con_promo.unidades_promedio                               AS uds_con_promo,
  sin_promo.unidades_promedio                               AS uds_sin_promo,
  ROUND(con_promo.unidades_promedio - sin_promo.unidades_promedio, 2) AS uplift_uds
FROM
  (SELECT * FROM category_metrics WHERE tiene_promo = 1) AS con_promo
FULL OUTER JOIN
  (SELECT * FROM category_metrics WHERE tiene_promo = 0) AS sin_promo
  USING (category)
ORDER BY uplift_ticket_pct DESC;
