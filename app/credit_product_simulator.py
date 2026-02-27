#!/usr/bin/env python3
"""
Simulador Realista de Produto de Crédito
Simula múltiplos serviços fazendo requisições contínuas durante o dia,
com introdução gradual de problemas para análise via DBM.
"""

import time
import random
import pyodbc
import threading
from datetime import datetime, timedelta
from ddtrace import tracer, patch, config

# Configura DBM propagation antes do patch
config.dbapi_propagation_mode = 'full'
config._trace_sql_comments = True

# Habilita instrumentação automática
patch(pyodbc=True)

# Configuração do banco (usando usuário específico da aplicação)
CONN_STRING = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=sqlserver;"
    "DATABASE=SimDB;"
    "UID=app_user;"
    "PWD=AppUser123!@#;"
    "TrustServerCertificate=yes;"
)

# Controle de problemas (serão ativados em horários específicos)
PROBLEMS_ENABLED = {
    'slow_queries': False,
    'missing_indexes': False,
    'deadlocks': False,
    'high_cpu': False,
    'blocking': False
}

def get_connection():
    """Cria conexão com SQL Server"""
    return pyodbc.connect(CONN_STRING)

def add_dbm_comment(query, service_name, operation, span=None):
    """Adiciona comentário DBM para rastreamento end-to-end"""
    if span is None:
        span = tracer.current_span()
    
    if span and span.trace_id and span.span_id:
        trace_id = span.trace_id
        span_id = span.span_id
        comment = f"/*dddbs='credit-product',dde='lab',ddps='{service_name}',ddpv='1.0',ddtid='{trace_id}',ddsid='{span_id}'*/ "
        return comment + query.strip()
    return query.strip()

