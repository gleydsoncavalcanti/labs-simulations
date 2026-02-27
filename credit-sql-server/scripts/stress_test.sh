#!/bin/bash
# ============================================================
# stress_test.sh
# Estressa o SQL Server ao máximo por 10 minutos
# Gera: blocking, deadlocks, full scans, slow queries, alto volume
# ============================================================

set -euo pipefail

CONTAINER="sqlserver"
SA_PASS="YourStrong!Passw0rd"
DIR="$(cd "$(dirname "$0")" && pwd)"
DURATION=600  # 10 minutos

echo "🔥 STRESS TEST INICIADO - Duração: 10 minutos"
echo "   Gerando: blocking, deadlocks, full scans, slow queries, alto volume"
echo "   Pressione Ctrl+C para interromper"
echo ""

START_TIME=$(date +%s)

# Função para rodar SQL em background
run_sql_loop() {
    local file="$1"
    local label="$2"
    local sleep_between="${3:-2}"
    
    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        
        if [ $ELAPSED -ge $DURATION ]; then
            break
        fi
        
        docker exec -i "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
            -S localhost -U sa -P "$SA_PASS" -C \
            -i /dev/stdin < "$file" 2>/dev/null || true
        
        sleep $sleep_between
    done
}

# 1) Full Scans em loop (gera I/O e CPU)
echo "▶ Iniciando full scans em loop..."
run_sql_loop "$DIR/04_full_scan.sql" "full_scan" 3 &
PIDS+=($!)

# 2) Slow Queries em loop (gera CPU e compilações)
echo "▶ Iniciando slow queries em loop..."
run_sql_loop "$DIR/05_slow_query.sql" "slow_query" 5 &
PIDS+=($!)

# 3) Blocking contínuo (sessão segura lock por tempo longo)
echo "▶ Iniciando blocking contínuo..."
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED -ge $DURATION ]; then break; fi
    
    # Blocker
    docker exec -i "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASS" -C \
        -Q "USE SimDB; BEGIN TRANSACTION; UPDATE Inventory SET Stock = Stock - 1 WHERE ProductID = 1; WAITFOR DELAY '00:00:15'; COMMIT;" &
    
    sleep 2
    
    # Vítima tentando acessar o mesmo registro
    docker exec -i "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASS" -C \
        -Q "USE SimDB; UPDATE Inventory SET Stock = Stock + 1 WHERE ProductID = 1;" &
    
    sleep 18
done &
PIDS+=($!)

# 4) Deadlocks recorrentes
echo "▶ Iniciando deadlocks recorrentes..."
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED -ge $DURATION ]; then break; fi
    
    # Sessão A: lock 1 → 2
    docker exec -i "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASS" -C \
        -Q "USE SimDB; BEGIN TRANSACTION; UPDATE Inventory SET Stock = Stock - 1 WHERE ProductID = 1; WAITFOR DELAY '00:00:03'; UPDATE Inventory SET Stock = Stock - 1 WHERE ProductID = 2; COMMIT;" &
    
    sleep 1
    
    # Sessão B: lock 2 → 1 (causa deadlock)
    docker exec -i "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASS" -C \
        -Q "USE SimDB; BEGIN TRANSACTION; UPDATE Inventory SET Stock = Stock - 1 WHERE ProductID = 2; WAITFOR DELAY '00:00:03'; UPDATE Inventory SET Stock = Stock - 1 WHERE ProductID = 1; COMMIT;" 2>/dev/null || true
    
    sleep 10
done &
PIDS+=($!)

# 5) Alto volume de SELECTs simples (throughput)
echo "▶ Iniciando alto volume de SELECTs..."
for i in {1..3}; do
    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        if [ $ELAPSED -ge $DURATION ]; then break; fi
        
        docker exec -i "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
            -S localhost -U sa -P "$SA_PASS" -C \
            -Q "USE SimDB; SELECT COUNT(*) FROM Orders WHERE Amount > RAND() * 100; SELECT COUNT(*) FROM OrderItems WHERE Price > RAND() * 50;" &>/dev/null || true
        
        sleep 0.5
    done &
    PIDS+=($!)
done

# 6) INSERTs em massa (gera log growth e contention)
echo "▶ Iniciando INSERTs em massa..."
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED -ge $DURATION ]; then break; fi
    
    docker exec -i "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASS" -C \
        -Q "USE SimDB; INSERT INTO Orders (CustomerID, Amount, Status, CreatedAt) SELECT TOP 100 ABS(CHECKSUM(NEWID())) % 1000, RAND() * 1000, 'pending', GETDATE() FROM Orders;" &>/dev/null || true
    
    sleep 4
done &
PIDS+=($!)

echo ""
echo "✅ Todos os geradores de stress iniciados!"
echo "   Aguardando 10 minutos..."
echo ""

# Aguarda o tempo total
sleep $DURATION

echo ""
echo "⏱️  Tempo esgotado. Finalizando processos..."

# Mata todos os processos background
for pid in "${PIDS[@]}"; do
    kill $pid 2>/dev/null || true
done

wait 2>/dev/null || true

echo ""
echo "🎉 STRESS TEST CONCLUÍDO!"
echo "   Verifique o DBM agora para ver os incidentes gerados:"
echo "   - Blocking Queries"
echo "   - Deadlocks"
echo "   - Query Metrics (full scans, slow queries, alto throughput)"
echo "   - Activity (sessões, waits, locks)"
echo ""
