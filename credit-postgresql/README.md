# 🐘 PostgreSQL — Credit Product Simulation

Simulação de um **sistema de análise de crédito** no PostgreSQL 15, com 5 serviços concorrentes gerando carga realista para análise de performance.

**Destaque:** Suporte completo a **DBM Propagation** (psycopg2) — link automático entre APM traces e queries no DBM.

---

## 🚀 Quick Start

```bash
# 1. Configure (opcional, necessário para Datadog)
cp .env.example .env
# Edite .env com sua DD_API_KEY

# 2. Suba tudo
docker compose up -d

# 3. Verifique
docker compose logs -f app
```

### Portas expostas

| Serviço | Porta | Acesso |
|---------|-------|--------|
| PostgreSQL | `5432` | `postgres / YourStrong!Passw0rd` |
| Prometheus | `9091` | http://localhost:9091 |
| Grafana | `3001` | http://localhost:3001 (`admin/admin`) |

> 💡 Portas diferentes do SQL Server para rodar ambas as simulações simultaneamente.

---

## 📋 O que é simulado

### Database: creditdb

**7 tabelas** simulam o ciclo de vida completo de uma proposta de crédito:

| Tabela | Registros | Descrição |
|--------|-----------|-----------|
| `customers` | 10.000 | Clientes com CPF, score, renda |
| `credit_proposals` | 50.000+ | Propostas (crescente) |
| `credit_analysis` | ~40.000 | Análises automáticas e manuais |
| `credit_contracts` | ~25.000 | Contratos ativos |
| `installments` | ~100.000 | Parcelas de pagamento |
| `credit_transactions` | Crescente | Desembolsos e pagamentos |
| `audit_log` | Crescente | Auditoria de operações |

### 5 Serviços Concorrentes

| # | Serviço | Operação | Taxa | Latência |
|---|---------|----------|------|----------|
| 1 | **Proposal Creation** | `INSERT` nova proposta | ~10/min | ~40ms |
| 2 | **Proposal Approval** | `UPDATE` status | ~15/min | ~60ms |
| 3 | **Customer Lookup** | `SELECT + JOIN` histórico | ~50/min | ~100ms |
| 4 | **Risk Analysis** | `GROUP BY` agregações | ~5/min | ~300ms |
| 5 | **Service Performance** | `JOIN + Aggregation` | ~3/min | ~180ms |

### Wait Events Gerados

| Wait Event | % | Causa |
|------------|---|-------|
| `LWLock:BufferContent` | 35% | Acesso concorrente ao shared buffer |
| `Lock:transactionid` | 20% | Locks transacionais em UPDATEs |
| `IO:DataFileRead` | 18% | Leitura de páginas do disco |
| `LWLock:WALWrite` | 15% | Escrita no WAL (Write-Ahead Log) |
| `IO:DataFileWrite` | 10% | Checkpoint / background writer |

---

## 🏗️ Arquitetura

