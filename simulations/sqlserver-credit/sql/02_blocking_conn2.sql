-- ============================================================
-- INCIDENTE 1: Blocking - CONEXÃO 2
-- Esta sessão ficará bloqueada pela conexão 1
-- ============================================================
USE SimDB;
GO

BEGIN TRANSACTION;

-- Esta query ficará bloqueada até a conexão 1 fazer commit/rollback
UPDATE Inventory
SET Stock = Stock + 1
WHERE ProductID = 1;

COMMIT TRANSACTION;
PRINT 'Conexão 2: desbloqueada e commit feito.';
GO
