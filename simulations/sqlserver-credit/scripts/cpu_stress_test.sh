#!/bin/bash

# ============================================================
# Script: CPU Stress Test
# Descrição: Executa queries CPU-intensive em loop
# ============================================================

set -e

DURATION=${1:-300}  # Duração em segundos (padrão: 5 minutos)
DELAY=${2:-10}      # Delay entre execuções (padrão: 10 segundos)

echo "=========================================="
echo "CPU Intensive Stress Test"
echo "=========================================="
echo "Duração: ${DURATION} segundos"
echo "Delay entre execuções: ${DELAY} segundos"
echo "Início: $(date)"
echo ""

END_TIME=$((SECONDS + DURATION))

ITERATION=1

while [ $SECONDS -lt $END_TIME ]; do
    REMAINING=$((END_TIME - SECONDS))
    echo "─────────────────────────────────────────"
    echo "Iteração #${ITERATION} - Restam ${REMAINING}s"
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
    echo "─────────────────────────────────────────"
    
    # Copia o arquivo para o container (se ainda não existir)
    docker exec sqlserver test -f /tmp/06_cpu_intensive.sql || \
        docker cp $(dirname "$0")/06_cpu_intensive.sql sqlserver:/tmp/06_cpu_intensive.sql
    
    # Executa as queries CPU-intensive
    docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P 'YourStrong@Passw0rd' \
        -C -i /tmp/06_cpu_intensive.sql \
        -o /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✓ Queries executadas com sucesso"
    else
        echo "✗ Erro ao executar queries"
    fi
    
    ((ITERATION++))
    
    # Verifica se ainda há tempo para outra iteração
    if [ $((SECONDS + DELAY)) -lt $END_TIME ]; then
        echo "Aguardando ${DELAY}s..."
        sleep $DELAY
    fi
done

echo ""
echo "=========================================="
echo "CPU Stress Test Finalizado"
echo "=========================================="
echo "Total de iterações: $((ITERATION - 1))"
echo "Fim: $(date)"
