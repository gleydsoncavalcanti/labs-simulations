#!/bin/bash
# ============================================================
# run_simulations.sh
# Orquestra os cenários de incidente no SQL Server via sqlcmd
# Uso: ./simulate/run_simulations.sh [cenario]
# Cenários: setup | blocking | deadlock | full_scan | slow_query | all
# ============================================================

set -euo pipefail

CONTAINER="sqlserver"
SA_PASS="YourStrong!Passw0rd"
DIR="$(cd "$(dirname "$0")" && pwd)"

run_sql() {
    local file="$1"
    echo "▶ Executando: $(basename "$file")"
    docker exec -i "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASS" -C \
        -i /dev/stdin < "$file"
    echo "✔ Concluído: $(basename "$file")"
    echo ""
}

run_sql_bg() {
    local file="$1"
    local label="$2"
    echo "▶ [background] $label"
    docker exec -i "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASS" -C \
        -i /dev/stdin < "$file" &
    echo $!
}

CENARIO="${1:-all}"

case "$CENARIO" in

  setup)
    echo "=== 🏗️  Setup ==="
    run_sql "$DIR/01_setup.sql"
    ;;

  blocking)
    echo "=== 🔒 Blocking / Lock Chain ==="
    echo "Iniciando conexão 1 em background (segura lock por 30s)..."
    PID=$(run_sql_bg "$DIR/02_blocking_conn1.sql" "conn1 (blocker)")
    sleep 2
    echo "Iniciando conexão 2 (vai bloquear)..."
    run_sql "$DIR/02_blocking_conn2.sql"
    wait "$PID" 2>/dev/null || true
    echo "✔ Blocking finalizado"
    ;;

  deadlock)
    echo "=== 💀 Deadlock ==="
    echo "Iniciando sessão A em background..."
    PID=$(run_sql_bg "$DIR/03_deadlock_sessionA.sql" "sessão A")
    sleep 1
    echo "Iniciando sessão B (vai criar dependência circular)..."
    run_sql "$DIR/03_deadlock_sessionB.sql" || true
    wait "$PID" 2>/dev/null || true
    echo "✔ Deadlock simulado (uma das sessões será vítima do deadlock)"
    ;;

  full_scan)
    echo "=== 🔍 Full Table Scan ==="
    run_sql "$DIR/04_full_scan.sql"
    ;;

  slow_query)
    echo "=== 🐢 Slow Query / Alto CPU ==="
    run_sql "$DIR/05_slow_query.sql"
    ;;

  all)
    echo "=== 🚀 Rodando todos os cenários ==="
    echo ""

    echo "--- 1/5: Setup ---"
    run_sql "$DIR/01_setup.sql"
    sleep 2

    echo "--- 2/5: Full Scan ---"
    run_sql "$DIR/04_full_scan.sql"
    sleep 2

    echo "--- 3/5: Slow Query ---"
    run_sql "$DIR/05_slow_query.sql"
    sleep 2

    echo "--- 4/5: Blocking ---"
    PID=$(run_sql_bg "$DIR/02_blocking_conn1.sql" "conn1 (blocker)")
    sleep 2
    run_sql "$DIR/02_blocking_conn2.sql"
    wait "$PID" 2>/dev/null || true
    sleep 2

    echo "--- 5/5: Deadlock ---"
    PID=$(run_sql_bg "$DIR/03_deadlock_sessionA.sql" "sessão A")
    sleep 1
    run_sql "$DIR/03_deadlock_sessionB.sql" || true
    wait "$PID" 2>/dev/null || true

    echo ""
    echo "✅ Todos os incidentes simulados! Verifique o Grafana em http://localhost:3000"
    ;;

  *)
    echo "Uso: $0 [setup|blocking|deadlock|full_scan|slow_query|all]"
    exit 1
    ;;
esac
