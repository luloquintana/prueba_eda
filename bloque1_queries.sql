-- ============================================================================
-- BLOQUE 1 · SQL AVANZADO
-- Se asume solo transacciones con status = 'COMPLETED' representan venta neta real.
-- ============================================================================

-- ============================================================================
-- QUERY 1 - COMP SALES 
-- ============================================================================
-- Ventas comparables — crecimiento YoY

DECLARE analysis_end DATE DEFAULT (
  SELECT MAX(transaction_date) FROM `test-eda-507323.producto.transactions`
);
DECLARE current_start DATE DEFAULT DATE_SUB(analysis_end, INTERVAL 12 MONTH);
DECLARE prior_start   DATE DEFAULT DATE_SUB(current_start, INTERVAL 12 MONTH);
DECLARE prior_end     DATE DEFAULT DATE_SUB(current_start, INTERVAL 1 DAY);

WITH comp_stores AS (
  -- Tiendas "comparables": operando 13+ meses antes del período actual
  SELECT store_id, country, format
  FROM `test-eda-507323.producto.stores`
  WHERE opening_date <= DATE_SUB(current_start, INTERVAL 13 MONTH)
),
gmv_actual AS (
  SELECT store_id, SUM(total_amount) AS gmv_actual
  FROM `test-eda-507323.producto.transactions`
  WHERE status = 'COMPLETED'
    AND transaction_date BETWEEN current_start AND analysis_end
  GROUP BY store_id
),
gmv_anterior AS (
  SELECT store_id, SUM(total_amount) AS gmv_anterior
  FROM `test-eda-507323.producto.transactions`
  WHERE status = 'COMPLETED'
    AND transaction_date BETWEEN prior_start AND prior_end
  GROUP BY store_id
),
comp_sales AS (
  SELECT
    cs.country,
    cs.format,
    cs.store_id,
    IFNULL(ga.gmv_actual, 0)   AS gmv_actual,
    IFNULL(gp.gmv_anterior, 0) AS gmv_anterior,
    ROUND(
      SAFE_DIVIDE(IFNULL(ga.gmv_actual, 0) - IFNULL(gp.gmv_anterior, 0), gp.gmv_anterior) * 100,
      2
    ) AS comp_sales_growth_pct
  FROM comp_stores cs
  LEFT JOIN gmv_actual   ga USING (store_id)
  LEFT JOIN gmv_anterior gp USING (store_id)
)
SELECT
  *,
  RANK() OVER (PARTITION BY format ORDER BY comp_sales_growth_pct DESC) AS ranking_en_formato
FROM comp_sales
ORDER BY format, ranking_en_formato;

-- ============================================================================
-- QUERY 2 - PRODUCTIVIDAD POR METRO CUADRADO
-- ============================================================================
-- Último trimestre disponible
DECLARE q_end DATE DEFAULT (
  SELECT MAX(transaction_date) FROM `test-eda-507323.producto.transactions`
  );
DECLARE q_start DATE DEFAULT DATE_SUB(q_end, INTERVAL 3 MONTH);

WITH ventas_trimestre AS (
  SELECT
    store_id,
    SUM(total_amount) AS gmv_trimestre,
    COUNT(DISTINCT transaction_id) AS num_transacciones
  FROM `test-eda-507323.producto.transactions`
  WHERE status = 'COMPLETED'
    AND transaction_date BETWEEN q_start AND q_end
  GROUP BY store_id
),
metrica AS (
  SELECT
    s.store_id,
    s.store_name,
    s.format,
    s.size_sqm,
    IFNULL(v.gmv_trimestre, 0)      AS gmv_trimestre,
    IFNULL(v.num_transacciones, 0)  AS num_transacciones,
    ROUND(SAFE_DIVIDE(IFNULL(v.gmv_trimestre, 0), s.size_sqm), 2)       AS gmv_por_m2,
    ROUND(SAFE_DIVIDE(IFNULL(v.num_transacciones, 0), s.size_sqm), 4)  AS transacciones_por_m2,
    ROUND(SAFE_DIVIDE(IFNULL(v.gmv_trimestre, 0), NULLIF(v.num_transacciones, 0)), 2) AS ticket_promedio
  FROM `test-eda-507323.producto.stores` s
  LEFT JOIN ventas_trimestre v USING (store_id)
),
con_percentil AS (
  SELECT
    *,
    RANK() OVER (PARTITION BY format ORDER BY gmv_por_m2 DESC) AS ranking_en_formato,
    PERCENTILE_CONT(gmv_por_m2, 0.25) OVER (PARTITION BY format) AS p25_gmv_por_m2
  FROM metrica
)
SELECT
  * EXCEPT(p25_gmv_por_m2),
  CASE WHEN gmv_por_m2 < p25_gmv_por_m2 THEN 'BAJO_RENDIMIENTO' ELSE 'OK' END AS flag_rendimiento
FROM con_percentil
ORDER BY format, ranking_en_formato;

