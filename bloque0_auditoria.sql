-- BLOQUE 0 · AUDITORÍA DE CALIDAD DE DATOS
-- ----------------------------------------------------------------------------
-- 1. COMPLETITUD
-- ¿Qué % de transacciones no tiene customer_id? ¿Coincide con loyalty_card = FALSE?
-- ----------------------------------------------------------------------------
SELECT
  COUNT(*) AS total_transacciones,
  COUNTIF(customer_id IS NULL) AS sin_customer_id,
  ROUND(COUNTIF(customer_id IS NULL) / COUNT(*) * 100, 2) AS pct_sin_customer_id,
  COUNTIF(loyalty_card = FALSE) AS sin_loyalty,
  COUNTIF(customer_id IS NULL AND loyalty_card = TRUE) AS inconsistente_loyalty_true_sin_id,
  COUNTIF(customer_id IS NOT NULL AND loyalty_card = FALSE) AS inconsistente_loyalty_false_con_id
FROM `test-eda-507323.producto.transactions`;	

-- ----------------------------------------------------------------------------
-- 2. CONSISTENCIA
-- ¿total_amount coincide con SUM(unit_price * quantity) de transaction_items?
-- ----------------------------------------------------------------------------
WITH calculado AS (
  SELECT
    transaction_id,
    SUM(unit_price * quantity) AS monto_calculado
  FROM `test-eda-507323.producto.transaction_items`
  GROUP BY transaction_id
)
SELECT
  t.transaction_id,
  t.total_amount,
  c.monto_calculado,
  ROUND(ABS(t.total_amount - c.monto_calculado), 2) AS diferencia_abs,
  ROUND(SAFE_DIVIDE(ABS(t.total_amount - c.monto_calculado), t.total_amount) * 100, 2) AS diferencia_pct
FROM `test-eda-507323.producto.transactions` t
LEFT JOIN calculado c USING (transaction_id)
WHERE ABS(t.total_amount - IFNULL(c.monto_calculado, 0)) > 0.01 * t.total_amount  -- tolerancia 1%
ORDER BY diferencia_abs DESC;

-- Resumen agregado de consistencia
WITH calculado AS (
  SELECT transaction_id, SUM(unit_price * quantity) AS monto_calculado
  FROM `test-eda-507323.producto.transaction_items`
  GROUP BY transaction_id
)
SELECT
  COUNT(*) AS total_transacciones,
  COUNTIF(ABS(t.total_amount - IFNULL(c.monto_calculado, 0)) > 0.01 * t.total_amount) AS transacciones_inconsistentes,
  ROUND(COUNTIF(ABS(t.total_amount - IFNULL(c.monto_calculado, 0)) > 0.01 * t.total_amount) / COUNT(*) * 100, 2) AS pct_inconsistentes,
  COUNTIF(c.transaction_id IS NULL) AS transacciones_sin_items
FROM `test-eda-507323.producto.transactions` t
LEFT JOIN calculado c USING (transaction_id);

-- ----------------------------------------------------------------------------
-- 3. UNICIDAD
-- ¿Existen transaction_id duplicados?
-- ----------------------------------------------------------------------------

SELECT
  transaction_id,
  COUNT(*) AS veces_repetido
FROM `test-eda-507323.producto.transactions`
GROUP BY transaction_id
HAVING COUNT(*) > 1
ORDER BY veces_repetido DESC;

-- Duplicados exactos de fila completa (posible carga duplicada del pipeline)
SELECT transaction_id, customer_id, transaction_date, store_id, total_amount,
       payment_method, loyalty_card, status, COUNT(*) AS repeticiones
FROM `test-eda-507323.producto.transactions` 
GROUP BY ALL
HAVING COUNT(*) > 1; 

-- ----------------------------------------------------------------------------
-- 4. VALIDEZ
-- ¿total_amount negativo o cero? ¿unit_price = 0 sin promo?
-- ----------------------------------------------------------------------------
SELECT
  COUNTIF(total_amount <= 0) AS transacciones_monto_invalido,
  COUNTIF(total_amount < 0) AS transacciones_monto_negativo
FROM `test-eda-507323.producto.transactions`
WHERE status = 'COMPLETED';  -- las RETURNED podrían justificar montos negativos; se analiza aparte

SELECT
  COUNT(*) AS items_precio_cero_sin_promo
FROM `test-eda-507323.producto.transaction_items` 
WHERE unit_price = 0 AND was_on_promo = FALSE;

