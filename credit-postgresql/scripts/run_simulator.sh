#!/bin/bash
# =========================================================
# Entrypoint: Aguarda PostgreSQL e roda o simulador
# =========================================================
set -e

echo "⏳ Aguardando PostgreSQL ficar pronto..."

for i in $(seq 1 30); do
    if pg_isready -h "${PGHOST:-postgres-credit}" -p "${PGPORT:-5432}" -U "${PGUSER:-app_user}" > /dev/null 2>&1; then
        echo "✅ PostgreSQL pronto!"
        break
    fi
    echo "  Tentativa $i/30..."
    sleep 2
done

echo "🚀 Iniciando simulador..."
exec ddtrace-run python /app/credit_simulator.py
