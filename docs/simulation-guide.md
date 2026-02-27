# 🎮 Simulação SQL Server - Credit Product Database

## 📋 Visão Geral

Este lab implementa um **cenário realista de produto de crédito** no SQL Server, com dados volumosos e queries complexas para demonstrar os recursos do **Datadog Database Monitoring (DBM)**.

**Objetivo:** Criar um ambiente que gere métricas significativas e situações reais de performance para análise no DBM.

---

## 🏗️ Arquitetura do Cenário

### Componentes

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Compose                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────┐  │
│  │ SQL Server   │◄───┤ Python App   │◄───┤ Datadog  │  │
│  │ 2022         │    │ Simulator    │    │ Agent    │  │
│  │              │    │              │    │          │  │
│  │ Port: 1433   │    │ 5 Services   │    │ DBM ✓    │  │
│  │ DB: CreditDB │    │ APM ✓        │    │ APM ✓    │  │
│  └──────────────┘    └──────────────┘    └──────────┘  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Stack Tecnológica

| Componente | Tecnologia | Versão |
|------------|------------|--------|
| **Database** | SQL Server | 2022-latest |
| **Aplicação** | Python | 3.11-slim |
| **Driver SQL** | pyodbc | 5.0.1 |
| **APM** | ddtrace | 2.8.0+ |
| **Monitoring** | Datadog Agent | 7.x |

---

## 🗄️ Estrutura do Database

### Database: **CreditDB**

#### Tabelas Principais

##### 1. **Customers** (Clientes)
```sql
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY IDENTITY(1,1),
    Name NVARCHAR(100),
    Email NVARCHAR(100),
    CPF NVARCHAR(14),
    Phone NVARCHAR(20),
    CreatedAt DATETIME2 DEFAULT GETDATE()
);
```

**Volume:** 10.000 registros

**Índices:**
- ✅ PK_Customers (clustered) on CustomerID
- ✅ IX_Customers_CPF (non-clustered) on CPF

##### 2. **CreditServices** (Produtos de Crédito)
```sql
CREATE TABLE CreditServices (
    ServiceID INT PRIMARY KEY IDENTITY(1,1),
    ServiceName NVARCHAR(100),
    Description NVARCHAR(500),
    InterestRate DECIMAL(5,2),
    MaxAmount DECIMAL(18,2),
    MaxInstallments INT
);
```

**Volume:** 5 produtos
- Personal Loan (15% a.a., até R$ 50.000)
- Credit Card (180% a.a., até R$ 10.000)
- Payroll Loan (8% a.a., até R$ 30.000)
- Home Equity (10% a.a., até R$ 500.000)
- Vehicle Financing (12% a.a., até R$ 100.000)

##### 3. **CreditProposals** (Propostas de Crédito)
```sql
CREATE TABLE CreditProposals (
    ProposalID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT FOREIGN KEY REFERENCES Customers(CustomerID),
    ServiceID INT FOREIGN KEY REFERENCES CreditServices(ServiceID),
    RequestedAmount DECIMAL(18,2),
    Installments INT,
    Status NVARCHAR(20), -- 'Pending', 'Approved', 'Rejected', 'Cancelled'
    RequestDate DATETIME2 DEFAULT GETDATE(),
    ApprovalDate DATETIME2 NULL,
    RiskScore INT, -- 0-1000
    ApprovedAmount DECIMAL(18,2) NULL
);
```

**Volume:** 50.000+ registros

**Status Distribution:**
- Pending: ~40%
- Approved: ~35%
- Rejected: ~20%
- Cancelled: ~5%

**Índices:**
- ✅ PK_CreditProposals (clustered) on ProposalID
- ✅ IX_Proposals_CustomerID (non-clustered) on CustomerID
- ✅ IX_Proposals_Status_Date (non-clustered) on (Status, RequestDate)

---

## 🎯 Serviços Simulados

A aplicação Python executa **5 serviços** concorrentes, simulando operações reais:

### 1. **Proposal Creation Service** 📝
**Operação:** Criar novas propostas de crédito

**Query Principal:**
```sql
INSERT INTO CreditProposals 
(CustomerID, ServiceID, RequestedAmount, Installments, Status, RiskScore)
VALUES (?, ?, ?, ?, 'Pending', ?)
```

**Características:**
- Taxa: ~10 propostas/minuto
- Wait Events: WRITELOG (escrita no transaction log)
- APM Span: `credit.proposal.create`

**Visão no DBM:**
- Query Samples: INSERT statements
- Avg Duration: ~50ms
- Wait: WRITELOG (escrita de log)

