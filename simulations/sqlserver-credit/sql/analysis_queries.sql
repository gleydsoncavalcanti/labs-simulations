-- =========================================================
-- QUERIES ÚTEIS PARA ANÁLISE - Produto de Crédito
-- Execute estas queries para investigar problemas
-- =========================================================
USE SimDB;
GO

-- ══════════════════════════════════════════════════════════
-- 📊 ESTATÍSTICAS GERAIS
-- ══════════════════════════════════════════════════════════

-- Resumo geral do sistema
SELECT 
    'Total Clientes' AS Metrica,
    COUNT(*) AS Valor
FROM Customers
UNION ALL
SELECT 'Total Propostas', COUNT(*) FROM CreditProposals
UNION ALL
SELECT 'Propostas Pendentes', COUNT(*) FROM CreditProposals WHERE Status = 'PENDING'
UNION ALL
SELECT 'Propostas Aprovadas', COUNT(*) FROM CreditProposals WHERE Status = 'APPROVED'
UNION ALL
SELECT 'Total Análises', COUNT(*) FROM CreditAnalysis;
GO

-- Distribuição por status
SELECT 
    Status,
    COUNT(*) AS Total,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) AS Percentual
FROM CreditProposals
GROUP BY Status
ORDER BY Total DESC;
GO

-- ══════════════════════════════════════════════════════════
-- 🐌 IDENTIFICAR QUERIES LENTAS
-- ══════════════════════════════════════════════════════════

-- Top 10 queries mais lentas (tempo total)
SELECT TOP 10
    SUBSTRING(qt.text, 1, 200) AS query_text,
    qs.execution_count AS exec_count,
    CAST(qs.total_elapsed_time / 1000000.0 AS DECIMAL(10,2)) AS total_sec,
    CAST(qs.total_elapsed_time / qs.execution_count / 1000.0 AS DECIMAL(10,2)) AS avg_ms,
    CAST(qs.max_elapsed_time / 1000.0 AS DECIMAL(10,2)) AS max_ms,
    qs.last_execution_time
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_elapsed_time DESC;
GO

-- Top 10 queries com pior tempo médio
SELECT TOP 10
    SUBSTRING(qt.text, 1, 200) AS query_text,
    qs.execution_count AS exec_count,
    CAST(qs.total_elapsed_time / qs.execution_count / 1000.0 AS DECIMAL(10,2)) AS avg_ms,
    CAST(qs.max_elapsed_time / 1000.0 AS DECIMAL(10,2)) AS max_ms,
    qs.last_execution_time
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qs.execution_count > 5
ORDER BY qs.total_elapsed_time / qs.execution_count DESC;
GO

-- ══════════════════════════════════════════════════════════
-- 📈 MÉTRICAS DE PERFORMANCE
-- ══════════════════════════════════════════════════════════

-- Métricas gerais do servidor
SELECT 
    'CPU Usage %' AS Metric,
    cntr_value AS Value
FROM sys.dm_os_performance_counters
WHERE counter_name LIKE '%CPU%' AND cntr_type = 65792
UNION ALL
SELECT 
    'Batch Requests/sec',
    cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Batch Requests/sec'
UNION ALL
SELECT 
    'Page Life Expectancy',
    cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Page life expectancy'
UNION ALL
SELECT 
    'Buffer Cache Hit Ratio',
    cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Buffer cache hit ratio';
GO

-- Sessões ativas
SELECT 
    session_id,
    login_name,
    host_name,
    program_name,
    status,
    cpu_time,
    memory_usage,
    last_request_start_time,
    last_request_end_time
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
ORDER BY cpu_time DESC;
GO

-- ══════════════════════════════════════════════════════════
-- 🔒 LOCKS E BLOCKS
-- ══════════════════════════════════════════════════════════

-- Sessões bloqueadas
SELECT 
    t1.resource_type,
    t1.request_session_id AS blocked_session,
    t2.blocking_session_id AS blocking_session,
    t1.resource_description,
    t1.request_mode,
    t1.request_status
FROM sys.dm_tran_locks t1
JOIN sys.dm_os_waiting_tasks t2 
    ON t1.lock_owner_address = t2.resource_address
WHERE t2.blocking_session_id IS NOT NULL;
GO

-- Wait statistics
SELECT TOP 20
    wait_type,
    wait_time_ms / 1000.0 AS wait_time_sec,
    waiting_tasks_count,
    wait_time_ms / NULLIF(waiting_tasks_count, 0) AS avg_wait_ms
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
    AND wait_type NOT LIKE 'SLEEP%'
    AND wait_type NOT LIKE 'CLR%'
    AND wait_type NOT LIKE 'XE%'
    AND wait_type NOT LIKE 'BROKER%'
ORDER BY wait_time_ms DESC;
GO

-- ══════════════════════════════════════════════════════════
-- 📑 ÍNDICES E TABELAS
-- ══════════════════════════════════════════════════════════

-- Missing Indexes (sugestões do SQL Server)
SELECT 
    migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    'CREATE INDEX IX_' + 
    OBJECT_NAME(mid.object_id) + '_' + 
    REPLACE(REPLACE(ISNULL(mid.equality_columns, ''), ', ', '_'), '[', '') AS index_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact
FROM sys.dm_db_missing_index_groups mig
INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY improvement_measure DESC;
GO

