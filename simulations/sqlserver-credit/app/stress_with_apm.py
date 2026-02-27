#!/usr/bin/env python3
"""
Aplicação de stress test com Datadog APM habilitado
Gera traces end-to-end: código → query SQL → explain plan
"""

import time
import random
import pyodbc
from ddtrace import tracer, patch_all

# Habilita instrumentação automática (SQL, HTTP, etc.)
patch_all()

# Configuração do banco (usando usuário específico da aplicação)
CONN_STRING = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=sqlserver;"
    "DATABASE=SimDB;"
    "UID=app_user;"
    "PWD=AppUser123!@#;"
    "TrustServerCertificate=yes;"
)


def get_connection():
    """Cria conexão com SQL Server"""
    return pyodbc.connect(CONN_STRING)


@tracer.wrap(service="simdb-api", resource="get_orders")
def get_orders(customer_id):
    """Busca pedidos de um cliente específico"""
    with tracer.trace("database.query", service="simdb-api") as span:
        span.set_tag("customer_id", customer_id)
        span.set_tag("db.system", "sqlserver")
        span.set_tag("db.name", "SimDB")
        
        conn = get_connection()
        cursor = conn.cursor()
        
        # Query com JOIN (vai gerar explain plan interessante)
        query = """
            SELECT o.OrderID, o.Amount, o.Status, o.CreatedAt,
                   COUNT(oi.ItemID) AS item_count,
                   SUM(oi.Price * oi.Quantity) AS total_value
            FROM Orders o
            LEFT JOIN OrderItems oi ON o.OrderID = oi.OrderID
            WHERE o.CustomerID = ?
            GROUP BY o.OrderID, o.Amount, o.Status, o.CreatedAt
            ORDER BY o.CreatedAt DESC
        """
        
        cursor.execute(query, (customer_id,))
        rows = cursor.fetchall()
        
        span.set_tag("db.row_count", len(rows))
        cursor.close()
        conn.close()
        
        return rows


@tracer.wrap(service="simdb-api", resource="get_inventory")
def get_inventory(min_stock):
    """Busca produtos com estoque baixo"""
    with tracer.trace("database.query", service="simdb-api") as span:
        span.set_tag("min_stock", min_stock)
        span.set_tag("db.system", "sqlserver")
        span.set_tag("db.name", "SimDB")
        
        conn = get_connection()
        cursor = conn.cursor()
        
        query = """
            SELECT ProductID, Stock, LastUpdated
            FROM Inventory
            WHERE Stock < ?
            ORDER BY Stock ASC
        """
        
        cursor.execute(query, (min_stock,))
        rows = cursor.fetchall()
        
        span.set_tag("db.row_count", len(rows))
        cursor.close()
        conn.close()
        
        return rows


@tracer.wrap(service="simdb-api", resource="slow_analytics")
def slow_analytics():
    """Query analítica pesada (gera explain plan complexo)"""
    with tracer.trace("database.query", service="simdb-api") as span:
        span.set_tag("db.system", "sqlserver")
        span.set_tag("db.name", "SimDB")
        span.set_tag("query_type", "analytics")
        
        conn = get_connection()
        cursor = conn.cursor()
        
        # Query com window function e múltiplos JOINs
        query = """
            SELECT TOP 100
                o.OrderID,
                o.CustomerID,
                o.Amount,
                i.ProductID,
                i.Stock,
                SUM(oi.Price * oi.Quantity) OVER (
                    PARTITION BY o.CustomerID 
                    ORDER BY o.CreatedAt
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS running_total
            FROM Orders o
            JOIN OrderItems oi ON o.OrderID = oi.OrderID
            JOIN Inventory i ON oi.ProductID = i.ProductID
            WHERE o.Amount > 50
            ORDER BY running_total DESC
        """
        
        cursor.execute(query)
        rows = cursor.fetchall()
        
        span.set_tag("db.row_count", len(rows))
        cursor.close()
        conn.close()
        
        return rows


@tracer.wrap(service="simdb-api", resource="update_inventory")
def update_inventory(product_id, quantity):
    """Atualiza estoque de um produto"""
    with tracer.trace("database.query", service="simdb-api") as span:
        span.set_tag("product_id", product_id)
        span.set_tag("quantity", quantity)
        span.set_tag("db.system", "sqlserver")
        span.set_tag("db.name", "SimDB")
        
        conn = get_connection()
        cursor = conn.cursor()
        
        query = """
            UPDATE Inventory
            SET Stock = Stock - ?,
                LastUpdated = GETDATE()
            WHERE ProductID = ?
        """
        
        cursor.execute(query, (quantity, product_id))
        conn.commit()
        
        span.set_tag("db.rows_affected", cursor.rowcount)
        cursor.close()
        conn.close()


def main():
    """Loop principal de stress test com APM"""
    print("🚀 Stress test com APM iniciado")
    print("   Service: simdb-api")
    print("   Traces sendo enviados para Datadog Agent")
    print("")
    
    iteration = 0
    
    while True:
        iteration += 1
        
        try:
            # Simula diferentes operações com traces
            operation = random.choice([
                "get_orders",
                "get_inventory",
                "slow_analytics",
                "update_inventory"
            ])
            
            if operation == "get_orders":
                customer_id = random.randint(1, 1000)
                with tracer.trace("api.request", service="simdb-api") as span:
                    span.set_tag("http.method", "GET")
                    span.set_tag("http.url", f"/api/orders?customer_id={customer_id}")
                    orders = get_orders(customer_id)
                    print(f"✓ [{iteration}] GET /api/orders (customer={customer_id}): {len(orders)} orders")
            
            elif operation == "get_inventory":
                min_stock = random.randint(50, 150)
                with tracer.trace("api.request", service="simdb-api") as span:
                    span.set_tag("http.method", "GET")
                    span.set_tag("http.url", f"/api/inventory?min_stock={min_stock}")
                    inventory = get_inventory(min_stock)
                    print(f"✓ [{iteration}] GET /api/inventory (min={min_stock}): {len(inventory)} products")
            
            elif operation == "slow_analytics":
                with tracer.trace("api.request", service="simdb-api") as span:
                    span.set_tag("http.method", "GET")
                    span.set_tag("http.url", "/api/analytics/customer-value")
                    results = slow_analytics()
                    print(f"✓ [{iteration}] GET /api/analytics (slow query): {len(results)} results")
            
            elif operation == "update_inventory":
                product_id = random.randint(1, 3)
                quantity = random.randint(1, 5)
                with tracer.trace("api.request", service="simdb-api") as span:
                    span.set_tag("http.method", "POST")
                    span.set_tag("http.url", f"/api/inventory/{product_id}")
                    update_inventory(product_id, quantity)
                    print(f"✓ [{iteration}] POST /api/inventory/{product_id} (qty={quantity})")
            
            # Intervalo entre requests
            time.sleep(random.uniform(2, 5))
        
        except Exception as e:
            print(f"✗ [{iteration}] Error: {e}")
            time.sleep(5)


if __name__ == "__main__":
    # Aguarda SQL Server e Datadog Agent ficarem prontos
    print("Aguardando 15 segundos para SQL Server e Datadog Agent iniciarem...")
    time.sleep(15)
    
    main()
