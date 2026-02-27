-- ============================================================
-- INCIDENTE 2: Deadlock
-- Duas transações que criam dependência circular
-- Rodar as duas em paralelo para forçar deadlock
-- ============================================================
USE SimDB;
GO

-- SESSÃO A: lock no ProductID=1, depois tenta ProductID=2
BEGIN TRANSACTION;

UPDATE Inventory SET Stock = Stock - 1 WHERE ProductID = 1;
WAITFOR DELAY '00:00:05';  -- pausa para a sessão B travar ProductID=2
UPDATE Inventory SET Stock = Stock - 1 WHERE ProductID = 2;

COMMIT TRANSACTION;
PRINT 'Sessão A concluída';
GO