---

### 2. **Proposal Approval Service** ✅
**Operação:** Processar e aprovar/rejeitar propostas pendentes

**Query Principal:**
```sql
UPDATE CreditProposals
SET Status = ?,
    ApprovalDate = GETDATE(),
    ApprovedAmount = ?
WHERE ProposalID = ? AND Status = 'Pending'
```

**Lógica de Negócio:**
- Risk Score < 300 → Rejected
- Risk Score 300-600 → Approved (80% do valor)
- Risk Score > 600 → Approved (100% do valor)

**Características:**
- Taxa: ~15 aprovações/minuto
- Wait Events: LCK_M_U (update locks)
- APM Span: `credit.proposal.approve`

**Visão no DBM:**
- Query Samples: UPDATE statements
- Avg Duration: ~80ms
- Wait: LCK_M_U (exclusive locks durante update)
- Logical Reads: 5-10 páginas

---

### 3. **Customer Lookup Service** 🔍
**Operação:** Consultar histórico de crédito do cliente

**Query Principal:**
```sql
SELECT 
    c.CustomerID, c.Name, c.CPF, c.Email,
    COUNT(p.ProposalID) AS TotalProposals,
    SUM(CASE WHEN p.Status = 'Approved' THEN 1 ELSE 0 END) AS ApprovedCount,
    SUM(CASE WHEN p.Status = 'Approved' THEN p.ApprovedAmount ELSE 0 END) AS TotalCredit
FROM Customers c
LEFT JOIN CreditProposals p ON c.CustomerID = p.CustomerID
WHERE c.CPF = ?
GROUP BY c.CustomerID, c.Name, c.CPF, c.Email
```

**Características:**
- Taxa: ~50 consultas/minuto
- Wait Events: PAGEIOLATCH_SH (leitura de páginas)
- APM Span: `credit.customer.lookup`

**Visão no DBM:**
- Query Samples: SELECT com JOIN e GROUP BY
- Avg Duration: ~120ms
- Wait: PAGEIOLATCH_SH (I/O reads)
- Logical Reads: 100-200 páginas
- Rows Examined: ~5.000 (scan na join)

---

### 4. **Risk Analysis Service** 📊
**Operação:** Analisar distribuição de risco das propostas

**Query Principal:**
```sql
SELECT 
    ServiceID,
    Status,
    COUNT(*) AS ProposalCount,
    AVG(RiskScore) AS AvgRiskScore,
    AVG(RequestedAmount) AS AvgAmount,
    SUM(CASE WHEN Status = 'Approved' THEN ApprovedAmount ELSE 0 END) AS TotalApproved
FROM CreditProposals
WHERE RequestDate >= DATEADD(DAY, -30, GETDATE())
GROUP BY ServiceID, Status
ORDER BY ServiceID, Status
```

**Características:**
- Taxa: ~5 análises/minuto
- Wait Events: CXPACKET (paralelismo)
- APM Span: `credit.risk.analysis`

**Visão no DBM:**
- Query Samples: SELECT com agregações complexas
- Avg Duration: ~350ms (mais lenta por ser analítica)
- Wait: CXPACKET (threads paralelas esperando)
- Logical Reads: 1.000+ páginas
- Parallel Plan: SIM (MAXDOP = 4)

---

### 5. **Service Performance Service** 📈
**Operação:** Relatório de performance por produto

**Query Principal:**
```sql
SELECT 
    s.ServiceID,
    s.ServiceName,
    COUNT(p.ProposalID) AS TotalProposals,
    COUNT(CASE WHEN p.Status = 'Approved' THEN 1 END) AS ApprovedCount,
    CAST(COUNT(CASE WHEN p.Status = 'Approved' THEN 1 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS ApprovalRate,
    AVG(p.RequestedAmount) AS AvgRequestedAmount,
    AVG(p.ApprovedAmount) AS AvgApprovedAmount
FROM CreditServices s
LEFT JOIN CreditProposals p ON s.ServiceID = p.ServiceID
GROUP BY s.ServiceID, s.ServiceName
ORDER BY ApprovalRate DESC
```

**Características:**
- Taxa: ~3 relatórios/minuto
- Wait Events: ASYNC_NETWORK_IO (cliente lento)
- APM Span: `credit.service.performance`

**Visão no DBM:**
- Query Samples: SELECT com múltiplas agregações
- Avg Duration: ~200ms
- Wait: ASYNC_NETWORK_IO (rede esperando cliente)
- Logical Reads: 500+ páginas

