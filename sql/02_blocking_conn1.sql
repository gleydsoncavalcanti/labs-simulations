-- ============================================================
-- INCIDENTE 1: Blocking / Lock Chain
-- Simula sessão segurando lock enquanto outra tenta atualizar
-- Abrir em duas conexões separadas OU rodar via script externo
-- ============================================================
USE SimDB;
GO

-- CONEXÃO 1: inicia transação e segura o lock (não faz COMMIT)
-- Execute isso e NÃO faça commit por 30-60 segundos
BEGIN TRANSACTION;

UPDATE Inventory
SET Stock = Stock - 1,
    LastUpdated = GETDATE()
WHERE ProductID = 1;

-- Simula trabalho lento (30s de espera antes do commit)
WAITFOR DELAY '00:00:30';

COMMIT TRANSACTION;
PRINT 'Conexão 1: commit feito.';
GO