-- ============================================================================
-- QUERY 3 · COHORTES DE CLIENTES CON TARJETA DE LEALTAD
-- ============================================================================
WITH primera_compra AS (
  -- Cohorte = mes de la primera transacción como cliente identificado con loyalty_card
  SELECT
    customer_id,
    DATE_TRUNC(MIN(transaction_date), MONTH) AS mes_cohorte
  FROM `test-eda-507323.producto.transactions`
  WHERE loyalty_card = TRUE
    AND customer_id IS NOT NULL
    AND status = 'COMPLETED'
  GROUP BY customer_id
),
compras_con_offset AS (
  SELECT
    t.customer_id,
    p.mes_cohorte,
    DATE_DIFF(DATE_TRUNC(t.transaction_date, MONTH), p.mes_cohorte, MONTH) AS month_offset,
    t.total_amount
  FROM `test-eda-507323.producto.transactions` t
  JOIN primera_compra p USING (customer_id)
  WHERE t.loyalty_card = TRUE AND t.status = 'COMPLETED'
),
tamano_cohorte AS (
  SELECT mes_cohorte, COUNT(DISTINCT customer_id) AS clientes_cohorte
  FROM primera_compra
  GROUP BY mes_cohorte
),
retencion AS (
  SELECT
    mes_cohorte,
    month_offset,
    COUNT(DISTINCT customer_id) AS clientes_activos,
    ROUND(AVG(total_amount), 2) AS ticket_promedio_periodo
  FROM compras_con_offset
  WHERE month_offset IN (0, 1, 2, 3, 6)
  GROUP BY mes_cohorte, month_offset
)
-- Tabla pivoteada: cohortes en filas, meses en columnas
SELECT
  r.mes_cohorte,
  tc.clientes_cohorte,
  ROUND(MAX(IF(month_offset = 1, clientes_activos, NULL)) / tc.clientes_cohorte * 100, 1) AS retencion_mes_1_pct,
  ROUND(MAX(IF(month_offset = 2, clientes_activos, NULL)) / tc.clientes_cohorte * 100, 1) AS retencion_mes_2_pct,
  ROUND(MAX(IF(month_offset = 3, clientes_activos, NULL)) / tc.clientes_cohorte * 100, 1) AS retencion_mes_3_pct,
  ROUND(MAX(IF(month_offset = 6, clientes_activos, NULL)) / tc.clientes_cohorte * 100, 1) AS retencion_mes_6_pct,
  MAX(IF(month_offset = 0, ticket_promedio_periodo, NULL)) AS ticket_mes_0,
  MAX(IF(month_offset = 1, ticket_promedio_periodo, NULL)) AS ticket_mes_1,
  MAX(IF(month_offset = 3, ticket_promedio_periodo, NULL)) AS ticket_mes_3,
  MAX(IF(month_offset = 6, ticket_promedio_periodo, NULL)) AS ticket_mes_6
FROM retencion r
JOIN tamano_cohorte tc USING (mes_cohorte)
GROUP BY r.mes_cohorte, tc.clientes_cohorte
ORDER BY r.mes_cohorte;

-- comparar ticket_mes_0 vs ticket_mes_3/6 para responder si el ticket promedio de los clientes retenidos crece o decrece.

-- ============================================================================
-- QUERY 4 · GMROI POR PROVEEDOR Y CATEGORÍA
-- ============================================================================
DECLARE periodo_dias INT64 DEFAULT (
  SELECT DATE_DIFF(MAX(transaction_date), MIN(transaction_date), DAY) + 1
  FROM `test-eda-507323.producto.transactions`
);

WITH ventas AS (
  SELECT
    p.vendor_id,
    p.category,
    p.item_id,
    SUM(ti.quantity)              AS unidades_vendidas,
    SUM(ti.unit_price * ti.quantity) AS gmv,
    SUM(p.cost * ti.quantity)     AS costo_total
  FROM `test-eda-507323.producto.transaction_items` ti
  JOIN `test-eda-507323.producto.producto` p USING (item_id)
  JOIN `test-eda-507323.producto.transactions` t USING (transaction_id)
  WHERE t.status = 'COMPLETED'
  GROUP BY p.vendor_id, p.category, p.item_id
),
agregado AS (
  SELECT
    v.vendor_id,
    ven.vendor_name,
    v.category,
    SUM(v.gmv)                          AS gmv_total,
    SUM(v.costo_total)                  AS costo_total,
    SUM(v.gmv) - SUM(v.costo_total)     AS margen_bruto,
    COUNT(DISTINCT v.item_id)           AS skus_activos,
    SUM(v.unidades_vendidas)            AS unidades_totales
  FROM ventas v
  JOIN `test-eda-507323.producto.vendors` ven USING (vendor_id)
  GROUP BY v.vendor_id, ven.vendor_name, v.category
)
SELECT
  vendor_id,
  vendor_name,
  category,
  gmv_total,
  costo_total,
  margen_bruto,
  ROUND(SAFE_DIVIDE(margen_bruto, costo_total), 2) AS gmroi,
  skus_activos,
  ROUND(SAFE_DIVIDE(unidades_totales, periodo_dias), 2) AS velocidad_venta_unid_dia,
  CASE WHEN SAFE_DIVIDE(margen_bruto, costo_total) < 1 THEN 'ALERTA_GMROI_BAJO' ELSE 'OK' END AS flag_gmroi
