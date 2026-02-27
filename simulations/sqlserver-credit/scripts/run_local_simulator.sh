#!/bin/bash

# Script para executar o simulador localmente (fora do Docker)

echo "=========================================="
echo "  EXECUTANDO LOCALMENTE"
echo "=========================================="

# Verifica conexão com usuário app_user
if ! python3 -c "import pyodbc; conn=pyodbc.connect('DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost;DATABASE=SimDB;UID=app_user;PWD=AppUser!2024#Strong;TrustServerCertificate=yes;'); print('Conectado!')" 2>/dev/null; then
    echo "Erro: Não foi possível conectar ao SQL Server com usuário app_user"
    echo "Verifique se:"
    echo "  1. O container está rodando: docker ps"
    echo "  2. Os usuários foram criados"
    echo ""
    echo "Criando usuários agora..."
    
    # Copia e executa script de usuários
    docker cp 00_create_users.sql sqlserver:/tmp/00_create_users.sql
    docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -C -i /tmp/00_create_users.sql
    
    echo "Tentando conectar novamente..."
    sleep 2
fi

# Executa o setup (usando sa para DDL)
echo "Executando setup..."
docker cp credit_product_setup.sql sqlserver:/tmp/credit_product_setup.sql
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -C -i /tmp/credit_product_setup.sql

# Executa o simulador
echo "Iniciando simulador..."
cd ../app
python3 credit_product_simulator.py