-- Índices não utilizados (candidatos para remoção)
SELECT 
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    i.type_desc,
    us.user_seeks,
    us.user_scans,
    us.user_lookups,
    us.user_updates
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us 
    ON i.object_id = us.object_id 
    AND i.index_id = us.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND i.type_desc <> 'HEAP'
    AND (us.user_seeks IS NULL OR us.user_seeks = 0)
    AND (us.user_scans IS NULL OR us.user_scans = 0)
    AND (us.user_lookups IS NULL OR us.user_lookups = 0)
ORDER BY us.user_updates DESC;
GO

-- Fragmentação de índices
SELECT 
    OBJECT_NAME(ips.object_id) AS table_name,
    i.name AS index_name,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10
    AND ips.page_count > 1000
ORDER BY ips.avg_fragmentation_in_percent DESC;
GO

-- ══════════════════════════════════════════════════════════
-- 🔍 ANÁLISE DE DADOS DO PRODUTO
-- ══════════════════════════════════════════════════════════

-- Taxa de aprovação por tipo de proposta
SELECT 
    ProposalType,
    COUNT(*) AS Total,
    SUM(CASE WHEN Status = 'APPROVED' THEN 1 ELSE 0 END) AS Aprovadas,
    SUM(CASE WHEN Status = 'REJECTED' THEN 1 ELSE 0 END) AS Rejeitadas,
    CAST(SUM(CASE WHEN Status = 'APPROVED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS TaxaAprovacao
FROM CreditProposals
GROUP BY ProposalType
ORDER BY Total DESC;
GO

-- Análise por score de crédito
SELECT 
    CASE 
        WHEN c.CreditScore < 400 THEN '< 400 (Muito Baixo)'
        WHEN c.CreditScore < 600 THEN '400-599 (Baixo)'
        WHEN c.CreditScore < 700 THEN '600-699 (Médio)'
        WHEN c.CreditScore < 800 THEN '700-799 (Alto)'
        ELSE '800+ (Muito Alto)'
    END AS FaixaScore,
    COUNT(DISTINCT c.CustomerID) AS TotalClientes,
    COUNT(p.ProposalID) AS TotalPropostas,
    AVG(p.RequestedAmount) AS ValorMedio,
    SUM(CASE WHEN p.Status = 'APPROVED' THEN 1 ELSE 0 END) AS Aprovadas
FROM Customers c
LEFT JOIN CreditProposals p ON c.CustomerID = p.CustomerID
GROUP BY 
    CASE 
        WHEN c.CreditScore < 400 THEN '< 400 (Muito Baixo)'
        WHEN c.CreditScore < 600 THEN '400-599 (Baixo)'
        WHEN c.CreditScore < 700 THEN '600-699 (Médio)'
        WHEN c.CreditScore < 800 THEN '700-799 (Alto)'
        ELSE '800+ (Muito Alto)'
    END
ORDER BY FaixaScore;
GO

-- Tempo médio de análise
SELECT 
    ca.AnalysisType,
    COUNT(*) AS Total,
    AVG(ca.ProcessingTimeMs) AS AvgTimeMs,
    MIN(ca.ProcessingTimeMs) AS MinTimeMs,
    MAX(ca.ProcessingTimeMs) AS MaxTimeMs,
    AVG(CASE WHEN ca.Recommendation = 'APPROVE' THEN 1.0 ELSE 0.0 END) * 100 AS TaxaAprovacao
FROM CreditAnalysis ca
GROUP BY ca.AnalysisType
ORDER BY Total DESC;
GO

-- Volume de propostas por hora (últimas 24h)
SELECT 
    DATEPART(HOUR, CreatedAt) AS Hora,
    COUNT(*) AS Total,
    AVG(RequestedAmount) AS ValorMedio
FROM CreditProposals
WHERE CreatedAt >= DATEADD(HOUR, -24, GETDATE())
GROUP BY DATEPART(HOUR, CreatedAt)
ORDER BY Hora;
GO

-- ══════════════════════════════════════════════════════════
-- 🎯 TROUBLESHOOTING ESPECÍFICO
-- ══════════════════════════════════════════════════════════

-- Queries em execução no momento
SELECT 
    r.session_id,
    r.status,
    r.command,
    r.cpu_time,
    r.total_elapsed_time / 1000.0 AS elapsed_sec,
    r.wait_type,
    r.wait_time,
    r.blocking_session_id,
    SUBSTRING(qt.text, 1, 500) AS query_text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) qt
WHERE r.session_id <> @@SPID
ORDER BY r.total_elapsed_time DESC;
GO

-- Planos de execução em cache que fazem scan
SELECT 
    cp.usecounts AS exec_count,
    CAST(cp.size_in_bytes / 1024.0 AS DECIMAL(10,2)) AS size_kb,
    qs.total_elapsed_time / 1000000.0 AS total_sec,
    SUBSTRING(qt.text, 1, 500) AS query_text
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) qt
LEFT JOIN sys.dm_exec_query_stats qs ON cp.plan_handle = qs.plan_handle
WHERE CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%TableScan%'
    OR CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%IndexScan%'
ORDER BY qs.total_elapsed_time DESC;
GO

-- Estatísticas de I/O por query
SELECT TOP 10
    SUBSTRING(qt.text, 1, 200) AS query_text,
    qs.execution_count,
    qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
    qs.total_physical_reads / qs.execution_count AS avg_physical_reads,
    qs.total_logical_writes / qs.execution_count AS avg_logical_writes
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_logical_reads DESC;
GO

PRINT 'Queries de análise executadas com sucesso!';
PRINT 'Use estas queries para investigar problemas no DBM.';
GO
