-- =========================================================
-- Slow Query proposital
-- =========================================================

-- Query com CROSS JOIN pesado (cartesian product parcial)
SELECT
    c.full_name,
    c.credit_score,
    cp.requested_amount,
    cp.status,
    ca.risk_level
FROM customers c
CROSS JOIN credit_proposals cp
JOIN credit_analysis ca ON ca.proposal_id = cp.proposal_id
WHERE c.credit_score > 800
  AND cp.requested_amount > 40000
ORDER BY cp.requested_amount DESC
LIMIT 100;

-- Subquery correlacionada (lenta por natureza)
SELECT
    c.customer_id,
    c.full_name,
    (SELECT COUNT(*) FROM credit_proposals cp WHERE cp.customer_id = c.customer_id) AS total_proposals,
    (SELECT AVG(requested_amount) FROM credit_proposals cp WHERE cp.customer_id = c.customer_id) AS avg_amount,
    (SELECT MAX(created_at) FROM credit_proposals cp WHERE cp.customer_id = c.customer_id) AS last_proposal
FROM customers c
WHERE c.credit_score > 700
ORDER BY total_proposals DESC;
