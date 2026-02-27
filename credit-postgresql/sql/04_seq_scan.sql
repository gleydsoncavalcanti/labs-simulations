-- =========================================================
-- Sequential Scan proposital (sem uso de índice)
-- =========================================================

-- Force seq scan desabilitando index scan temporariamente
SET enable_indexscan = off;
SET enable_bitmapscan = off;

EXPLAIN ANALYZE
SELECT *
FROM credit_proposals
WHERE requested_amount > 10000
  AND status = 'APPROVED';

-- Resultado: Seq Scan em ~50k rows

-- Agora com scan habilitado (comparação)
SET enable_indexscan = on;
SET enable_bitmapscan = on;

EXPLAIN ANALYZE
SELECT *
FROM credit_proposals
WHERE requested_amount > 10000
  AND status = 'APPROVED';

-- Full table scan sem filtro
SELECT COUNT(*), AVG(requested_amount), SUM(requested_amount)
FROM credit_proposals cp
CROSS JOIN customers c
WHERE c.customer_id < 100;
