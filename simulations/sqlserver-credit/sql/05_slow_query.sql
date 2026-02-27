-- ============================================================
-- INCIDENTE 4: Query lenta com alto consumo de CPU e memória
-- Simula query mal otimizada com sort + hash join
-- ============================================================
USE SimDB;
GO

DECLARE @i INT = 0;
WHILE @i < 10
BEGIN
    -- Cross join intencional para explodir o resultado e forçar alto CPU
    SELECT TOP 1000
        o.OrderID,
        o.CustomerID,
        o.Amount,
        i.ProductID,
        i.Stock,
        SUM(oi.Price * oi.Quantity) OVER (PARTITION BY o.CustomerID ORDER BY o.CreatedAt
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
    FROM Orders o
    JOIN OrderItems oi ON o.OrderID = oi.OrderID
    JOIN Inventory i   ON oi.ProductID = i.ProductID
    ORDER BY running_total DESC, o.CreatedAt DESC;

    -- Força recompilação a cada iteração (simula plano instável)
    EXEC sp_recompile 'Orders';

    SET @i = @i + 1;
END;

PRINT 'Query lenta simulada: ' + CAST(@i AS VARCHAR) + ' execuções';
GO
