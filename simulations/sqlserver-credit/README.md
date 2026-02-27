# 🏦 SQL Server — Credit Product Simulation

Simulação de um **sistema de análise de crédito** no SQL Server 2022, com 5 serviços concorrentes gerando carga realista para análise de performance.

---

## 🚀 Quick Start

```bash
# 1. Configure (opcional, necessário para Datadog)
cp .env.example .env
# Edite .env com sua DD_API_KEY

# 2. Suba tudo
docker compose up -d

# 3. Verifique
docker logs -f app-with-apm
```

### Portas expostas

| Serviço | Porta | Acesso |
|---------|-------|--------|
| SQL Server | `1433` | `sa / YourStrong!Passw0rd` |
| Prometheus | `9090` | http://localhost:9090 |
| Grafana | `3000` | http://localhost:3000 (`admin/admin`) |

---

## 📋 O que é simulado

### Database: CreditDB (SimDB)

**7 tabelas** simulam o ciclo de vida completo de uma proposta de crédito:

| Tabela | Registros | Descrição |
|--------|-----------|-----------|
| `Customers` | 10.000 | Clientes com CPF, score, renda |
| `CreditProposals` | 50.000+ | Propostas (crescente) |
| `CreditAnalysis` | ~40.000 | Análises automáticas e manuais |
| `CreditContracts` | ~25.000 | Contratos ativos |
| `Installments` | ~100.000 | Parcelas de pagamento |
| `CreditTransactions` | Crescente | Desembolsos e pagamentos |
| `AuditLog` | Crescente | Auditoria de operações |

### 5 Serviços Concorrentes

| # | Serviço | Operação | Taxa | Latência |
|---|---------|----------|------|----------|
| 1 | **Proposal Creation** | `INSERT` nova proposta | ~10/min | ~50ms |
| 2 | **Proposal Approval** | `UPDATE` status | ~15/min | ~80ms |
| 3 | **Customer Lookup** | `SELECT + JOIN` histórico | ~50/min | ~120ms |
| 4 | **Risk Analysis** | `GROUP BY` agregações | ~5/min | ~350ms |
| 5 | **Service Performance** | `JOIN + Aggregation` | ~3/min | ~200ms |

### Wait Statistics Gerados

| Wait Type | % | Causa |
|-----------|---|-------|
| `PAGEIOLATCH_SH` | 40% | Leitura de páginas (I/O) |
| `CXPACKET` | 25% | Paralelismo em queries analíticas |
| `WRITELOG` | 15% | Escrita no transaction log |
| `LCK_M_U` | 10% | Locks em UPDATEs |
| `ASYNC_NETWORK_IO` | 8% | Network I/O |

---

## 🏗️ Arquitetura

```
┌──────────────────────────────────────────────────────────┐
│                    Docker Compose Network                  │
├──────────────────────────────────────────────────────────┤
│                                                            │
│  ┌──────────────┐    ┌──────────────┐    ┌────────────┐  │
│  │ SQL Server   │◄───┤ Python App   │    │ Datadog    │  │
│  │ 2022         │    │ 5 Services   │    │ Agent 7    │  │
│  │ Port: 1433   │◄───┤ APM + Traces │    │ DBM + APM  │  │
│  └──────┬───────┘    └──────────────┘    └────────────┘  │
│         │                                                  │
│         │            ┌──────────────┐    ┌────────────┐  │
│         └───────────►│ OTel Collect │───►│ Prometheus │  │
│                      └──────────────┘    └─────┬──────┘  │
│                                                │          │
│                                          ┌─────▼──────┐  │
│                                          │  Grafana   │  │
│                                          └────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### Componentes

| Componente | Imagem | Função |
|------------|--------|--------|
| **SQL Server** | `mcr.microsoft.com/mssql/server:2022-latest` | Banco de dados |
| **Python App** | `python:3.11-slim` + pyodbc | Simulador de carga |
| **Datadog Agent** | `gcr.io/datadoghq/agent:7` | DBM + APM |
| **OTel Collector** | `otel/opentelemetry-collector-contrib` | Métricas SQL → Prometheus |
| **Prometheus** | `prom/prometheus` | Time-series DB |
| **Grafana** | `grafana/grafana` | Dashboards locais |

---

## 📂 Estrutura de Pastas

```
sqlserver-credit/
├── docker-compose.yaml         ← Orquestração
├── .env.example                ← Variáveis de ambiente
│
├── app/                        ← Simulador Python
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── credit_product_simulator.py   ← 5 serviços + problemas graduais
│   └── stress_with_apm.py           ← Stress test com APM traces
│
├── sql/                        ← Scripts SQL
│   ├── 00_create_users.sql     ← Usuários do banco
│   ├── 01_setup.sql            ← Schema base (Orders, Inventory)
│   ├── credit_product_setup.sql← Schema de crédito (7 tabelas, 60k+ rows)
│   ├── 02_blocking_conn*.sql   ← Simulação de bloqueio
│   ├── 03_deadlock_session*.sql← Simulação de deadlock
│   ├── 04_full_scan.sql        ← Full table scan
│   ├── 05_slow_query.sql       ← Query lenta proposital
│   ├── 06_cpu_intensive.sql    ← Carga CPU
│   └── analysis_queries.sql    ← Queries úteis de diagnóstico
│
├── scripts/                    ← Shell scripts
│   ├── run_credit_simulator.sh ← Entrypoint do container
│   ├── run_simulations.sh      ← Roda incidentes SQL
│   └── stress_test.sh          ← Teste de stress
│
├── dashboard/                  ← Dashboards prontos
│   ├── datadog-dashboard-sqlserver.json  ← Dashboard DPA-style (40 widgets)
│   └── grafana-sqlserver-dbm.json        ← Dashboard Grafana
│
├── datadog-agent/              ← Config do Datadog Agent
│   └── conf.d/sqlserver.d/conf.yaml
│
├── grafana/provisioning/       ← Auto-provisioning Grafana
│
├── docs/                       ← Documentação
│   ├── architecture.md         ← Arquitetura detalhada
│   └── simulation-guide.md     ← Guia completo da simulação
│
├── otel-config.yaml            ← OpenTelemetry config
└── prometheus.yaml             ← Prometheus config
```

---

## 🔧 Cenários de Incidentes SQL

Além da carga contínua, scripts SQL simulam problemas específicos:

| Script | Cenário | O que acontece |
|--------|---------|----------------|
| `02_blocking_conn*.sql` | **Blocking** | Transaction aberta + UPDATE concorrente |
| `03_deadlock_session*.sql` | **Deadlock** | Duas sessions com locks cruzados |
| `04_full_scan.sql` | **Full Scan** | SELECT sem WHERE em tabela grande |
| `05_slow_query.sql` | **Slow Query** | Query com CROSS JOIN pesado |
| `06_cpu_intensive.sql` | **CPU Stress** | Loop com cálculos em 10M rows |

### Executar incidentes manualmente

```bash
# Executar full scan
docker exec -i sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong!Passw0rd' -C \
  -i /simulate/04_full_scan.sql

