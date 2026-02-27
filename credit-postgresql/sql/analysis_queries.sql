-- =========================================================
-- Queries de diagnóstico para PostgreSQL
-- =========================================================

-- ── Top queries por duração total ──
SELECT
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round(stddev_exec_time::numeric, 2) AS stddev_ms,
    rows,
    round((shared_blks_hit::numeric / nullif(shared_blks_hit + shared_blks_read, 0)) * 100, 2) AS cache_hit_pct,
    left(query, 100) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;

-- ── Tabelas: seq scans vs index scans ──
SELECT
    schemaname || '.' || relname AS table_name,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_live_tup AS live_rows,
    n_dead_tup AS dead_rows,
    round(n_dead_tup::numeric / nullif(n_live_tup, 0) * 100, 2) AS dead_pct,
    last_vacuum,
    last_autovacuum,
    last_analyze
FROM pg_stat_user_tables
ORDER BY seq_tup_read DESC;

-- ── Cache hit ratio por tabela ──
SELECT
    schemaname || '.' || relname AS table_name,
    heap_blks_read,
    heap_blks_hit,
    round(heap_blks_hit::numeric / nullif(heap_blks_hit + heap_blks_read, 0) * 100, 2) AS cache_hit_pct
FROM pg_statio_user_tables
WHERE heap_blks_read + heap_blks_hit > 0
ORDER BY heap_blks_read DESC;

-- ── Índices não utilizados ──
SELECT
    schemaname || '.' || relname AS table_name,
    indexrelname AS index_name,
    idx_scan AS scans,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelname NOT LIKE '%pkey%'
ORDER BY pg_relation_size(indexrelid) DESC;

-- ── Locks ativos ──
SELECT
    pid,
    usename,
    pg_blocking_pids(pid) AS blocked_by,
    wait_event_type,
    wait_event,
    state,
    left(query, 80) AS query,
    NOW() - query_start AS duration
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
ORDER BY query_start;

-- ── Tamanho das tabelas ──
SELECT
    schemaname || '.' || relname AS table_name,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    pg_size_pretty(pg_relation_size(relid)) AS table_size,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS index_size,
    n_live_tup AS rows
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

-- ── Conexões ativas ──
SELECT
    datname,
    usename,
    state,
    COUNT(*) AS connections
FROM pg_stat_activity
GROUP BY datname, usename, state
ORDER BY connections DESC;
