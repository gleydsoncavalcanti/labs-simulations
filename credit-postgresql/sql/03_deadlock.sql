-- =========================================================
-- Simulação de Deadlock
-- =========================================================
-- Execute em dois terminais simultaneamente:

-- Terminal A:
-- BEGIN;
-- UPDATE credit_proposals SET status = 'ANALYZING' WHERE proposal_id = 1;
-- SELECT pg_sleep(2);
-- UPDATE credit_proposals SET status = 'ANALYZING' WHERE proposal_id = 2;
-- COMMIT;

-- Terminal B:
-- BEGIN;
-- UPDATE credit_proposals SET status = 'APPROVED' WHERE proposal_id = 2;
-- SELECT pg_sleep(2);
-- UPDATE credit_proposals SET status = 'APPROVED' WHERE proposal_id = 1;
-- COMMIT;

-- Um dos dois será abortado pelo PostgreSQL (deadlock detected)
