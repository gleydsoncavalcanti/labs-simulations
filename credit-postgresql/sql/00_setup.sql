-- =========================================================
-- SETUP: Credit Product Database - PostgreSQL
-- =========================================================

-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- ── Tabela de Clientes ──
CREATE TABLE IF NOT EXISTS customers (
    customer_id SERIAL PRIMARY KEY,
    cpf VARCHAR(11) NOT NULL UNIQUE,
    full_name VARCHAR(200) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(20),
    birth_date DATE,
    credit_score INT,
    monthly_income NUMERIC(12,2),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customers_cpf ON customers(cpf);
CREATE INDEX IF NOT EXISTS idx_customers_credit_score ON customers(credit_score);

-- ── Tabela de Propostas de Crédito ──
CREATE TABLE IF NOT EXISTS credit_proposals (
    proposal_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customers(customer_id),
    requested_amount NUMERIC(12,2) NOT NULL,
    approved_amount NUMERIC(12,2),
    interest_rate NUMERIC(5,2),
    installment_count INT,
    status VARCHAR(50) NOT NULL,  -- PENDING, ANALYZING, APPROVED, REJECTED, DISBURSED
    proposal_type VARCHAR(50),    -- PERSONAL, PAYROLL, VEHICLE, HOME_EQUITY
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    analyzed_at TIMESTAMPTZ,
    analyzed_by VARCHAR(100)
);

CREATE INDEX IF NOT EXISTS idx_proposals_status ON credit_proposals(status);
CREATE INDEX IF NOT EXISTS idx_proposals_customer_id ON credit_proposals(customer_id);
CREATE INDEX IF NOT EXISTS idx_proposals_created_at ON credit_proposals(created_at);
CREATE INDEX IF NOT EXISTS idx_proposals_status_created ON credit_proposals(status, created_at);

-- ── Tabela de Análise de Crédito ──
CREATE TABLE IF NOT EXISTS credit_analysis (
    analysis_id SERIAL PRIMARY KEY,
    proposal_id INT NOT NULL REFERENCES credit_proposals(proposal_id),
    analysis_type VARCHAR(50),    -- AUTO, MANUAL, FRAUD_CHECK, BUREAU_CHECK
    score INT,
    risk_level VARCHAR(20),       -- LOW, MEDIUM, HIGH, CRITICAL
    recommendation VARCHAR(50),   -- APPROVE, REJECT, MANUAL_REVIEW
    observations TEXT,
    processing_time_ms INT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_analysis_proposal_id ON credit_analysis(proposal_id);
CREATE INDEX IF NOT EXISTS idx_analysis_created_at ON credit_analysis(created_at);

-- ── Tabela de Contratos ──
CREATE TABLE IF NOT EXISTS credit_contracts (
    contract_id SERIAL PRIMARY KEY,
    proposal_id INT NOT NULL REFERENCES credit_proposals(proposal_id),
    contract_number VARCHAR(50) NOT NULL UNIQUE,
    principal_amount NUMERIC(12,2) NOT NULL,
    interest_rate NUMERIC(5,2) NOT NULL,
    installment_count INT NOT NULL,
    installment_value NUMERIC(12,2) NOT NULL,
    first_due_date DATE,
    status VARCHAR(50),           -- ACTIVE, PAID_OFF, DEFAULTED, RENEGOTIATED
    disbursed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_contracts_number ON credit_contracts(contract_number);
CREATE INDEX IF NOT EXISTS idx_contracts_status ON credit_contracts(status);

-- ── Tabela de Parcelas ──
CREATE TABLE IF NOT EXISTS installments (
    installment_id SERIAL PRIMARY KEY,
    contract_id INT NOT NULL REFERENCES credit_contracts(contract_id),
    installment_number INT NOT NULL,
    due_date DATE NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    paid_amount NUMERIC(12,2),
    paid_at TIMESTAMPTZ,
    status VARCHAR(50),           -- PENDING, PAID, OVERDUE, PARTIALLY_PAID
    days_overdue INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_installments_contract_id ON installments(contract_id);
CREATE INDEX IF NOT EXISTS idx_installments_due_date ON installments(due_date);
CREATE INDEX IF NOT EXISTS idx_installments_status ON installments(status);

-- ── Tabela de Transações ──
CREATE TABLE IF NOT EXISTS credit_transactions (
    transaction_id SERIAL PRIMARY KEY,
    contract_id INT,
    transaction_type VARCHAR(50), -- DISBURSEMENT, PAYMENT, FEE, ADJUSTMENT
    amount NUMERIC(12,2) NOT NULL,
    description TEXT,
    processed_by VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transactions_contract_id ON credit_transactions(contract_id);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON credit_transactions(transaction_type);

-- ── Tabela de Auditoria ──
CREATE TABLE IF NOT EXISTS audit_log (
    log_id BIGSERIAL PRIMARY KEY,
    entity_type VARCHAR(50),      -- PROPOSAL, CONTRACT, CUSTOMER
    entity_id INT,
    action VARCHAR(100),
    user_service VARCHAR(100),
    changes JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_log(created_at);

-- ══════════════════════════════════════════
-- Populando dados iniciais
-- ══════════════════════════════════════════

-- Clientes (10.000)
INSERT INTO customers (cpf, full_name, email, phone, birth_date, credit_score, monthly_income)
SELECT
    lpad(i::text, 11, '0'),
    'Cliente ' || i,
    'cliente' || i || '@example.com',
    '11' || lpad(i::text, 9, '0'),
    NOW() - ((20 + (i % 40)) * interval '1 year'),
    300 + (i % 600),
    1500 + (i % 15000)
FROM generate_series(1, 10000) AS i
ON CONFLICT (cpf) DO NOTHING;

-- Propostas (50.000)
INSERT INTO credit_proposals (customer_id, requested_amount, approved_amount, interest_rate, installment_count, status, proposal_type, created_at)
SELECT
    1 + (i % 10000),
    1000 + (i % 50000),
    CASE WHEN (i % 10) IN (2,4,5,6,7,8) THEN (1000 + (i % 50000)) * 0.9 ELSE NULL END,
    2.5 + (i % 5),
    12 * (1 + (i % 4)),
    CASE (i % 10)
        WHEN 0 THEN 'PENDING'
        WHEN 1 THEN 'ANALYZING'
        WHEN 2 THEN 'APPROVED'
        WHEN 3 THEN 'REJECTED'
        WHEN 4 THEN 'DISBURSED'
        ELSE 'APPROVED'
    END,
    CASE (i % 4)
        WHEN 0 THEN 'PERSONAL'
        WHEN 1 THEN 'PAYROLL'
        WHEN 2 THEN 'VEHICLE'
        ELSE 'HOME_EQUITY'
    END,
    NOW() - ((i % 43200) * interval '1 minute')
FROM generate_series(1, 50000) AS i;

-- Análises de crédito
INSERT INTO credit_analysis (proposal_id, analysis_type, score, risk_level, recommendation, processing_time_ms, created_at)
SELECT
    proposal_id,
    CASE (proposal_id % 4)
        WHEN 0 THEN 'AUTO'
        WHEN 1 THEN 'MANUAL'
        WHEN 2 THEN 'FRAUD_CHECK'
        ELSE 'BUREAU_CHECK'
    END,
    400 + (proposal_id % 400),
    CASE
        WHEN (proposal_id % 400) < 100 THEN 'CRITICAL'
        WHEN (proposal_id % 400) < 200 THEN 'HIGH'
        WHEN (proposal_id % 400) < 300 THEN 'MEDIUM'
        ELSE 'LOW'
    END,
    CASE
        WHEN (proposal_id % 400) < 150 THEN 'REJECT'
        WHEN (proposal_id % 400) < 200 THEN 'MANUAL_REVIEW'
        ELSE 'APPROVE'
    END,
    50 + (proposal_id % 2000),
    NOW() - ((proposal_id % 43200) * interval '1 minute')
FROM credit_proposals
WHERE status IN ('ANALYZING', 'APPROVED', 'REJECTED', 'DISBURSED');

-- Estatísticas
DO $$
DECLARE
    v_customers INT;
    v_proposals INT;
    v_analysis INT;
BEGIN
    SELECT COUNT(*) INTO v_customers FROM customers;
    SELECT COUNT(*) INTO v_proposals FROM credit_proposals;
    SELECT COUNT(*) INTO v_analysis FROM credit_analysis;
    RAISE NOTICE 'Setup completo! Customers: %, Proposals: %, Analysis: %', v_customers, v_proposals, v_analysis;
END $$;

-- Atualiza estatísticas das tabelas
ANALYZE customers;
ANALYZE credit_proposals;
ANALYZE credit_analysis;