# Executar stress de CPU
docker exec -i sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong!Passw0rd' -C \
  -i /simulate/06_cpu_intensive.sql
```

---

## 📊 Como monitorar

### Com Datadog (DBM)

1. Configure `DD_API_KEY` no `.env`
2. Acesse **Databases** no Datadog
3. Encontre o host `lab-sqlserver-dbm`
4. Explore: Query Metrics, Samples, Explain Plans, Wait Statistics

### Com Grafana (local)

1. Acesse http://localhost:3000
2. Login: `admin / admin`
3. Dashboard pré-provisionado: **SQL Server DBM Style**

### Com SSMS / Azure Data Studio

```
Server: localhost,1433
User: sa
Password: YourStrong!Passw0rd
Database: SimDB
```

### Queries úteis de diagnóstico

```sql
-- Top queries por duração
SELECT TOP 10
    qs.execution_count,
    qs.total_elapsed_time / 1000 AS total_ms,
    qs.total_elapsed_time / qs.execution_count / 1000 AS avg_ms,
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_elapsed_time DESC;

-- Wait statistics (sem ruído)
SELECT TOP 10
    wait_type, wait_time_ms,
    wait_time_ms * 100.0 / SUM(wait_time_ms) OVER() AS pct
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN ('CLR_SEMAPHORE','LAZYWRITER_SLEEP',
    'RESOURCE_QUEUE','SLEEP_TASK','SLEEP_SYSTEMTASK',
    'SQLTRACE_BUFFER_FLUSH','WAITFOR')
ORDER BY wait_time_ms DESC;

-- Buffer cache hit ratio
SELECT
    (CAST(a.cntr_value AS FLOAT) /
     CAST(b.cntr_value AS FLOAT)) * 100 AS hit_ratio
FROM sys.dm_os_performance_counters a
JOIN sys.dm_os_performance_counters b
    ON a.object_name = b.object_name
WHERE a.counter_name = 'Buffer cache hit ratio'
  AND b.counter_name = 'Buffer cache hit ratio base'
  AND a.object_name LIKE '%Buffer Manager%';
```

---

## 🛠️ Personalização

### Ajustar volume de dados

Edite `sql/credit_product_setup.sql`:

```sql
-- Número de clientes (default: 10.000)
WHILE @i <= 10000

-- Número de propostas (default: 50.000)
WHILE @i <= 50000
```

### Ajustar taxa de queries

Edite `app/credit_product_simulator.py` — altere os intervalos de `time.sleep()` em cada serviço.

### Rodar sem Datadog

Remova ou comente os serviços `datadog-agent` e `app` no `docker-compose.yaml`. O SQL Server, Prometheus e Grafana funcionam independentemente.

---

## 🧹 Limpeza

```bash
# Parar
docker compose down

# Parar e remover volumes (dados)
docker compose down -v

# Remover tudo (incluindo imagens)
docker compose down -v --rmi all
```

---

## 📚 Documentação

- [Arquitetura detalhada](docs/architecture.md)
- [Guia completo da simulação](docs/simulation-guide.md)

---

**Stack:** SQL Server 2022 · Python 3.11 · Datadog Agent 7 · OpenTelemetry · Prometheus · Grafana
