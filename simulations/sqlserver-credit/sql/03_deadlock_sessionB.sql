-- ============================================================
-- INCIDENTE 2: Deadlock - SESSÃO B
-- ============================================================
USE SimDB;
GO

-- SESSÃO B: lock no ProductID=2, depois tenta ProductID=1
BEGIN TRANSACTION;

UPDATE Inventory SET Stock = Stock - 1 WHERE ProductID = 2;
WAITFOR DELAY '00:00:05';  -- pausa para criar a dependência circular
UPDATE Inventory SET Stock = Stock - 1 WHERE ProductID = 1;

COMMIT TRANSACTION;
PRINT 'Sessão B concluída';
GO
