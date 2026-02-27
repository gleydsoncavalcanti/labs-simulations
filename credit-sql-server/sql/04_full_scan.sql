-- ============================================================
-- INCIDENTE 3: Full Table Scan (sem índice)
-- Força uso intenso de I/O e CPU por varredura completa
-- ============================================================
USE SimDB;
GO

-- Query sem índice no OrderID (coluna de OrderItems sem índice)
-- Vai gerar full scan + alto logical reads
DECLARE @i INT = 0;
WHILE @i < 20
BEGIN
    SELECT COUNT(*), SUM(Price * Quantity)
    FROM OrderItems
    WHERE OrderID > 0       -- sem índice nessa coluna
      AND ProductID > 0     -- sem índice
      AND Price > 0;

    SELECT o.Status, COUNT(*), SUM(oi.Price * oi.Quantity)
    FROM Orders o
    JOIN OrderItems oi ON o.OrderID = oi.OrderID  -- join sem índice em OrderItems.OrderID
    WHERE o.CreatedAt > DATEADD(DAY, -365, GETDATE())
    GROUP BY o.Status;

    SET @i = @i + 1;
END;

PRINT 'Full scan simulado: ' + CAST(@i AS VARCHAR) + ' iterações';
GO
