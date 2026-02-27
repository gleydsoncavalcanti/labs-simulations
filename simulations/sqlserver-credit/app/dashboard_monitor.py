#!/usr/bin/env python3
"""
Dashboard Visual - Monitor de Simulação
Mostra estatísticas em tempo real com interface visual
"""

import pyodbc
import time
import os
from datetime import datetime

CONN_STRING = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=sqlserver;"
    "DATABASE=SimDB;"
    "UID=app_user;"
    "PWD=AppUser123!@#;"
    "TrustServerCertificate=yes;"
)

def clear_screen():
    os.system('clear' if os.name != 'nt' else 'cls')

def get_stats():
    """Busca estatísticas do banco"""
    conn = pyodbc.connect(CONN_STRING)
    cursor = conn.cursor()
    
    # Contadores gerais
    cursor.execute("SELECT COUNT(*) FROM Customers")
    total_customers = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM CreditProposals")
    total_proposals = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM CreditProposals WHERE Status = 'PENDING'")
    pending = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM CreditProposals WHERE Status = 'APPROVED'")
    approved = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM CreditProposals WHERE Status = 'REJECTED'")
    rejected = cursor.fetchone()[0]
    
    # Últimas propostas
    cursor.execute("""
        SELECT TOP 5 ProposalID, Status, RequestedAmount, 
               FORMAT(CreatedAt, 'HH:mm:ss') as Time
        FROM CreditProposals 
        ORDER BY CreatedAt DESC
    """)
    last_proposals = cursor.fetchall()
    
    # Conexões ativas
    cursor.execute("""
        SELECT COUNT(*) FROM sys.dm_exec_sessions 
        WHERE is_user_process = 1
    """)
    active_connections = cursor.fetchone()[0]
    
    # Wait stats
    cursor.execute("""
        SELECT COUNT(*) FROM sys.dm_os_waiting_tasks
    """)
    waiting_tasks = cursor.fetchone()[0]
    
    cursor.close()
    conn.close()
    
    return {
        'total_customers': total_customers,
        'total_proposals': total_proposals,
        'pending': pending,
        'approved': approved,
        'rejected': rejected,
        'last_proposals': last_proposals,
        'active_connections': active_connections,
        'waiting_tasks': waiting_tasks
    }

def draw_bar(value, max_value, width=50):
    """Desenha barra de progresso"""
    filled = int((value / max_value) * width) if max_value > 0 else 0
    bar = '█' * filled + '░' * (width - filled)
    return f"{bar} {value}/{max_value}"

def main():
    print("Iniciando dashboard...")
    time.sleep(2)
    
    while True:
        try:
            stats = get_stats()
            
            clear_screen()
            
            # Header
            print("=" * 80)
            print(" 🏦 SIMULADOR DE PRODUTO DE CRÉDITO - DASHBOARD REAL-TIME".center(80))
            print("=" * 80)
            print(f" Atualizado em: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}".center(80))
            print("=" * 80)
            print()
            
            # Estatísticas principais
            print("📊 ESTATÍSTICAS GERAIS")
            print("-" * 80)
            print(f"  Total de Clientes:  {stats['total_customers']:,}")
            print(f"  Total de Propostas: {stats['total_proposals']:,}")
            print()
            
            # Status das propostas
            print("📋 STATUS DAS PROPOSTAS")
            print("-" * 80)
            total = stats['pending'] + stats['approved'] + stats['rejected']
            
            print(f"  Pendentes:  {draw_bar(stats['pending'], total, 40)}")
            print(f"  Aprovadas:  {draw_bar(stats['approved'], total, 40)}")
            print(f"  Rejeitadas: {draw_bar(stats['rejected'], total, 40)}")
            print()
            
            # Métricas do servidor
            print("⚡ MÉTRICAS DO SERVIDOR")
            print("-" * 80)
            print(f"  Conexões Ativas:  {stats['active_connections']}")
            print(f"  Tasks em Wait:    {stats['waiting_tasks']}")
            print()
            
            # Últimas atividades
            print("🔄 ÚLTIMAS 5 ATIVIDADES")
            print("-" * 80)
            print(f"  {'ID':<8} {'Status':<12} {'Valor':<15} {'Hora':<10}")
            print("  " + "-" * 76)
            for prop in stats['last_proposals']:
                print(f"  {prop[0]:<8} {prop[1]:<12} R$ {prop[2]:>10,.2f}  {prop[3]:<10}")
            print()
            
            # Taxa de aprovação
            if total > 0:
                approval_rate = (stats['approved'] / total) * 100
                rejection_rate = (stats['rejected'] / total) * 100
                pending_rate = (stats['pending'] / total) * 100
                
                print("📈 TAXAS")
                print("-" * 80)
                print(f"  Taxa de Aprovação: {approval_rate:>5.1f}%")
                print(f"  Taxa de Rejeição:  {rejection_rate:>5.1f}%")
                print(f"  Taxa Pendente:     {pending_rate:>5.1f}%")
            
            print()
            print("=" * 80)
            print(" Pressione Ctrl+C para sair | Atualizando a cada 3 segundos".center(80))
            print("=" * 80)
            
            time.sleep(3)
            
        except KeyboardInterrupt:
            print("\n\nEncerrando dashboard...")
            break
        except Exception as e:
            print(f"\nErro: {e}")
            print("Tentando reconectar em 5 segundos...")
            time.sleep(5)

if __name__ == "__main__":
    main()