-- Cruce con status: ¿los montos negativos concentran en RETURNED?
SELECT status, COUNTIF(total_amount < 0) AS negativos, COUNTIF(total_amount = 0) AS ceros, COUNT(*) AS total
FROM `test-eda-507323.producto.transactions` 
GROUP BY status;

-- ----------------------------------------------------------------------------
-- 5. INTEGRIDAD REFERENCIAL
-- ----------------------------------------------------------------------------
-- store_id en transactions que no existen en stores
SELECT DISTINCT t.store_id
FROM `test-eda-507323.producto.transactions` t
LEFT JOIN `test-eda-507323.producto.stores` s USING (store_id)
WHERE s.store_id IS NULL;

-- vendor_id en products que no existen en vendors
SELECT DISTINCT p.vendor_id
FROM `test-eda-507323.producto.producto` p
LEFT JOIN `test-eda-507323.producto.vendors` v USING (vendor_id)
WHERE v.vendor_id IS NULL;

-- item_id en transaction_items que no existen en products (chequeo adicional recomendado)
SELECT DISTINCT ti.item_id
FROM `test-eda-507323.producto.transaction_items` ti
LEFT JOIN `test-eda-507323.producto.producto` p USING (item_id)
WHERE p.item_id IS NULL;

-- transaction_id en transaction_items sin transacción padre
SELECT DISTINCT ti.transaction_id
FROM `test-eda-507323.producto.transaction_items` ti
LEFT JOIN `test-eda-507323.producto.transactions` t USING (transaction_id)
WHERE t.transaction_id IS NULL;

-- ----------------------------------------------------------------------------
-- 6. FRESCURA
-- ¿Tiendas con gaps de días consecutivos sin transacciones?
-- ----------------------------------------------------------------------------
WITH dias_con_venta AS (
  SELECT DISTINCT store_id, transaction_date
  FROM `test-eda-507323.producto.transactions`
),
con_gap AS ( 
  SELECT 
    store_id, 
    transaction_date,
    LAG(transaction_date) OVER (PARTITION BY store_id ORDER BY transaction_date) AS fecha_anterior,
    DATE_DIFF(transaction_date, LAG(transaction_date) OVER (PARTITION BY store_id ORDER BY transaction_date), DAY) AS dias_gap
  FROM dias_con_venta
  )
SELECT 
  store_id,
  fecha_anterior, 
  transaction_date AS fecha_reanudacion, 
  dias_gap
FROM con_gap
WHERE dias_gap >= 3 -- Umbral de más de 3 días en los que no se haya hecho ninguna venta puede considerarse una alerta
ORDER BY dias_gap DESC; 

-- ----------------------------------------------------------------------------
-- 7. INTEGRIDAD TEMPORAL
-- ¿Transacciones anteriores a la apertura de la tienda?
-- ----------------------------------------------------------------------------
SELECT
  t.store_id,
  s.opening_date,
  MIN(t.transaction_date) AS primera_transaccion,
  COUNTIF(t.transaction_date < s.opening_date) AS transacciones_antes_apertura
FROM `test-eda-507323.producto.transactions` t
JOIN `test-eda-507323.producto.stores` s USING (store_id)
GROUP BY t.store_id, s.opening_date
HAVING transacciones_antes_apertura > 0;

-- ----------------------------------------------------------------------------
-- 8. A/B TEST — ASIGNACIÓN DUPLICADA
-- ¿Tiendas asignadas simultáneamente a CONTROL y TREATMENT?
-- ----------------------------------------------------------------------------
SELECT
  store_id,
  promo_name,
  COUNT(DISTINCT variant) AS variantes_distintas,
  STRING_AGG(DISTINCT variant) AS variantes -- Para tener todas las variantes concatenadas en una sola variable
FROM `test-eda-507323.producto.store_promotions`
GROUP BY store_id, promo_name
HAVING COUNT(DISTINCT variant) > 1;

-- Chequeo adicional: solapamiento de fechas entre distintos experimentos para la misma tienda
SELECT
  a.store_id, a.promo_name AS promo_a, b.promo_name AS promo_b,
  a.start_date AS a_inicio, a.end_date AS a_fin, b.start_date AS b_inicio, b.end_date AS b_fin
FROM `test-eda-507323.producto.store_promotions` a
JOIN `test-eda-507323.producto.store_promotions` b
  ON a.store_id = b.store_id
  AND a.promo_name < b.promo_name
  AND a.start_date <= b.end_date
  AND b.start_date <= a.end_date;

