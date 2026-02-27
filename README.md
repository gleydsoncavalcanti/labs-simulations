# 🎮 Labs Simulations

Laboratórios de simulação de carga em bancos de dados para testes de **performance**, **monitoramento** e **troubleshooting** com ferramentas como **Datadog DBM**, **Grafana**, **Prometheus** e **OpenTelemetry**.

> ⚠️ Repositório público para fins educacionais. Não contém credenciais ou dados sensíveis.

---

## 📋 Simulações Disponíveis

| Simulação | Banco | Cenário | Queries/s | Status |
|-----------|-------|---------|-----------|--------|
| [credit-sql-server](credit-sql-server/) | SQL Server 2022 | Análise de crédito | ~83 q/s | ✅ Ativo |
| [credit-postgresql](credit-postgresql/) | PostgreSQL 15 | Análise de crédito | ~90 q/s | ✅ Ativo |

---

## 🚀 Quick Start

### Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/) e [Docker Compose](https://docs.docker.com/compose/install/)
- (Opcional) Conta no [Datadog](https://www.datadoghq.com/) para DBM/APM

### Rodar uma simulação

```bash
# 1. Clone
git clone https://github.com/gleydsoncavalcanti/labs-simulations.git
cd labs-simulations

# 2. Escolha uma simulação
cd credit-sql-server    # ou credit-postgresql

# 3. Configure (opcional, necessário para Datadog)
cp .env.example .env
# Edite .env com sua DD_API_KEY

# 4. Suba
docker compose up -d

# 5. Acompanhe
docker compose logs -f app
```

---

## 📊 Resumo das Simulações

### 🔷 [credit-sql-server](credit-sql-server/)

Sistema de análise de crédito no **SQL Server 2022** com pyodbc:

| Item | Detalhe |
|------|---------|
| **Tabelas** | 7 (Customers, CreditProposals, CreditAnalysis, Contracts, Installments, Transactions, AuditLog) |
| **Volume** | 10k clientes · 50k+ propostas · 60k+ registros |
| **Serviços** | 5 concorrentes (INSERT, UPDATE, SELECT+JOIN, GROUP BY, Aggregation) |
| **Throughput** | ~83 queries/s · latência média ~150ms |
| **Wait Types** | PAGEIOLATCH_SH (40%) · CXPACKET (25%) · WRITELOG (15%) |
| **Incidentes** | Blocking, Deadlocks, Full Scans, Slow Queries, CPU Stress |
| **DBM Propagation** | ❌ pyodbc não suporta |
| **Stack** | SQL Server 2022 · Python 3.11 · Datadog Agent 7 · OTel · Prometheus · Grafana |

### 🐘 [credit-postgresql](credit-postgresql/)

Sistema de análise de crédito no **PostgreSQL 15** com psycopg2:

| Item | Detalhe |
|------|---------|
| **Tabelas** | 7 (customers, credit_proposals, credit_analysis, contracts, installments, transactions, audit_log) |
| **Volume** | 10k clientes · 50k+ propostas · 60k+ registros |
| **Serviços** | 5 concorrentes (INSERT, UPDATE, SELECT+JOIN, GROUP BY, Aggregation) |
| **Throughput** | ~90 queries/s · latência média ~120ms |
| **Wait Events** | LWLock:BufferContent · Lock:transactionid · IO:DataFileRead |
| **Incidentes** | Blocking, Deadlocks, Seq Scans, Slow Queries, CPU Stress |
| **DBM Propagation** | ✅ psycopg2 suporta (traceparent injetado nos SQL comments) |
| **Stack** | PostgreSQL 15 · Python 3.11 · Datadog Agent 7 · OTel · Prometheus · Grafana |

### 🔀 Comparação

| Feature | SQL Server | PostgreSQL |
|---------|------------|------------|
| DBM Propagation | ❌ (pyodbc) | ✅ (psycopg2) |
| Trace ↔ Query link | Manual | Automático |
| Explain Plans | Estimated | Actual (auto_explain) |
| Wait classification | Wait Types | Wait Events |
| Parallel queries | CXPACKET/MAXDOP | Parallel Workers |
| Index recommendations | ✅ Missing indexes DMV | ✅ pg_stat_user_indexes |

---

## 🏗️ Estrutura do Repositório

```
labs-simulations/
├── README.md                          ← Este arquivo
├── LICENSE
├── .gitignore
│
├── credit-sql-server/                 ← SQL Server 2022
│   ├── README.md
│   ├── docker-compose.yaml
│   ├── .env.example
│   ├── app/                           ← Simulador Python (pyodbc)
│   ├── sql/                           ← Scripts SQL (T-SQL)
│   ├── scripts/                       ← Shell scripts
│   ├── dashboard/                     ← Dashboards Datadog + Grafana
│   ├── datadog-agent/                 ← Config Agent
│   ├── grafana/                       ← Provisioning
│   ├── docs/
│   ├── otel-config.yaml
│   └── prometheus.yaml
│
└── credit-postgresql/                 ← PostgreSQL 15
    ├── README.md
    ├── docker-compose.yaml
    ├── .env.example
    ├── app/                           ← Simulador Python (psycopg2)
    ├── sql/                           ← Scripts SQL (PL/pgSQL)
    ├── scripts/                       ← Shell scripts
    ├── dashboard/                     ← Dashboards Datadog + Grafana
    ├── datadog-agent/                 ← Config Agent
    ├── grafana/                       ← Provisioning
    ├── docs/
    └── prometheus.yaml
```

---

## 🎯 Casos de Uso

### 1. Avaliar ferramenta de monitoramento
Suba uma simulação e conecte sua ferramenta (Datadog, New Relic, Dynatrace, etc.) para ver queries, waits e explain plans reais.

### 2. Comparar SQL Server vs PostgreSQL
Rode as duas simulações lado a lado e compare comportamento de locks, waits, paralelismo e explain plans.

### 3. Testar DBM Propagation
Use `credit-postgresql` para ver o link automático APM ↔ DBM (trace ID nos SQL comments). Compare com `credit-sql-server` onde não há propagation.

### 4. Praticar troubleshooting
Execute os scripts de incidentes (blocking, deadlocks, full scans) e pratique identificação e resolução no DBM.

### 5. Performance tuning
Analise explain plans, identifique missing indexes, ajuste configurações e meça o impacto.

---

## 🤝 Contribuindo

Para adicionar uma nova simulação, crie um diretório na raiz com:

```
nome-da-simulacao/
├── README.md              ← Quick Start
├── docker-compose.yaml    ← docker compose up -d
└── ...
```

---

## 📄 Licença

[MIT](LICENSE)