def log(service, message):
    """Log formatado com timestamp"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] [{service}] {message}")

# ═══════════════════════════════════════════════════════════════
#  SERVIÇO 1: CONSULTA DE PROPOSTAS (alta frequência)
# ═══════════════════════════════════════════════════════════════
@tracer.wrap(service="proposal-query-service", resource="list_proposals")
def list_proposals_by_status(status):
    """Lista propostas por status - Query mais comum do sistema"""
    with tracer.trace("database.query", service="proposal-query-service") as span:
        span.set_tag("proposal.status", status)
        span.set_tag("db.system", "sqlserver")
        
        conn = get_connection()
        cursor = conn.cursor()
        
        # Query otimizada com índice
        query = add_dbm_comment("""
            SELECT TOP 100 
                p.ProposalID, p.CustomerID, p.RequestedAmount, 
                p.Status, p.CreatedAt, c.FullName, c.CreditScore
            FROM CreditProposals p
            INNER JOIN Customers c ON p.CustomerID = c.CustomerID
            WHERE p.Status = ?
            ORDER BY p.CreatedAt DESC
        """, "proposal-query-service", "list_proposals", span)
        
        cursor.execute(query, (status,))
        rows = cursor.fetchall()
        
        span.set_tag("db.row_count", len(rows))
        cursor.close()
        conn.close()
        
        return rows

def proposal_query_service():
    """Serviço que consulta propostas constantemente"""
    service_name = "proposal-query-service"
    statuses = ['PENDING', 'ANALYZING', 'APPROVED', 'REJECTED']
    
    while True:
        try:
            status = random.choice(statuses)
            result = list_proposals_by_status(status)
            log(service_name, f"Consultou {len(result)} propostas com status {status}")
            time.sleep(random.uniform(0.5, 2))
        except Exception as e:
            log(service_name, f"ERRO: {e}")
            time.sleep(5)

# ═══════════════════════════════════════════════════════════════
#  SERVIÇO 2: CRIAÇÃO DE PROPOSTAS
# ═══════════════════════════════════════════════════════════════
@tracer.wrap(service="proposal-creation-service", resource="create_proposal")
def create_proposal(customer_id, amount, proposal_type):
    """Cria nova proposta de crédito"""
    with tracer.trace("database.insert", service="proposal-creation-service") as span:
        span.set_tag("customer_id", customer_id)
        span.set_tag("amount", amount)
        span.set_tag("proposal_type", proposal_type)
        
        conn = get_connection()
        cursor = conn.cursor()
        
        query = add_dbm_comment("""
            INSERT INTO CreditProposals 
            (CustomerID, RequestedAmount, Status, ProposalType, InterestRate, InstallmentCount)
            VALUES (?, ?, 'PENDING', ?, ?, 12)
        """, "proposal-creation-service", "create_proposal")
        
        cursor.execute(query, (customer_id, amount, proposal_type, random.uniform(2.5, 5.5)))
        conn.commit()
        
        # Log de auditoria
        audit_query = add_dbm_comment("""
            INSERT INTO AuditLog (EntityType, EntityID, Action, UserService)
            VALUES ('PROPOSAL', @@IDENTITY, 'CREATE', 'proposal-creation-service')
        """, "proposal-creation-service", "audit_log")
        cursor.execute(audit_query)
        conn.commit()
        
        cursor.close()
        conn.close()

def proposal_creation_service():
    """Serviço que cria propostas de crédito"""
    service_name = "proposal-creation-service"
    proposal_types = ['PERSONAL', 'PAYROLL', 'VEHICLE', 'HOME_EQUITY']
    
    while True:
        try:
            customer_id = random.randint(1, 10000)
            amount = random.randint(1000, 100000)
            proposal_type = random.choice(proposal_types)
            
            create_proposal(customer_id, amount, proposal_type)
            log(service_name, f"Criou proposta de R${amount} para cliente {customer_id}")
            time.sleep(random.uniform(2, 5))
        except Exception as e:
            log(service_name, f"ERRO: {e}")
            time.sleep(5)

# ═══════════════════════════════════════════════════════════════
#  SERVIÇO 3: ANÁLISE DE CRÉDITO (processamento pesado)
# ═══════════════════════════════════════════════════════════════
@tracer.wrap(service="credit-analysis-service", resource="analyze_credit")
def analyze_credit(proposal_id):
    """Analisa crédito de uma proposta"""
    with tracer.trace("database.transaction", service="credit-analysis-service") as span:
        span.set_tag("proposal_id", proposal_id)
        
        conn = get_connection()
        cursor = conn.cursor()
        
        # Busca dados do cliente e proposta
        query = add_dbm_comment("""
            SELECT p.ProposalID, p.CustomerID, p.RequestedAmount,
                   c.CreditScore, c.MonthlyIncome, c.CPF
            FROM CreditProposals p
            INNER JOIN Customers c ON p.CustomerID = c.CustomerID
            WHERE p.ProposalID = ? AND p.Status = 'PENDING'
        """, "credit-analysis-service", "fetch_proposal")
        
        cursor.execute(query, (proposal_id,))
        row = cursor.fetchone()
        
        if row:
            # Simula processamento
            time.sleep(random.uniform(0.1, 0.3))
            
            credit_score = row[3]
            score = random.randint(300, 800)
            risk = 'LOW' if score > 650 else ('MEDIUM' if score > 500 else 'HIGH')
            recommendation = 'APPROVE' if score > 600 else 'REJECT'
            
            # Insere análise
            insert_query = add_dbm_comment("""
                INSERT INTO CreditAnalysis 
                (ProposalID, AnalysisType, Score, RiskLevel, Recommendation, ProcessingTimeMs)
                VALUES (?, 'AUTO', ?, ?, ?, ?)
            """, "credit-analysis-service", "insert_analysis")
            cursor.execute(insert_query, (proposal_id, score, risk, recommendation, random.randint(100, 500)))
            
            # Atualiza status da proposta
            update_query = add_dbm_comment("""
                UPDATE CreditProposals 
                SET Status = ?, AnalyzedAt = GETDATE()
                WHERE ProposalID = ?
            """, "credit-analysis-service", "update_status")
            cursor.execute(update_query, (new_status, proposal_id))
            
            conn.commit()
            log("credit-analysis-service", f"Analisou proposta {proposal_id} - Resultado: {new_status}")
        
        cursor.close()
        conn.close()

def credit_analysis_service():
    """Serviço que analisa propostas pendentes"""
    service_name = "credit-analysis-service"
    
    while True:
        try:
            # Busca propostas pendentes
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute("""
                SELECT TOP 1 ProposalID 
                FROM CreditProposals 
                WHERE Status = 'PENDING'
                ORDER BY CreatedAt ASC
            """)
            row = cursor.fetchone()
            cursor.close()
            conn.close()
            
            if row:
                analyze_credit(row[0])
            else:
                log(service_name, "Nenhuma proposta pendente")
            
            time.sleep(random.uniform(1, 3))
        except Exception as e:
            log(service_name, f"ERRO: {e}")
            time.sleep(5)

# ═══════════════════════════════════════════════════════════════
#  SERVIÇO 4: CONSULTA DE CLIENTES (com possível problema)
# ═══════════════════════════════════════════════════════════════
@tracer.wrap(service="customer-query-service", resource="get_customer_history")
def get_customer_history(cpf):
    """Busca histórico completo do cliente"""
    with tracer.trace("database.query", service="customer-query-service") as span:
        span.set_tag("cpf", cpf)
        
        conn = get_connection()
        cursor = conn.cursor()
        
        # Query que pode ficar lenta se não tiver índice adequado
        if PROBLEMS_ENABLED['missing_indexes']:
            # Remove hint de índice, força table scan
            query = add_dbm_comment("""
                SELECT c.CustomerID, c.FullName, c.CreditScore,
                       COUNT(p.ProposalID) as total_proposals,
                       SUM(CASE WHEN p.Status = 'APPROVED' THEN 1 ELSE 0 END) as approved_count,
                       MAX(p.CreatedAt) as last_proposal
                FROM Customers c WITH (INDEX(0))
                LEFT JOIN CreditProposals p ON c.CustomerID = p.CustomerID
                WHERE c.CPF = ?
                GROUP BY c.CustomerID, c.FullName, c.CreditScore
            """, "customer-query-service", "customer_history_slow")
        else:
            query = add_dbm_comment("""
                SELECT c.CustomerID, c.FullName, c.CreditScore,
                       COUNT(p.ProposalID) as total_proposals,
                       SUM(CASE WHEN p.Status = 'APPROVED' THEN 1 ELSE 0 END) as approved_count,
                       MAX(p.CreatedAt) as last_proposal
                FROM Customers c
                LEFT JOIN CreditProposals p ON c.CustomerID = p.CustomerID
                WHERE c.CPF = ?
                GROUP BY c.CustomerID, c.FullName, c.CreditScore
            """, "customer-query-service", "customer_history")
        
        cursor.execute(query, (cpf,))
        row = cursor.fetchone()
        
        cursor.close()
        conn.close()
        
        return row

def customer_query_service():
    """Serviço que consulta dados de clientes"""
    service_name = "customer-query-service"
    
    while True:
        try:
            cpf = f"{random.randint(1, 10000):011d}"
            result = get_customer_history(cpf)
            if result:
                log(service_name, f"Consultou histórico do CPF {cpf}")
            time.sleep(random.uniform(1, 3))
        except Exception as e:
            log(service_name, f"ERRO: {e}")
            time.sleep(5)

# ═══════════════════════════════════════════════════════════════
#  SERVIÇO 5: RELATÓRIOS E ANALYTICS (queries pesadas)
# ═══════════════════════════════════════════════════════════════
@tracer.wrap(service="analytics-service", resource="daily_report")
def generate_daily_report():
    """Gera relatório diário - query pesada"""
    with tracer.trace("database.analytics", service="analytics-service") as span:
        conn = get_connection()
        cursor = conn.cursor()
        
        if PROBLEMS_ENABLED['slow_queries']:
            # Query sem otimização
            query = add_dbm_comment("""
                SELECT 
                    p.ProposalType,
                    p.Status,
                    COUNT(*) as total,
                    AVG(p.RequestedAmount) as avg_amount,
                    SUM(p.RequestedAmount) as total_amount,
                    AVG(c.CreditScore) as avg_credit_score,
                    COUNT(DISTINCT p.CustomerID) as unique_customers
                FROM CreditProposals p
                INNER JOIN Customers c ON p.CustomerID = c.CustomerID
                LEFT JOIN CreditAnalysis ca ON p.ProposalID = ca.ProposalID
                WHERE p.CreatedAt >= DATEADD(day, -1, GETDATE())
                GROUP BY p.ProposalType, p.Status
                ORDER BY total DESC
            """, "analytics-service", "daily_report_slow")
        else:
            query = add_dbm_comment("""
                SELECT 
                    p.ProposalType,
                    p.Status,
                    COUNT(*) as total,
                    AVG(p.RequestedAmount) as avg_amount
                FROM CreditProposals p
                WHERE p.CreatedAt >= DATEADD(day, -1, GETDATE())
                GROUP BY p.ProposalType, p.Status
            """, "analytics-service", "daily_report")
        
        cursor.execute(query)
        rows = cursor.fetchall()
        
        span.set_tag("report.row_count", len(rows))
        cursor.close()
        conn.close()
        
        return rows

def analytics_service():
    """Serviço de relatórios e analytics"""
    service_name = "analytics-service"
    
    while True:
        try:
            result = generate_daily_report()
            log(service_name, f"Gerou relatório com {len(result)} linhas")
            time.sleep(random.uniform(10, 20))  # Menos frequente
        except Exception as e:
            log(service_name, f"ERRO: {e}")
            time.sleep(15)

# ═══════════════════════════════════════════════════════════════
#  CONTROLE DE PROBLEMAS (Timeline)
# ═══════════════════════════════════════════════════════════════
def problem_controller():
    """Controla quando os problemas aparecem durante o dia"""
    log("PROBLEM-CONTROLLER", "Iniciando controle de problemas")
    
    # Simula um dia de trabalho acelerado (1 minuto real = 1 hora simulada)
    start_time = datetime.now()
    
    while True:
        elapsed_minutes = (datetime.now() - start_time).total_seconds() / 60
        simulated_hour = int(elapsed_minutes % 24)  # 0-23
        
        # Horário de pico (9h-12h e 14h-18h) - problemas começam
        if 9 <= simulated_hour < 12 or 14 <= simulated_hour < 18:
            if simulated_hour >= 11 and not PROBLEMS_ENABLED['slow_queries']:
                PROBLEMS_ENABLED['slow_queries'] = True
                log("PROBLEM-CONTROLLER", "⚠️  PROBLEMA ATIVADO: Queries lentas (11h)")
            
            if simulated_hour >= 15 and not PROBLEMS_ENABLED['missing_indexes']:
                PROBLEMS_ENABLED['missing_indexes'] = True
                log("PROBLEM-CONTROLLER", "⚠️  PROBLEMA ATIVADO: Índices ausentes (15h)")
            
            if simulated_hour >= 17 and not PROBLEMS_ENABLED['high_cpu']:
                PROBLEMS_ENABLED['high_cpu'] = True
                log("PROBLEM-CONTROLLER", "⚠️  PROBLEMA ATIVADO: Alto CPU (17h)")
        
        # Madrugada - reset dos problemas
        if simulated_hour == 0:
            PROBLEMS_ENABLED['slow_queries'] = False
            PROBLEMS_ENABLED['missing_indexes'] = False
            PROBLEMS_ENABLED['high_cpu'] = False
            log("PROBLEM-CONTROLLER", "✓ Reset de problemas (00h)")
        
        log("PROBLEM-CONTROLLER", f"Hora simulada: {simulated_hour:02d}:00 | Problemas ativos: {sum(PROBLEMS_ENABLED.values())}")
        time.sleep(60)  # Verifica a cada minuto

# ═══════════════════════════════════════════════════════════════
#  MAIN - Inicia todos os serviços
# ═══════════════════════════════════════════════════════════════
def main():
    print("=" * 70)
    print("  SIMULADOR DE PRODUTO DE CRÉDITO")
    print("  Múltiplos serviços com problemas graduais para análise DBM")
    print("=" * 70)
    
    # Inicia serviços em threads separadas
    services = [
        threading.Thread(target=proposal_query_service, daemon=True, name="ProposalQuery"),
        threading.Thread(target=proposal_creation_service, daemon=True, name="ProposalCreation"),
        threading.Thread(target=credit_analysis_service, daemon=True, name="CreditAnalysis"),
        threading.Thread(target=customer_query_service, daemon=True, name="CustomerQuery"),
        threading.Thread(target=analytics_service, daemon=True, name="Analytics"),
        threading.Thread(target=problem_controller, daemon=True, name="ProblemController"),
    ]
    
    for service in services:
        service.start()
        log("MAIN", f"Serviço {service.name} iniciado")
        time.sleep(0.5)
    
    log("MAIN", "✓ Todos os serviços estão rodando!")
    log("MAIN", "Pressione Ctrl+C para parar")
    
    # Mantém o programa rodando
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        log("MAIN", "Encerrando simulação...")

if __name__ == "__main__":
    main()
