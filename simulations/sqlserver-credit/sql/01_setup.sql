-- ============================================================
-- Setup: cria banco e tabelas para simulação de incidentes
-- ============================================================
USE master;
GO

IF DB_ID('SimDB') IS NOT NULL
    DROP DATABASE SimDB;
GO

CREATE DATABASE SimDB;
GO

USE SimDB;
GO

-- Tabela principal de pedidos
CREATE TABLE Orders (
    OrderID     INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID  INT NOT NULL,
    Amount      DECIMAL(10,2) NOT NULL,
    Status      VARCHAR(20) NOT NULL DEFAULT 'pending',
    CreatedAt   DATETIME NOT NULL DEFAULT GETDATE()
);

-- Tabela sem índice (para simular full scan)
CREATE TABLE OrderItems (
    ItemID      INT IDENTITY(1,1) PRIMARY KEY,
    OrderID     INT NOT NULL,   -- sem FK e sem índice proposital
    ProductID   INT NOT NULL,
    Quantity    INT NOT NULL,
    Price       DECIMAL(10,2) NOT NULL
);

-- Tabela para simular bloqueios
CREATE TABLE Inventory (
    ProductID   INT PRIMARY KEY,
    Stock       INT NOT NULL,
    LastUpdated DATETIME NOT NULL DEFAULT GETDATE()
);

-- Popula dados iniciais
INSERT INTO Inventory (ProductID, Stock)
SELECT TOP 1000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 100
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

INSERT INTO Orders (CustomerID, Amount, Status)
SELECT TOP 5000
    ABS(CHECKSUM(NEWID())) % 1000 + 1,
    CAST(ABS(CHECKSUM(NEWID())) % 10000 AS DECIMAL(10,2)) / 100.0,
    CASE ABS(CHECKSUM(NEWID())) % 3
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'completed'
        ELSE 'cancelled'
    END
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

INSERT INTO OrderItems (OrderID, ProductID, Quantity, Price)
SELECT TOP 20000
    ABS(CHECKSUM(NEWID())) % 5000 + 1,
    ABS(CHECKSUM(NEWID())) % 1000 + 1,
    ABS(CHECKSUM(NEWID())) % 10 + 1,
    CAST(ABS(CHECKSUM(NEWID())) % 5000 AS DECIMAL(10,2)) / 100.0
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

PRINT 'Setup concluído: banco SimDB, tabelas e dados prontos.';
GO
