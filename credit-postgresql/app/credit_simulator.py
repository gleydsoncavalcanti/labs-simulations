#!/usr/bin/env python3
"""
Simulador de Produto de Crédito — PostgreSQL
5 serviços concorrentes com Datadog APM + DBM Propagation.
"""

import os
import time
import random
import threading
import psycopg2
from psycopg2 import sql
from ddtrace import tracer, patch_all

# Instrumentação automática (psycopg2 + DBM Propagation)
patch_all()

# Configuração via variáveis de ambiente
DB_CONFIG = {
    "host": os.getenv("PGHOST", "postgres-credit"),
    "port": int(os.getenv("PGPORT", 5432)),
    "dbname": os.getenv("PGDATABASE", "creditdb"),
    "user": os.getenv("PGUSER", "app_user"),
    "password": os.getenv("PGPASSWORD", "AppUser123"),
}


def get_connection():
    """Cria conexão com PostgreSQL."""
    return psycopg2.connect(**DB_CONFIG)


def wait_for_db(max_retries=30, delay=2):
    """Aguarda o PostgreSQL ficar disponível."""
    for i in range(max_retries):
        try:
            conn = get_connection()
            conn.close()
            print("✅ PostgreSQL disponível!")
            return True
        except Exception as e:
            print(f"⏳ Aguardando PostgreSQL... ({i+1}/{max_retries}): {e}")
            time.sleep(delay)
    print("❌ PostgreSQL não disponível após timeout")
    return False


# ═══════════════════════════════════════════════════════════
# Serviço 1: Criação de Propostas
# ═══════════════════════════════════════════════════════════
@tracer.wrap(service="credit-product-pg", resource="proposal.create")
def proposal_creation():
    """Cria novas propostas de crédito."""
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    customer_id = random.randint(1, 10000)
    amount = round(random.uniform(1000, 50000), 2)
    installments = random.choice([12, 24, 36, 48])
    proposal_type = random.choice(["PERSONAL", "PAYROLL", "VEHICLE", "HOME_EQUITY"])
    risk_score = random.randint(300, 900)

    cur.execute("""
        INSERT INTO credit_proposals
            (customer_id, requested_amount, installment_count, status, proposal_type)
        VALUES (%s, %s, %s, 'PENDING', %s)
        RETURNING proposal_id
    """, (customer_id, amount, installments, proposal_type))

    proposal_id = cur.fetchone()[0]

    # Audit log
    cur.execute("""
        INSERT INTO audit_log (entity_type, entity_id, action, user_service)
        VALUES ('PROPOSAL', %s, 'CREATE', 'proposal-service')
    """, (proposal_id,))

    cur.close()
    conn.close()
    return proposal_id


# ═══════════════════════════════════════════════════════════
# Serviço 2: Aprovação de Propostas
# ═══════════════════════════════════════════════════════════
@tracer.wrap(service="credit-product-pg", resource="proposal.approve")
def proposal_approval():
    """Processa e aprova/rejeita propostas pendentes."""
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    # Busca proposta pendente
    cur.execute("""
        SELECT proposal_id, requested_amount, customer_id
        FROM credit_proposals
        WHERE status = 'PENDING'
        ORDER BY created_at ASC
        LIMIT 1
    """)

    row = cur.fetchone()
    if not row:
        cur.close()
        conn.close()
        return None

    proposal_id, amount, customer_id = row

    # Busca score do cliente
    cur.execute("SELECT credit_score FROM customers WHERE customer_id = %s", (customer_id,))
    score_row = cur.fetchone()
    score = score_row[0] if score_row else 500

    # Lógica de aprovação
    if score < 400:
        status = "REJECTED"
        approved = None
    elif score < 600:
        status = "APPROVED"
        approved = round(float(amount) * 0.8, 2)
    else:
        status = "APPROVED"
        approved = float(amount)

    cur.execute("""
        UPDATE credit_proposals
        SET status = %s,
            approved_amount = %s,
            analyzed_at = NOW(),
            analyzed_by = 'approval-service',
            updated_at = NOW()
        WHERE proposal_id = %s
    """, (status, approved, proposal_id))

    # Registra análise
    cur.execute("""
        INSERT INTO credit_analysis
            (proposal_id, analysis_type, score, risk_level, recommendation, processing_time_ms)
        VALUES (%s, 'AUTO', %s, %s, %s, %s)
    """, (
        proposal_id,
        score,
        "LOW" if score > 700 else "MEDIUM" if score > 500 else "HIGH",
        status,
        random.randint(50, 500)
    ))

    cur.close()
    conn.close()
    return proposal_id


