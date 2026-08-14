"""
Export every table from the existing local DuckDB warehouse
(../sql/paysim_edw.duckdb, built by the enterprise-dwh-analytics project)
to Parquet files, ready to be staged into Snowflake.

This is the part of the Snowflake rebuild that needs no Snowflake account —
it proves the source data and schema are real and exportable. The next step
(load_via_connector.py) needs actual Snowflake credentials to run.
"""
import duckdb
from pathlib import Path

SOURCE_DB = Path(r"C:\Users\jumma\Downloads\sql\paysim_edw.duckdb")
OUT_DIR = Path(__file__).resolve().parent.parent / "data" / "parquet"
OUT_DIR.mkdir(parents=True, exist_ok=True)

TABLES = [
    "dim_date", "dim_transaction_type", "dim_account", "dim_risk_signal",
    "dim_location", "fact_transaction", "fact_daily_financial_activity",
    "fact_merchant_revenue",
]

con = duckdb.connect(str(SOURCE_DB), read_only=True)

for table in TABLES:
    out_path = OUT_DIR / f"{table}.parquet"
    con.execute(f"COPY {table} TO '{out_path.as_posix()}' (FORMAT PARQUET, COMPRESSION ZSTD)")
    rows = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    size_mb = out_path.stat().st_size / 1e6
    print(f"{table}: {rows:,} rows -> {out_path.name} ({size_mb:.1f} MB)")

print(f"\nAll tables exported to {OUT_DIR}")
print("Next: run python/load_via_connector.py once you have a Snowflake trial account (see SIGNUP_CHECKLIST.md)")
