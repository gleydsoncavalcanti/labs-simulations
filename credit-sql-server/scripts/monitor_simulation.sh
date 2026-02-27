#!/bin/bash

# ============================================
# Monitor de Simulação - Produto de Crédito
# Mostra estatísticas em tempo real
# ============================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear

echo -e "${BLUE}=============================================="
echo "  MONITOR - PRODUTO DE CRÉDITO"
echo -e "==============================================${NC}"
echo ""

while true; do
    # Move cursor para o topo
    tput cup 4 0
    
    # Timestamp
    echo -e "${CYAN}$(date +'%Y-%m-%d %H:%M:%S')${NC}"
    echo "----------------------------------------------"
    
    # Estatísticas do banco (usando usuário datadog para monitoramento)
    stats=$(docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U datadog -P 'Datadog123!@#' -C -Q "
    SET NOCOUNT ON;
    USE SimDB;
    
    -- Contadores
    DECLARE @pending INT, @analyzing INT, @approved INT, @rejected INT;
    DECLARE @total_customers INT, @total_proposals INT, @total_analysis INT;
    
    SELECT @pending = COUNT(*) FROM CreditProposals WHERE Status = 'PENDING';
    SELECT @analyzing = COUNT(*) FROM CreditProposals WHERE Status = 'ANALYZING';
    SELECT @approved = COUNT(*) FROM CreditProposals WHERE Status = 'APPROVED';
    SELECT @rejected = COUNT(*) FROM CreditProposals WHERE Status = 'REJECTED';
    SELECT @total_customers = COUNT(*) FROM Customers;
    SELECT @total_proposals = COUNT(*) FROM CreditProposals;
    SELECT @total_analysis = COUNT(*) FROM CreditAnalysis;
    
    -- Output formatado
    PRINT '📊 ESTATÍSTICAS DO BANCO';
    PRINT '  Total Clientes: ' + CAST(@total_customers AS VARCHAR);
    PRINT '  Total Propostas: ' + CAST(@total_proposals AS VARCHAR);
    PRINT '  Total Análises: ' + CAST(@total_analysis AS VARCHAR);
    PRINT '';
    PRINT '📋 STATUS DAS PROPOSTAS';
    PRINT '  Pendentes: ' + CAST(@pending AS VARCHAR);
    PRINT '  Em Análise: ' + CAST(@analyzing AS VARCHAR);
    PRINT '  Aprovadas: ' + CAST(@approved AS VARCHAR);
    PRINT '  Rejeitadas: ' + CAST(@rejected AS VARCHAR);
    PRINT '';
    
    -- Últimas 5 propostas
    PRINT '🔄 ÚLTIMAS 5 ATIVIDADES';
    SELECT TOP 5 
        ProposalID,
        Status,
        FORMAT(RequestedAmount, 'N2') AS Amount,
        FORMAT(CreatedAt, 'HH:mm:ss') AS Time
    FROM CreditProposals 
    ORDER BY CreatedAt DESC;
    " 2>/dev/null)
    
    echo "$stats"
    echo ""
    echo "----------------------------------------------"
    
    # Métricas do SQL Server
    echo -e "${YELLOW}⚡ MÉTRICAS DO SQL SERVER${NC}"
    
    metrics=$(docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U datadog -P 'Datadog123!@#' -C -Q "
    SET NOCOUNT ON;
    
    -- CPU e conexões
    SELECT 
        'CPU %' = (SELECT TOP 1 CAST(cntr_value AS VARCHAR) 
                   FROM sys.dm_os_performance_counters 
                   WHERE counter_name LIKE '%CPU%' 
                   AND cntr_type = 65792),
        'Conexões Ativas' = (SELECT COUNT(*) 
                             FROM sys.dm_exec_sessions 
                             WHERE is_user_process = 1),
        'Batch Requests/s' = (SELECT TOP 1 CAST(cntr_value AS VARCHAR)
                              FROM sys.dm_os_performance_counters
                              WHERE counter_name = 'Batch Requests/sec')
    " 2>/dev/null | tail -n +3)
    
    echo "$metrics"
    echo ""
    
    # Top 3 queries lentas
    echo -e "${RED}🐌 TOP 3 QUERIES LENTAS (última hora)${NC}"
    
    slow_queries=$(docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U datadog -P 'Datadog123!@#' -C -Q "
    SET NOCOUNT ON;
    
    SELECT TOP 3
        SUBSTRING(qt.text, 1, 100) AS query_text,
        CAST(qs.total_elapsed_time / 1000000.0 AS DECIMAL(10,2)) AS total_sec,
        qs.execution_count AS exec_count,
        CAST(qs.total_elapsed_time / qs.execution_count / 1000.0 AS DECIMAL(10,2)) AS avg_ms
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
    WHERE qs.last_execution_time > DATEADD(HOUR, -1, GETDATE())
    ORDER BY qs.total_elapsed_time DESC
    " 2>/dev/null | tail -n +3)
    
    echo "$slow_queries"
    echo ""
    
    # Locks e waits
    echo -e "${YELLOW}🔒 LOCKS E WAITS${NC}"
    
    locks=$(docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U datadog -P 'Datadog123!@#' -C -Q "
    SET NOCOUNT ON;
    
    SELECT 
        'Lock Waits' = (SELECT COUNT(*) FROM sys.dm_os_waiting_tasks 
                        WHERE wait_type LIKE 'LCK%'),
        'Deadlocks' = (SELECT cntr_value FROM sys.dm_os_performance_counters 
                       WHERE counter_name = 'Number of Deadlocks/sec' 
                       AND instance_name = '_Total')
    " 2>/dev/null | tail -n +3)
    
    echo "$locks"
    echo ""
    
    echo "----------------------------------------------"
    echo -e "${CYAN}Atualizando em 5 segundos... (Ctrl+C para sair)${NC}"
    
    sleep 5
done
