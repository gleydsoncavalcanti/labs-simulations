-- =========================================================
-- Criação de usuários para o lab PostgreSQL
-- =========================================================

-- Usuário da aplicação (leitura + escrita)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user WITH LOGIN PASSWORD 'AppUser123';
    END IF;
END $$;

GRANT CONNECT ON DATABASE creditdb TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_user;

-- Usuário do Datadog Agent (somente leitura + monitoramento)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'datadog') THEN
        CREATE ROLE datadog WITH LOGIN PASSWORD 'DatadogAgent123';
    END IF;
END $$;

GRANT CONNECT ON DATABASE creditdb TO datadog;
GRANT USAGE ON SCHEMA public TO datadog;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO datadog;
GRANT pg_monitor TO datadog;

-- Permissão para pg_stat_statements
GRANT SELECT ON pg_stat_statements TO datadog;

-- Função para explain plans (DBM)
CREATE OR REPLACE FUNCTION datadog.explain_statement(
    l_query TEXT,
    OUT explain JSON
)
RETURNS SETOF JSON AS
$$
DECLARE
    curs REFCURSOR;
    plan JSON;
BEGIN
    OPEN curs FOR EXECUTE pg_catalog.concat('EXPLAIN (FORMAT JSON) ', l_query);
    LOOP
        FETCH curs INTO plan;
        EXIT WHEN NOT FOUND;
        explain := plan;
        RETURN NEXT;
    END LOOP;
    CLOSE curs;
    RETURN;
END;
$$
LANGUAGE plpgsql
RETURNS NULL ON NULL INPUT
SECURITY DEFINER;
