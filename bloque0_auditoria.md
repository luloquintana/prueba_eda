# Auditoría de Calidad de Datos
Auditoría de la completitud, consistencia, unicidad, validez, etc. de los datasets. 
Para cada dataset, documentamos qué encontramos en cada hallazgo, y qué decisión conlleva para los subsecuentes bloques. 
Casos inconsistentes: no debería haber loyalty_card=TRUE sin customer_id, ni loyalty_card=FALSE con customer_id.

## Instrucciones
Documenta cada hallazgo con evidencia (conteo de filas afectadas).
Decisiones a tomar: ignorar, corregir, excluir o marcar como alerta.
Dimensiones: 
1. completitud: ¿Qué porcentaje de transacciones no tiene customer_id? ¿Es consistente con loyalty_card = FALSE?
2. consistencia: ¿El total_amount en transactions coincide con la suma de unit_price × quantity en transaction_items?
3. unicidad: ¿Existen transaction_id duplicados?
4. validez: ¿Hay total_amount negativos o cero? ¿Hay unit_price = 0 con was_on_promo =FALSE?
5. integridad inferencia: ¿Hay store_id en transactions que no existan en stores? ¿vendor_id en products que no existan en vendors?
6. frescura: ¿Hay tiendas con gaps de días consecutivos sin transacciones? ¿Son esperables osospechosos?
7. integridad temporal: ¿Existe alguna tienda con transacciones anteriores a su opening_date?
8. A/B testing: ¿Hay tiendas asignadas simultáneamente a CONTROL y TREATMENT en store_promotions?

## 1. Completitud

**Hallazgo:** 59% de las transacciones no tiene `customer_id` (`104632` de `174880` filas).
**Consistencia con `loyalty_card`:** `Coincide` — se encontraron `0` casos de `loyalty_card = TRUE` sin `customer_id` y `0` casos de `loyalty_card = FALSE` con `customer_id` asignado.
**Decisión:** Tratar `customer_id` nulo como cliente anónimo/no identificado. 
Los casos inconsistentes se marcan como alerta de captura en punto de venta, no se corrigen automáticamente.

