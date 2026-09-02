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