```
┌──────────────────────────────────────────────────────────┐
│                    Docker Compose Network                  │
├──────────────────────────────────────────────────────────┤
│                                                            │
│  ┌──────────────┐    ┌──────────────┐    ┌────────────┐  │
│  │ PostgreSQL   │◄───┤ Python App   │    │ Datadog    │  │
│  │ 15-alpine    │    │ 5 Services   │    │ Agent 7    │  │
│  │ Port: 5432   │◄───┤ APM + Traces │    │ DBM + APM  │  │
│  └──────┬───────┘    └──────────────┘    └────────────┘  │
│         │                                                  │
│         │                                ┌────────────┐  │
│         └───────────────────────────────►│ Prometheus │  │
│              (postgres_exporter)          └─────┬──────┘  │
│                                                │          │
│                                          ┌─────▼──────┐  │
│                                          │  Grafana   │  │
│                                          └────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### Componentes

| Componente | Imagem | Função |
|------------|--------|--------|
| **PostgreSQL** | `postgres:15-alpine` | Banco de dados |
| **Python App** | `python:3.11-slim` + psycopg2 | Simulador de carga |
| **Datadog Agent** | `gcr.io/datadoghq/agent:7` | DBM + APM |
| **postgres_exporter** | `prometheuscommunity/postgres-exporter` | Métricas → Prometheus |
| **Prometheus** | `prom/prometheus` | Time-series DB |
| **Grafana** | `grafana/grafana` | Dashboards locais |

---

## ✅ DBM Propagation

Diferente do SQL Server (pyodbc), o PostgreSQL com **psycopg2** suporta **DBM Propagation** nativo:

```
APM Trace → SQL Comment injetado automaticamente → DBM Query Sample
```

### O que acontece

1. A aplicação faz uma query
2. O `ddtrace` injeta automaticamente um **SQL comment** com o trace ID:
   ```sql
   /*dddbs='creditdb',ddps='credit-product',
     ddtag='env:lab',traceparent='00-abc123...'*/ 
   SELECT * FROM customers WHERE cpf = $1
   ```
3. O Datadog Agent captura o sample com o **trace ID**
4. No DBM, cada query tem um link direto para o **APM Trace**

### Resultado no Datadog

- **APM →** Click em uma query SQL →  vai direto para o **DBM Query Sample**
- **DBM →** Click em "View Trace" → vai direto para o **APM Trace**
- Correlação completa: latência da app ↔ duração da query ↔ wait events

---

## 📂 Estrutura de Pastas

```
credit-postgresql/
├── README.md                   ← Este arquivo
├── .env.example                ← Variáveis de ambiente
├── docker-compose.yaml         ← Orquestração Docker
│
├── app/                        ← Simulador Python
│   ├── Dockerfile
│   ├── requirements.txt
│   └── credit_simulator.py     ← 5 serviços com psycopg2
│
├── sql/                        ← Scripts SQL
│   ├── 00_setup.sql            ← Schema + dados iniciais
│   ├── 01_create_users.sql     ← Usuários do banco
│   ├── 02_blocking.sql         ← Simulação de bloqueio
│   ├── 03_deadlock.sql         ← Simulação de deadlock
│   ├── 04_seq_scan.sql         ← Sequential scan
│   ├── 05_slow_query.sql       ← Query lenta proposital
│   ├── 06_cpu_intensive.sql    ← Carga CPU
│   └── analysis_queries.sql    ← Queries de diagnóstico
│
├── scripts/                    ← Shell scripts
│   ├── run_simulator.sh        ← Entrypoint do container
│   └── run_incidents.sh        ← Roda incidentes
│
├── dashboard/                  ← Dashboards prontos
│   └── grafana-postgresql.json ← Dashboard Grafana
│
├── datadog-agent/              ← Config do Datadog Agent
│   └── conf.d/postgres.d/conf.yaml
│
├── grafana/provisioning/       ← Auto-provisioning Grafana
│
├── docs/                       ← Documentação
│   ├── architecture.md
│   └── simulation-guide.md
│
└── prometheus.yaml             ← Prometheus config
```

---

## 🔧 Cenários de Incidentes SQL

| Script | Cenário | O que acontece |
|--------|---------|----------------|
| `02_blocking.sql` | **Blocking** | Transaction aberta + UPDATE concorrente |
| `03_deadlock.sql` | **Deadlock** | Duas transactions com locks cruzados |
| `04_seq_scan.sql` | **Seq Scan** | SELECT sem WHERE em tabela grande |
| `05_slow_query.sql` | **Slow Query** | Query com CROSS JOIN pesado |
| `06_cpu_intensive.sql` | **CPU Stress** | generate_series com cálculos pesados |

### Executar incidentes manualmente

```bash
# Sequential scan
docker exec -i postgres psql -U postgres -d creditdb -f /sql/04_seq_scan.sql

# CPU stress
docker exec -i postgres psql -U postgres -d creditdb -f /sql/06_cpu_intensive.sql
```

---

## 📊 Como monitorar

### Com Datadog (DBM)

1. Configure `DD_API_KEY` no `.env`
2. Acesse **Databases** no Datadog
3. Encontre o host `lab-postgresql-dbm`
4. Explore: Query Metrics, Samples, Explain Plans, Wait Events
5. **Bonus:** Click em qualquer query → "View Trace" (DBM Propagation!)

### Com Grafana (local)

1. Acesse http://localhost:3001
2. Login: `admin / admin`
3. Dashboard pré-provisionado: **PostgreSQL Performance**

### Com psql

```bash
docker exec -it postgres psql -U postgres -d creditdb
```

### Queries úteis de diagnóstico

```sql
-- Top queries por duração total
SELECT
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    rows,
    left(query, 80) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- Tabelas com mais seq scans (falta de índice)
SELECT
    schemaname, relname,
    seq_scan, seq_tup_read,
    idx_scan, idx_tup_fetch,
    n_live_tup
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_tup_read DESC
LIMIT 10;

-- Cache hit ratio
SELECT
    sum(heap_blks_hit) / nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0) AS ratio
FROM pg_statio_user_tables;

-- Locks ativos
SELECT
    pid, mode, granted,
    pg_blocking_pids(pid) AS blocked_by,
    left(query, 60) AS query
FROM pg_stat_activity
WHERE wait_event_type = 'Lock';
```

---

## 🛠️ Personalização

### Ajustar volume de dados

Edite `sql/00_setup.sql` — altere os loops de `generate_series()`.

### Ajustar taxa de queries

Edite `app/credit_simulator.py` — altere os intervalos de `time.sleep()`.

### Rodar sem Datadog

Remova os serviços `datadog-agent` e `app` no `docker-compose.yaml`.

---

## 🧹 Limpeza

```bash
docker compose down        # Parar
docker compose down -v     # Parar + remover dados
docker compose down -v --rmi all  # Remover tudo
```

---

## 📚 Documentação

- [Arquitetura detalhada](docs/architecture.md)
- [Guia completo da simulação](docs/simulation-guide.md)

---

**Stack:** PostgreSQL 15 · Python 3.11 · psycopg2 · Datadog Agent 7 · Prometheus · Grafana