---

## 📊 Métricas Coletadas pelo DBM

### Query Metrics Globais

| Métrica | Valor Médio | Observação |
|---------|-------------|------------|
| **Total Queries/s** | ~83 queries/s | Soma de todos os serviços |
| **Avg Query Duration** | ~150ms | Média ponderada |
| **P95 Duration** | ~400ms | 95% das queries < 400ms |
| **Buffer Cache Hit Ratio** | 96-98% | Bom (> 90%) |
| **Page Life Expectancy** | 500-800s | Bom (> 300s) |
| **Lock Waits/s** | 2-5 waits/s | Normal para workload OLTP |
| **Deadlocks/s** | 0-0.1 deadlocks/s | Raro (boa modelagem) |

### Wait Statistics

**Top 5 Wait Types observados:**

1. **PAGEIOLATCH_SH** (40%)
   - Causa: Leitura de páginas do disco/cache
   - Queries: Customer Lookup, Risk Analysis
   - Normal em queries analíticas

2. **CXPACKET** (25%)
   - Causa: Paralelismo (threads esperando sincronização)
   - Queries: Risk Analysis (agregações complexas)
   - Normal em queries com GROUP BY

3. **WRITELOG** (15%)
   - Causa: Escrita no transaction log
   - Queries: Proposal Creation, Approval
   - Normal em INSERTs e UPDATEs

4. **LCK_M_U** (10%)
   - Causa: Locks exclusivos durante UPDATE
   - Queries: Proposal Approval
   - Normal em workload transacional

5. **ASYNC_NETWORK_IO** (8%)
   - Causa: Cliente lento consumindo resultados
   - Queries: Service Performance (retorna muitos dados)
   - Pode indicar rede lenta ou cliente sobrecarregado

---

## 🔍 Visualização no Datadog DBM

### 1. Database List
**URL:** https://stone-tech.datadoghq.com/databases

**Visão:**
```
┌────────────────────────────────────────────────────────┐
│ Host: sqlserver-credit                                 │
├────────────────────────────────────────────────────────┤
│ Queries/s: 83                                          │
│ Average Duration: 150ms                                │
│ Connections (Load): 5-8 connections                    │
│ % Blocked: 0-2% (baixo)                               │
│ By Wait Group: [PAGEIOLATCH_SH: 40%] [CXPACKET: 25%] │
└────────────────────────────────────────────────────────┘
```

### 2. Summary (Overview)
**Ao clicar no host sqlserver-credit:**

**Wait Types Graph (Temporal):**
- Stacked area chart mostrando distribuição ao longo do tempo
- Cores identificam cada wait type
- Picos em PAGEIOLATCH_SH durante queries analíticas
- CXPACKET constante durante Risk Analysis

**CPU Utilization:**
- User CPU: 15-30% (queries)
- System CPU: 5-10% (SQL Server overhead)

**Query Throughput:**
- 5 linhas representando os 5 serviços
- Customer Lookup tem maior volume

**Average Query Duration:**
- Risk Analysis é a mais lenta (~350ms)
- Proposal Creation é a mais rápida (~50ms)

### 3. Queries Tab
**Top 5 Queries por Total Duration:**

```
┌──────────────────────────────────────────────────────────────┐
│ 1. Risk Analysis Query                                       │
│    Avg: 350ms | Count: 5/min | Total: 105s/hr              │
│    Wait: CXPACKET (60%), PAGEIOLATCH_SH (30%)               │
│    Rows Examined: 50,000 | Rows Returned: 25                │
├──────────────────────────────────────────────────────────────┤
│ 2. Service Performance Query                                 │
│    Avg: 200ms | Count: 3/min | Total: 36s/hr               │
│    Wait: ASYNC_NETWORK_IO (50%), PAGEIOLATCH_SH (40%)       │
│    Rows Examined: 10,000 | Rows Returned: 5                 │
├──────────────────────────────────────────────────────────────┤
│ 3. Customer Lookup Query                                     │
│    Avg: 120ms | Count: 50/min | Total: 360s/hr             │
│    Wait: PAGEIOLATCH_SH (70%), LCK_M_S (20%)                │
│    Rows Examined: 5,000 | Rows Returned: 1                  │
├──────────────────────────────────────────────────────────────┤
│ 4. Proposal Approval Query                                   │
│    Avg: 80ms | Count: 15/min | Total: 72s/hr               │
│    Wait: LCK_M_U (60%), WRITELOG (30%)                      │
│    Rows Examined: 1 | Rows Returned: 0 (UPDATE)            │
├──────────────────────────────────────────────────────────────┤
│ 5. Proposal Creation Query                                   │
│    Avg: 50ms | Count: 10/min | Total: 30s/hr               │
│    Wait: WRITELOG (80%), LCK_M_IX (15%)                     │
│    Rows Examined: 0 | Rows Returned: 0 (INSERT)            │
└──────────────────────────────────────────────────────────────┘
```

