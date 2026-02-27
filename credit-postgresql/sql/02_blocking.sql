-- =========================================================
-- Simulação de Blocking (execute em duas sessions)
-- =========================================================
-- Session 1: Abre transação sem commit
BEGIN;

UPDATE credit_proposals
SET status = 'ANALYZING'
WHERE proposal_id = 1;

-- NÃO faz COMMIT — mantém lock

-- Para liberar depois:
-- COMMIT;

-- Session 2 (em outro terminal):
-- UPDATE credit_proposals SET status = 'APPROVED' WHERE proposal_id = 1;
-- (Vai ficar bloqueado esperando Session 1)
