-- =========================================================
-- CPU Intensive Queries
-- =========================================================

-- Cálculos pesados com generate_series
SELECT
    i,
    sqrt(i::numeric) AS raiz,
    ln(i::numeric + 1) AS logaritmo,
    power(i::numeric, 0.5) AS potencia,
    md5(i::text) AS hash_md5
FROM generate_series(1, 5000000) AS i
WHERE md5(i::text) LIKE 'a%';

-- Agregações pesadas com window functions
SELECT
    customer_id,
    proposal_id,
    requested_amount,
    status,
    SUM(requested_amount) OVER (PARTITION BY customer_id ORDER BY created_at) AS running_total,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at DESC) AS rn,
    LAG(requested_amount) OVER (PARTITION BY customer_id ORDER BY created_at) AS prev_amount
FROM credit_proposals
ORDER BY customer_id, created_at;

-- Recursive CTE (gera carga CPU)
WITH RECURSIVE fib(n, a, b) AS (
    VALUES (1, 0::BIGINT, 1::BIGINT)
    UNION ALL
    SELECT n + 1, b, a + b FROM fib WHERE n < 50
)
SELECT * FROM fib;
