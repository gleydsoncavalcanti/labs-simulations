# 🎮 Guia da Simulação — PostgreSQL Credit

## 📋 Visão Geral

Este lab implementa um cenário realista de produto de crédito no PostgreSQL 15, com dados volumosos e queries complexas.

**Destaque:** Suporte a **DBM Propagation** — link automático entre APM traces e DBM query samples.

---

## 🗄️ Estrutura do Database

### Database: creditdb

| Tabela | Registros | Descrição |
|--------|-----------|-----------|
| `customers` | 10.000 | Clientes (CPF, score, renda) |
| `credit_proposals` | 50.000+ | Propostas de crédito (crescente) |
| `credit_analysis` | ~40.000 | Análises automáticas/manuais |
| `credit_contracts` | Crescente | Contratos gerados |
| `installments` | Crescente | Parcelas de pagamento |
| `credit_transactions` | Crescente | Desembolsos e pagamentos |
| `audit_log` | Crescente | Auditoria de operações |

---

## 🎯 Serviços Simulados

### 1. Proposal Creation
- **Operação:** INSERT nova proposta + audit log
- **Taxa:** ~10/min
- **Latência:** ~40ms
- **Wait Events:** LWLock:WALWrite

### 2. Proposal Approval
- **Operação:** UPDATE status + INSERT análise
- **Taxa:** ~15/min
- **Latência:** ~60ms
- **Wait Events:** Lock:transactionid

### 3. Customer Lookup
- **Operação:** SELECT + JOIN + GROUP BY
- **Taxa:** ~50/min
- **Latência:** ~100ms
- **Wait Events:** LWLock:BufferContent, IO:DataFileRead

### 4. Risk Analysis
- **Operação:** Agregações complexas com GROUP BY
- **Taxa:** ~5/min
- **Latência:** ~300ms
- **Wait Events:** IO:DataFileRead (scan de muitas páginas)

### 5. Service Performance
- **Operação:** JOIN + múltiplas agregações
- **Taxa:** ~3/min
- **Latência:** ~180ms
- **Wait Events:** LWLock:BufferContent

---

## ✅ DBM Propagation

### Como funciona

1. A app usa `psycopg2` com `ddtrace`
2. O ddtrace injeta automaticamente **SQL comments** com traceparent:
   ```sql
   /*dddbs='creditdb',ddps='credit-product-pg',
     ddtag='env:lab',traceparent='00-abc123-def456-01'*/
   SELECT * FROM customers WHERE cpf = $1
   ```
3. O Datadog Agent captura o sample com trace ID
4. Link bidirecional APM ↔ DBM

### Resultado

- **No APM:** Click em query SQL → abre DBM Query Sample
- **No DBM:** Click em "View Trace" → abre APM Trace
- Correlação completa de latência

### vs SQL Server (pyodbc)

| Feature | PostgreSQL (psycopg2) | SQL Server (pyodbc) |
|---------|----------------------|---------------------|
| DBM Propagation | ✅ Automático | ❌ Não suportado |
| SQL Comments | ✅ Injetados pelo ddtrace | ❌ Não |
| Trace ID nos samples | ✅ Sim | ❌ Não |
| Link APM ↔ DBM | ✅ Bidirecional | ❌ Manual |

---

## 📊 Métricas Esperadas

| Métrica | Valor |
|---------|-------|
| Queries/s | ~90 |
| Latência média | ~120ms |
| Cache hit ratio | 95-99% |
| Conexões ativas | 5-8 |
| Tabelas no cache | ~80% |

### Wait Events

| Wait Event | % | Causa |
|------------|---|-------|
| LWLock:BufferContent | 35% | Shared buffers |
| Lock:transactionid | 20% | UPDATE locks |
| IO:DataFileRead | 18% | Leitura de dados |
| LWLock:WALWrite | 15% | Write-Ahead Log |
| IO:DataFileWrite | 10% | Checkpoint |

---

## 🔧 Cenários de Incidentes

### Blocking
```bash
# Terminal 1
docker exec -it postgres-credit psql -U postgres -d creditdb -c "
BEGIN;
UPDATE credit_proposals SET status = 'ANALYZING' WHERE proposal_id = 1;
"
# Terminal 2 (vai bloquear)
docker exec -it postgres-credit psql -U postgres -d creditdb -c "
UPDATE credit_proposals SET status = 'APPROVED' WHERE proposal_id = 1;
"
# Liberar: Terminal 1 → COMMIT;
```

### Sequential Scan
```bash
docker exec -it postgres-credit psql -U postgres -d creditdb -f /sql/04_seq_scan.sql
```

### CPU Stress
```bash
docker exec -it postgres-credit psql -U postgres -d creditdb -f /sql/06_cpu_intensive.sql
```

---

## 📚 Arquivos

- `sql/00_setup.sql` — Schema + dados (10k clientes, 50k propostas)
- `sql/01_create_users.sql` — Usuários app_user e datadog
- `app/credit_simulator.py` — 5 serviços com psycopg2 + ddtrace
- `datadog-agent/conf.d/postgres.d/conf.yaml` — Config DBM
