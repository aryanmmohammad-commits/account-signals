import duckdb

# The exports we load. thresholds is left out: it goes to Airtable later.
TABLES = [
    "accounts", "owners", "products", "account_products",
    "tenant_map", "usage_weekly", "churnzero_health", "gong_calls",
]

# Opens the warehouse file, or creates it the first time.
con = duckdb.connect("warehouse.duckdb")
con.execute("CREATE SCHEMA IF NOT EXISTS raw")

for t in TABLES:
    # Copies each CSV into raw.<table> exactly as it is,
    # plus a stamp of when it was loaded.
    con.execute(f"""
        CREATE OR REPLACE TABLE raw.{t} AS
        SELECT *, now() AS _loaded_at
        FROM read_csv('data/{t}.csv', header = true)
    """)
    n = con.execute(f"SELECT count(*) FROM raw.{t}").fetchone()[0]
    print(f"raw.{t}: {n} rows")

con.close()