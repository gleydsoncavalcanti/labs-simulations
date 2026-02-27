#!/bin/bash
# =========================================================
# Executa cenários de incidentes no PostgreSQL
# =========================================================
set -e

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-YourStrong!Passw0rd}"
PGDATABASE="${PGDATABASE:-creditdb}"

export PGPASSWORD

echo "═══════════════════════════════════════════"
echo "🔥 PostgreSQL — Incident Simulator"
echo "═══════════════════════════════════════════"

run_sql() {
    local file=$1
    local desc=$2
    echo ""
    echo "▶ $desc"
    echo "  File: $file"
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -f "$file" 2>&1 | head -20
    echo "  ✓ Concluído"
}

echo ""
echo "Escolha um cenário:"
echo "  1) Sequential Scan"
echo "  2) Slow Query"
echo "  3) CPU Intensive"
echo "  4) Todos"
echo ""
read -rp "Opção: " choice

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_DIR="$SCRIPT_DIR/../sql"

case $choice in
    1) run_sql "$SQL_DIR/04_seq_scan.sql" "Sequential Scan" ;;
    2) run_sql "$SQL_DIR/05_slow_query.sql" "Slow Query" ;;
    3) run_sql "$SQL_DIR/06_cpu_intensive.sql" "CPU Intensive" ;;
    4)
        run_sql "$SQL_DIR/04_seq_scan.sql" "Sequential Scan"
        run_sql "$SQL_DIR/05_slow_query.sql" "Slow Query"
        run_sql "$SQL_DIR/06_cpu_intensive.sql" "CPU Intensive"
        ;;
    *) echo "Opção inválida" ;;
esac

echo ""
echo "═══════════════════════════════════════════"
echo "✅ Incidentes executados!"
echo "═══════════════════════════════════════════"