### 4. Query Samples
**Exemplo de sample capturado (Risk Analysis):**

```yaml
Sample ID: abc123-def456
Timestamp: 2026-02-27 10:15:32
Duration: 385ms
Wait Event: CXPACKET
Wait Time: 230ms (60% do tempo total)
CPU Time: 120ms
Logical Reads: 1,245 pages
Physical Reads: 0 (tudo em cache)
Rows Examined: 50,234
Rows Returned: 25
Query Plan Hash: 0x7B4A3F2E
Service: credit-risk-analysis
Trace ID: 1234567890abcdef  ← Link para APM
```

### 5. Explain Plans
**Plano visual capturado:**

```
┌─────────────────────────────────────────────────────┐
│ Risk Analysis Query - Execution Plan                │
├─────────────────────────────────────────────────────┤
│                                                      │
│  SELECT (0%)                                        │
│   └─ Sort (ORDER BY) (5%)                          │
│       └─ Stream Aggregate (GROUP BY) (10%)         │
│           └─ Parallelism (Gather Streams) (15%)    │ ← CXPACKET aqui!
│               └─ Hash Match (Inner Join) (25%)     │
│                   ├─ Index Scan: CreditServices (5%)│
│                   └─ Parallelism (Distribute Streams) (10%)│
│                       └─ Clustered Index Scan:     │
│                           CreditProposals (30%)     │ ← Maior custo
│                           Filter: RequestDate >= ?  │
│                           Rows: 50,000 → 5,000     │
│                                                      │
└─────────────────────────────────────────────────────┘

Warnings:
  ⚠️  No stats created: CreditProposals.RequestDate
  💡 Consider: CREATE NONCLUSTERED INDEX IX_Proposals_RequestDate
               ON CreditProposals(RequestDate)
```

### 6. Recommendations
**Sugestões geradas automaticamente:**

```
┌────────────────────────────────────────────────────────┐
│ 1. Missing Index on CreditProposals.RequestDate       │
├────────────────────────────────────────────────────────┤
│ Impact: -45% duration on Risk Analysis Query          │
│ Benefit: Reduces Clustered Index Scan to Index Seek   │
│                                                        │
│ SQL:                                                   │
│ CREATE NONCLUSTERED INDEX IX_Proposals_RequestDate    │
│ ON CreditProposals(RequestDate)                       │
│ INCLUDE (ServiceID, Status, RiskScore,                │
│          RequestedAmount, ApprovedAmount)             │
│ WITH (ONLINE = ON, MAXDOP = 4)                        │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│ 2. Consider Reducing MAXDOP for Simple Queries        │
├────────────────────────────────────────────────────────┤
│ Observation: High CXPACKET waits (25% of total)       │
│ Cause: Queries using parallelism unnecessarily        │
│                                                        │
│ Suggestion:                                            │
│ - Keep MAXDOP = 4 for complex queries (Risk Analysis) │
│ - Use OPTION (MAXDOP 1) for simple queries            │
│                                                        │
│ Example:                                               │
│ SELECT * FROM Customers WHERE CPF = ?                  │
│ OPTION (MAXDOP 1)  ← Evita overhead de paralelismo    │
└────────────────────────────────────────────────────────┘
```

---

## 🔗 Correlação APM ↔ DBM

### ⚠️ Limitação Importante

**pyodbc NÃO suporta DBM Propagation Mode**

O que isso significa:
- ✅ APM traces são coletados normalmente
- ✅ DBM query samples são coletados normalmente
- ❌ **Não há link automático entre trace e query**
- ❌ SQL comments não são injetados automaticamente

### Visão no APM (sem correlação automática)

**APM Service Map:**
```
credit-product-api
  ├─ POST /api/proposal/create (120ms)
  │   ├─ credit.proposal.create (100ms)
  │   │   └─ sqlserver query (80ms)  ← Sem link para DBM!
  │   │       Query: INSERT INTO CreditProposals...
  │   │       Rows: 1
  │   └─ HTTP response (20ms)
```

