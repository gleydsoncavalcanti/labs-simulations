# 🏗️ Arquitetura — PostgreSQL Credit Lab

## Visão Geral

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Network: observability            │
│                                                                 │
│  ┌──────────────┐     ┌─────────────────┐     ┌─────────────┐  │
│  │ PostgreSQL   │────▶│ Datadog Agent 7 │────▶│  Datadog    │  │
│  │   15-alpine  │     │ (DBM + APM)     │     │  Cloud      │  │
│  │  creditdb    │     │                 │     │             │  │
│  └──────┬───────┘     └─────────────────┘     └─────────────┘  │
│         │                                                       │
│         │             ┌─────────────────┐     ┌─────────────┐  │
│         └────────────▶│ postgres_export  │────▶│ Prometheus  │  │
│                       │  (métricas)     │     │             │  │
│                       └─────────────────┘     └──────┬──────┘  │
│                                                       │         │
│  ┌──────────────┐                             ┌───────▼──────┐  │
│  │ Python App   │                             │   Grafana    │  │
│  │ (psycopg2)   │                             │  Dashboard   │  │
│  │ APM + DBM    │                             └─────────────┘  │
│  │ Propagation  │                                               │
│  └──────────────┘                                               │
└─────────────────────────────────────────────────────────────────┘
```

## Componentes

### PostgreSQL 15-alpine
- **Porta:** `5432`
- **Credenciais:** `postgres / YourStrong!Passw0rd`
- **Database:** `creditdb`
- **Extensões:** `pg_stat_statements`, `auto_explain`
- **Configurações otimizadas:**
  - `pg_stat_statements.track=all`
  - `auto_explain.log_min_duration=200`
  - `track_io_timing=on`
  - `log_min_duration_statement=100`

### Datadog Agent 7
- **Check:** `postgres` com DBM habilitado
- **O que coleta:**
  - Query Metrics (pg_stat_statements)
  - Query Samples (pg_stat_activity)
  - Explain Plans (via função datadog.explain_statement)
  - Wait Events
  - Conexões ativas
- **DBM Propagation:** ✅ Ativo (psycopg2 injeta traceparent)

### Python App (psycopg2)
- **Driver:** `psycopg2-binary 2.9.9`
- **APM:** `ddtrace >= 2.8.0`
- **DBM Propagation:** SQL comments com traceparent injetados automaticamente
- **5 serviços** em threads concorrentes

### postgres_exporter
- **Porta:** `9187`
- **Métricas:** ~150 métricas do PostgreSQL para Prometheus

### Prometheus
- **Porta:** `9091` (para não conflitar com SQL Server lab)
- **Scrape:** postgres_exporter a cada 10s

### Grafana
- **Porta:** `3001` (para não conflitar com SQL Server lab)
- **Credenciais:** `admin / admin`

## Fluxo de dados

```
Python App (psycopg2)
    │
    ├──▶ PostgreSQL (queries com SQL comments / traceparent)
    │         │
    │         ├──▶ Datadog Agent ──▶ Datadog Cloud (DBM + APM)
    │         │        • query samples com trace_id ← DBM Propagation!
    │         │        • query metrics (pg_stat_statements)
    │         │        • explain plans (auto_explain)
    │         │        • wait events
    │         │
    │         └──▶ postgres_exporter ──▶ Prometheus ──▶ Grafana
    │
    └──▶ Datadog Agent (APM traces)
             • traces com db query info
             • link automático para DBM samples
```

## Portas expostas

| Serviço | Porta | Nota |
|---------|-------|------|
| PostgreSQL | 5432 | |
| postgres_exporter | 9187 | |
| Prometheus | 9091 | Diferente do SQL Server (9090) |
| Grafana | 3001 | Diferente do SQL Server (3000) |

## Variáveis de ambiente (.env)

```bash
DD_API_KEY=<sua-api-key>
DD_SITE=datadoghq.com
```
