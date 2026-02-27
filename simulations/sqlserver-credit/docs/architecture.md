# 🏗️ Arquitetura do Lab

## Visão geral

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Network: observability            │
│                                                                 │
│  ┌──────────────┐     ┌─────────────────┐     ┌─────────────┐  │
│  │  SQL Server  │────▶│ Datadog Agent 7 │────▶│  Datadog    │  │
│  │    2022      │     │   (DBM nativo)  │     │  Cloud      │  │
│  │   SimDB      │     │                 │     │             │  │
│  └──────┬───────┘     └─────────────────┘     └─────────────┘  │
│         │                                                       │
│         │             ┌─────────────────┐     ┌─────────────┐  │
│         └────────────▶│  OTel Collector │────▶│ Prometheus  │  │
│                       │   (contrib)     │     │             │  │
│                       └─────────────────┘     └──────┬──────┘  │
│                                                       │         │
│                                               ┌───────▼──────┐  │
│                                               │   Grafana    │  │
│                                               │  Dashboard   │  │
│                                               └─────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Componentes

### SQL Server 2022
- **Imagem:** `mcr.microsoft.com/mssql/server:2022-latest`
- **Porta:** `1433`
- **Credenciais:** `sa / YourStrong!Passw0rd`
- **Banco de dados simulado:** `SimDB`
  - `Products` — 1.000 registros
  - `Orders` — 5.000 registros
  - `OrderItems` — 20.000 registros
  - `Inventory` — tabela auxiliar

### Datadog Agent 7
- **Imagem:** `gcr.io/datadoghq/agent:7`
- **Check:** `sqlserver` com DBM habilitado
- **O que coleta:**
  - Métricas de instância (CPU, memória, I/O, conexões)
  - Query Metrics (estatísticas agregadas de queries)
  - Query Samples (execuções reais com explain plans)
  - Activity (sessões ativas, waits, bloqueios em tempo real)
  - Settings (configurações do SQL Server)
- **Config:** `datadog-agent/conf.d/sqlserver.d/conf.yaml`

### OTel Collector (contrib)
- **Imagem:** `otel/opentelemetry-collector-contrib:latest`
- **Porta Prometheus:** `9464`
- **Receivers:** `sqlserverreceiver` (31 métricas nativas) + `sqlqueryreceiver` (5 DMV customizados)
- **Exporters:** Prometheus + Datadog (métricas)
- **Config:** `otel-config.yaml`

### Prometheus
- **Porta:** `9090`
- **Scrape target:** `otel-collector:9464` a cada 10s
- **Config:** `prometheus.yaml`

### Grafana
- **Porta:** `3000`
- **Credenciais:** `admin / admin`
- **Dashboard provisionado:** SQL Server DBM Style (OTel)
- **Datasource UID:** `prometheus`

## Fluxo de dados

```
SQL Server
    │
    ├──▶ Datadog Agent  ──▶  Datadog Cloud (DBM)
    │        • query samples (cada 10s)
    │        • query metrics (cada 10s)
    │        • activity (cada 10s)
    │        • métricas de instância (cada 15s)
    │
    └──▶ OTel Collector ──▶  Prometheus ──▶ Grafana (local)
             • 31 métricas nativas
             • 5 DMV customizados
             • coleta a cada 10s
```

## Variáveis de ambiente (.env)

```bash
DD_API_KEY=<sua-api-key>
DD_SITE=datadoghq.com
```

## Portas expostas no host

| Serviço | Porta |
|---|---|
| SQL Server | 1433 |
| OTel (Prometheus scrape) | 9464 |
| Prometheus UI | 9090 |
| Grafana UI | 3000 |
