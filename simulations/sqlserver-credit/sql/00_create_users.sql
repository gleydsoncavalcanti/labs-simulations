-- =========================================================
-- SETUP: Criação de Usuários e Permissões
-- Seguindo princípio de least privilege
-- =========================================================

USE master;
GO

-- ══════════════════════════════════════════════════════════
-- 1. Usuário para Aplicação (Read/Write)
-- ══════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT name FROM sys.sql_logins WHERE name = 'app_user')
BEGIN
    CREATE LOGIN app_user WITH PASSWORD = 'AppUser!2024#Strong';
    PRINT '✓ Login app_user criado';
END
ELSE
BEGIN
    PRINT '⚠ Login app_user já existe';
END
GO

USE SimDB;
GO

IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = 'app_user')
BEGIN
    CREATE USER app_user FOR LOGIN app_user;
    PRINT '✓ User app_user criado no banco SimDB';
END
GO

-- Permissões de leitura e escrita
ALTER ROLE db_datareader ADD MEMBER app_user;
ALTER ROLE db_datawriter ADD MEMBER app_user;

-- Permissão para executar stored procedures (se houver no futuro)
GRANT EXECUTE TO app_user;

PRINT '✓ Permissões concedidas para app_user (read/write)';
GO

-- ══════════════════════════════════════════════════════════
-- 2. Usuário para Datadog Agent (Read-Only + DBM)
-- ══════════════════════════════════════════════════════════

USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.sql_logins WHERE name = 'datadog')
BEGIN
    CREATE LOGIN datadog WITH PASSWORD = 'DatadogMonitor!2024#Strong';
    PRINT '✓ Login datadog criado';
END
ELSE
BEGIN
    PRINT '⚠ Login datadog já existe';
END
GO

-- Permissões a nível de servidor para o Datadog
GRANT VIEW SERVER STATE TO datadog;
GRANT VIEW ANY DEFINITION TO datadog;
PRINT '✓ Permissões de servidor concedidas para datadog';
GO

USE SimDB;
GO

IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = 'datadog')
BEGIN
    CREATE USER datadog FOR LOGIN datadog;
    PRINT '✓ User datadog criado no banco SimDB';
END
GO

-- Permissões de leitura
ALTER ROLE db_datareader ADD MEMBER datadog;

-- Permissões específicas para DBM
GRANT VIEW DATABASE STATE TO datadog;
GRANT VIEW DEFINITION TO datadog;

PRINT '✓ Permissões concedidas para datadog (monitoring)';
GO

-- ══════════════════════════════════════════════════════════
-- 3. Verificação das Permissões
-- ══════════════════════════════════════════════════════════

PRINT '';
PRINT '══════════════════════════════════════════════════════';
PRINT 'RESUMO DE USUÁRIOS E PERMISSÕES';
PRINT '══════════════════════════════════════════════════════';
PRINT '';

-- Listar logins
PRINT '📋 LOGINS CRIADOS:';
SELECT 
    name AS LoginName,
    type_desc AS Type,
    create_date AS Created,
    is_disabled AS Disabled
FROM sys.sql_logins
WHERE name IN ('app_user', 'datadog');
GO

-- Listar usuários do banco
USE SimDB;
GO

PRINT '';
PRINT '👤 USUÁRIOS NO BANCO SimDB:';
SELECT 
    dp.name AS UserName,
    dp.type_desc AS Type,
    dp.create_date AS Created
FROM sys.database_principals dp
WHERE dp.name IN ('app_user', 'datadog');
GO

PRINT '';
PRINT '🔐 PERMISSÕES:';
PRINT '';
PRINT 'app_user:';
PRINT '  ✓ db_datareader (SELECT em todas as tabelas)';
PRINT '  ✓ db_datawriter (INSERT, UPDATE, DELETE)';
PRINT '  ✓ EXECUTE (stored procedures)';
PRINT '';
PRINT 'datadog:';
PRINT '  ✓ db_datareader (SELECT)';
PRINT '  ✓ VIEW SERVER STATE';
PRINT '  ✓ VIEW ANY DEFINITION';
PRINT '  ✓ VIEW DATABASE STATE';
PRINT '';
PRINT '══════════════════════════════════════════════════════';
PRINT '✓ Setup de usuários concluído com sucesso!';
PRINT '══════════════════════════════════════════════════════';
GO