**DBM Query Sample (separado):**
```yaml
Query: INSERT INTO CreditProposals (CustomerID, ServiceID...)
Duration: 78ms
Wait: WRITELOG
Service: credit-product
Trace ID: null  ← Sem correlação!
```

### 📊 Comparação com PostgreSQL

No lab também há um cenário PostgreSQL com **DBM Propagation ativo**:

| Feature | SQL Server (pyodbc) | PostgreSQL (psycopg2) |
|---------|---------------------|------------------------|
| APM Traces | ✅ Sim | ✅ Sim |
| DBM Query Samples | ✅ Sim | ✅ Sim |
| DBM Propagation | ❌ Não suportado | ✅ Sim (DD_DBM_PROPAGATION_MODE=full) |
| SQL Comments | ❌ Não | ✅ Sim (traceparent injetado) |
| Trace ID em samples | ❌ Não | ✅ Sim (click → APM) |
| Query em trace | ⚠️ Manual | ✅ Automático (click → DBM) |

---

## 📈 Casos de Uso - O que Analisar

### 1. Identificar Query Mais Lenta
```
1. Databases → sqlserver-credit
2. Queries → Ordene por "Avg Duration"
3. Resultado: Risk Analysis Query (350ms)
4. Click → Veja Explain Plan
5. Diagnóstico: Clustered Index Scan (50k rows)
6. Recommendations → Missing Index sugerido
```

### 2. Investigar Wait Types Dominantes
```
1. Databases → sqlserver-credit
2. Summary → Veja gráfico de Wait Types
3. Observação: PAGEIOLATCH_SH (40%)
4. Interpretação: Muita leitura de disco/cache
5. Queries → Filtre queries com PAGEIOLATCH_SH
6. Resultado: Customer Lookup + Risk Analysis
7. Solução: Adicionar índices ou aumentar memória
```

### 3. Analisar Throughput por Serviço
```
1. Databases → sqlserver-credit
2. Summary → Query Throughput graph
3. Observação: Customer Lookup tem maior volume
4. Queries → Busque "SELECT...FROM Customers"
5. Métricas: 50 queries/min, 120ms avg
6. Decisão: Query é rápida, volume é esperado
```

### 4. Detectar Blocking e Locks
```
1. Databases → sqlserver-credit
2. Menu lateral → Blocking Queries
3. Resultado: Nenhum blocker ativo (boa modelagem!)
4. Active Connections → Veja conexões atuais
5. Observação: 5-8 conexões, todas ativas
```

### 5. Validar Performance de INSERTs
```
1. Databases → sqlserver-credit
2. Queries → Busque "INSERT INTO CreditProposals"
3. Métricas: 50ms avg, 10/min
4. Wait: WRITELOG (80%)
5. Diagnóstico: Normal, escrita de log é esperada
6. Validação: Performance OK para OLTP
```

---

## 🎯 Conclusão

### O que este Lab Demonstra

✅ **Cenário Realista**
- Database de produto de crédito com 60k+ registros
- 5 serviços executando operações reais
- Mix de queries OLTP (INSERT/UPDATE) e analíticas (SELECT com GROUP BY)

✅ **Métricas Significativas**
- 83 queries/s de throughput
- 150ms de latência média
- Distribuição real de wait types
- Buffer cache e PLE saudáveis

✅ **Recursos do DBM Demonstrados**
- Query Metrics: Agregação global
- Query Samples: Execuções individuais
- Explain Plans: Visualização de planos
- Recommendations: Sugestões AI de otimização
- Wait Statistics: Análise detalhada de waits

✅ **Análise Completa**
- Identificação de queries lentas
- Correlação de waits com queries
- Sugestões de índices
- Validação de configuração

### Próximos Passos

1. **Aplicar Recommendations:**
   - Criar índice sugerido (IX_Proposals_RequestDate)
   - Monitorar redução de duração

2. **Explorar Dashboard:**
   - Datadog: Importe `dashboard/datadog-dashboard-sqlserver.json`
   - Grafana: Dashboard pré-provisionado em http://localhost:3000

3. **Criar Alertas:**
   - Buffer Cache < 90%
   - Page Life Expectancy < 300s
   - Lock Waits > 100/s
   - Query Duration > 1s

---

## 📚 Arquivos Relacionados

- `sql/credit_product_setup.sql` — Schema e dados iniciais
- `app/credit_product_simulator.py` — Aplicação Python com 5 serviços
- `dashboard/datadog-dashboard-sqlserver.json` — Dashboard DPA-style (40 widgets)
- `docs/architecture.md` — Arquitetura detalhada do lab