# ═══════════════════════════════════════════════════════════
# Serviço 3: Consulta de Cliente
# ═══════════════════════════════════════════════════════════
@tracer.wrap(service="credit-product-pg", resource="customer.lookup")
def customer_lookup():
    """Consulta histórico de crédito do cliente."""
    conn = get_connection()
    cur = conn.cursor()

    cpf = str(random.randint(1, 10000)).zfill(11)

    cur.execute("""
        SELECT
            c.customer_id, c.full_name, c.cpf, c.email, c.credit_score,
            COUNT(p.proposal_id) AS total_proposals,
            SUM(CASE WHEN p.status = 'APPROVED' THEN 1 ELSE 0 END) AS approved_count,
            COALESCE(SUM(CASE WHEN p.status = 'APPROVED' THEN p.approved_amount ELSE 0 END), 0) AS total_credit
        FROM customers c
        LEFT JOIN credit_proposals p ON c.customer_id = p.customer_id
        WHERE c.cpf = %s
        GROUP BY c.customer_id, c.full_name, c.cpf, c.email, c.credit_score
    """, (cpf,))

    result = cur.fetchone()
    cur.close()
    conn.close()
    return result


# ═══════════════════════════════════════════════════════════
# Serviço 4: Análise de Risco
# ═══════════════════════════════════════════════════════════
@tracer.wrap(service="credit-product-pg", resource="risk.analysis")
def risk_analysis():
    """Análise de distribuição de risco das propostas."""
    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT
            proposal_type,
            status,
            COUNT(*) AS proposal_count,
            ROUND(AVG(ca.score)::numeric, 0) AS avg_risk_score,
            ROUND(AVG(cp.requested_amount)::numeric, 2) AS avg_amount,
            COALESCE(SUM(CASE WHEN cp.status = 'APPROVED' THEN cp.approved_amount ELSE 0 END), 0) AS total_approved
        FROM credit_proposals cp
        LEFT JOIN credit_analysis ca ON ca.proposal_id = cp.proposal_id
        WHERE cp.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY proposal_type, cp.status
        ORDER BY proposal_type, cp.status
    """)

    results = cur.fetchall()
    cur.close()
    conn.close()
    return results


# ═══════════════════════════════════════════════════════════
# Serviço 5: Performance por Produto
# ═══════════════════════════════════════════════════════════
@tracer.wrap(service="credit-product-pg", resource="service.performance")
def service_performance():
    """Relatório de performance por tipo de produto."""
    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT
            cp.proposal_type,
            COUNT(cp.proposal_id) AS total_proposals,
            COUNT(CASE WHEN cp.status = 'APPROVED' THEN 1 END) AS approved_count,
            ROUND(
                COUNT(CASE WHEN cp.status = 'APPROVED' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2
            ) AS approval_rate,
            ROUND(AVG(cp.requested_amount)::numeric, 2) AS avg_requested,
            ROUND(AVG(cp.approved_amount)::numeric, 2) AS avg_approved,
            ROUND(AVG(ca.processing_time_ms)::numeric, 0) AS avg_processing_ms
        FROM credit_proposals cp
        LEFT JOIN credit_analysis ca ON ca.proposal_id = cp.proposal_id
        GROUP BY cp.proposal_type
        ORDER BY approval_rate DESC
    """)

    results = cur.fetchall()
    cur.close()
    conn.close()
    return results


# ═══════════════════════════════════════════════════════════
# Workers (threads)
# ═══════════════════════════════════════════════════════════
def run_service(name, func, interval_range):
    """Loop contínuo para um serviço."""
    print(f"  🔄 [{name}] iniciado (intervalo: {interval_range}s)")
    while True:
        try:
            result = func()
            status = "✓" if result else "○"
            print(f"  {status} [{name}] executado")
        except Exception as e:
            print(f"  ✗ [{name}] erro: {e}")
        time.sleep(random.uniform(*interval_range))


def main():
    print("=" * 60)
    print("🐘 Credit Product Simulator — PostgreSQL")
    print("=" * 60)
    print(f"  Host: {DB_CONFIG['host']}:{DB_CONFIG['port']}")
    print(f"  Database: {DB_CONFIG['dbname']}")
    print(f"  User: {DB_CONFIG['user']}")
    print(f"  DBM Propagation: ✅ ATIVO (psycopg2)")
    print("=" * 60)

    # Aguarda banco
    if not wait_for_db():
        return

    # Aguarda Datadog Agent
    print("⏳ Aguardando 10s para Datadog Agent...")
    time.sleep(10)

    # Inicia serviços em threads
    services = [
        ("Proposal Creation",   proposal_creation,   (4, 8)),    # ~10/min
        ("Proposal Approval",   proposal_approval,    (3, 5)),    # ~15/min
        ("Customer Lookup",     customer_lookup,      (0.8, 1.5)),# ~50/min
        ("Risk Analysis",       risk_analysis,        (10, 15)),  # ~5/min
        ("Service Performance", service_performance,  (15, 25)),  # ~3/min
    ]

    print("\n🚀 Iniciando serviços:")
    threads = []
    for name, func, interval in services:
        t = threading.Thread(target=run_service, args=(name, func, interval), daemon=True)
        t.start()
        threads.append(t)

    print(f"\n✅ {len(threads)} serviços rodando. Ctrl+C para parar.\n")

    # Mantém main thread viva
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        print("\n🛑 Parando simulação...")


if __name__ == "__main__":
    main()