FROM agregado
ORDER BY gmroi ASC;

-- ============================================================================
-- QUERY 5 · DETECCIÓN DE POSIBLES QUIEBRES DE STOCK
-- ============================================================================
-- Patrón "gaps and islands": se construye el calendario de días con venta real por combinación store_id + item_id
-- Se calcula la diferencia con el día de venta anterior con LAG(), y se marcan como quiebre los gaps >= 3 días.
-- Historial de ventas para ver items que tienen al menos 2 días de venta registrados (para poder medir gap).

WITH ventas_diarias AS (
  SELECT DISTINCT
    t.store_id,
    ti.item_id,
    t.transaction_date
  FROM `test-eda-507323.producto.transaction_items` ti
  JOIN `test-eda-507323.producto.transactions` t USING (transaction_id)
  WHERE t.status = 'COMPLETED'
),
con_gap AS (
  SELECT
    store_id,
    item_id,
    transaction_date,
    LAG(transaction_date) OVER (PARTITION BY store_id, item_id ORDER BY transaction_date) AS fecha_venta_anterior,
    DATE_DIFF(
      transaction_date,
      LAG(transaction_date) OVER (PARTITION BY store_id, item_id ORDER BY transaction_date),
      DAY
    ) AS dias_sin_venta
  FROM ventas_diarias
),
gaps_detectados AS (
  SELECT
    store_id,
    item_id,
    fecha_venta_anterior AS gap_inicio,
    transaction_date     AS gap_fin,
    dias_sin_venta        AS duracion_dias
  FROM con_gap
  WHERE dias_sin_venta >= 3
),
venta_previa AS (
  -- Venta promedio diaria y precio promedio en los 30 días previos al gap,
  -- usados para estimar el GMV perdido durante el quiebre.
  SELECT
    g.store_id,
    g.item_id,
    g.gap_inicio,
    g.gap_fin,
    g.duracion_dias,
    ROUND(AVG(ti.quantity), 2)   AS venta_promedio_diaria_previa,
    ROUND(AVG(ti.unit_price), 2) AS precio_promedio
  FROM gaps_detectados g
  JOIN `test-eda-507323.producto.transactions` t
    ON t.store_id = g.store_id
    AND t.transaction_date BETWEEN DATE_SUB(g.gap_inicio, INTERVAL 30 DAY) AND g.gap_inicio
  JOIN `test-eda-507323.producto.transaction_items` ti
    ON ti.transaction_id = t.transaction_id AND ti.item_id = g.item_id
  GROUP BY g.store_id, g.item_id, g.gap_inicio, g.gap_fin, g.duracion_dias
)
SELECT
  vp.store_id,
  s.store_name,
  vp.item_id,
  p.item_name,
  p.category,
  vp.gap_inicio,
  vp.gap_fin,
  vp.duracion_dias,
  vp.venta_promedio_diaria_previa,
  ROUND(vp.venta_promedio_diaria_previa * vp.duracion_dias * vp.precio_promedio, 2) AS gmv_estimado_perdido
FROM venta_previa vp
JOIN `test-eda-507323.producto.stores`  s USING (store_id)
JOIN `test-eda-507323.producto.producto` p USING (item_id)
ORDER BY gmv_estimado_perdido DESC;

-- ============================================================================
-- QUERY 6 · IMPACTO DE PROMOCIONES EN TICKET Y VOLUMEN (Basket Analysis)
-- ============================================================================
WITH transacciones_categoria AS (
  SELECT
    t.transaction_id,
    p.category,
    MAX(CASE WHEN ti.was_on_promo THEN 1 ELSE 0 END) AS tiene_item_en_promo,
    SUM(ti.quantity) AS unidades_transaccion,
    SUM(ti.unit_price * ti.quantity) AS monto_transaccion
  FROM `test-eda-507323.producto.transaction_items` ti
  JOIN `test-eda-507323.producto.transactions` t USING (transaction_id)
  JOIN `test-eda-507323.producto.products` p USING (item_id)
  WHERE t.status = 'COMPLETED'
  GROUP BY t.transaction_id, p.category
)
SELECT
  category,
  tiene_item_en_promo,
  COUNT(DISTINCT transaction_id) AS num_transacciones,
  ROUND(AVG(monto_transaccion), 2) AS ticket_promedio,
  ROUND(AVG(unidades_transaccion), 2) AS unidades_promedio
FROM transacciones_categoria
GROUP BY category, tiene_item_en_promo
ORDER BY category, tiene_item_en_promo DESC;

-- Interpretación esperada: comparar ticket_promedio y unidades_promedio entre promo=1 vs promo=0 dentro de cada categoría. 
-- Si unidades_promedio sube significativamente con promo => aumento por compras adicionales.
-- Si solo cambia el monto pero no las unidades => es solo descuento en lobque ya se iba a comprar.


