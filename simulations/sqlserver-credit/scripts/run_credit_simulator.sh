#!/bin/bash

# ============================================
# Script de Simulação - Produto de Crédito
# ============================================

echo "=========================================="
echo "  SIMULAÇÃO DE PRODUTO DE CRÉDITO"
echo "=========================================="
echo ""

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Função para log
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERRO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] AVISO:${NC} $1"
}

# Verifica se o SQL Server está pronto
log "Verificando conexão com SQL Server..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if /opt/mssql-tools18/bin/sqlcmd -S sqlserver -U sa -P 'YourStrong!Passw0rd' -C -Q "SELECT 1" &>/dev/null; then
        log "✓ SQL Server está pronto!"
        break
    fi
    attempt=$((attempt + 1))
    warn "Aguardando SQL Server... (tentativa $attempt/$max_attempts)"
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    error "SQL Server não respondeu após $max_attempts tentativas"
    exit 1
fi

# Cria o banco de dados se não existir
log "Criando banco de dados SimDB..."
/opt/mssql-tools18/bin/sqlcmd -S sqlserver -U sa -P 'YourStrong!Passw0rd' -C -Q "
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'SimDB')
BEGIN
    CREATE DATABASE SimDB;
    PRINT 'Banco SimDB criado com sucesso';
END
ELSE
BEGIN
    PRINT 'Banco SimDB já existe';
END
"

# Cria usuários específicos (app_user e datadog)
log "Criando usuários de aplicação e monitoramento..."
if /opt/mssql-tools18/bin/sqlcmd -S sqlserver -U sa -P 'YourStrong!Passw0rd' -C -i /simulate/00_create_users.sql; then
    log "✓ Usuários criados com sucesso!"
else
    warn "Usuários podem já existir, continuando..."
fi

# Executa o setup do schema de crédito (usando sa apenas para DDL)
log "Executando setup do schema de crédito..."
if /opt/mssql-tools18/bin/sqlcmd -S sqlserver -U sa -P 'YourStrong!Passw0rd' -C -i /simulate/credit_product_setup.sql; then
    log "✓ Schema criado com sucesso!"
else
    error "Falha ao criar schema"
    exit 1
fi

# Aguarda um pouco para garantir que tudo está pronto
sleep 2

# Inicia o simulador Python
log "Iniciando simulador de produto de crédito..."
log "Serviços que serão executados:"
echo "  1. Proposal Query Service - Consulta de propostas (alta frequência)"
echo "  2. Proposal Creation Service - Criação de propostas"
echo "  3. Credit Analysis Service - Análise de crédito"
echo "  4. Customer Query Service - Consulta de clientes"
echo "  5. Analytics Service - Relatórios e analytics"
echo "  6. Problem Controller - Controla injeção de problemas"
echo ""
log "Timeline de problemas:"
echo "  09h-18h: Horário de pico (carga alta)"
echo "  11h: Ativação de queries lentas ⚠️"
echo "  15h: Ativação de problemas de índices ⚠️"
echo "  17h: Ativação de alto CPU ⚠️"
echo "  00h: Reset de todos os problemas ✓"
echo ""
warn "Pressione Ctrl+C para parar a simulação"
echo ""

python3 /app/credit_product_simulator.py
