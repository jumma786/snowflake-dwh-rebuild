"""
Load the exported Parquet files (data/parquet/, produced by
export_to_parquet.py) into Snowflake: creates the DDL, an internal stage,
PUTs each file, then COPY INTOs each table.

Requires a Snowflake account — see ../SIGNUP_CHECKLIST.md. Reads credentials
from environment variables so nothing secret is ever hardcoded or committed:

    SNOWFLAKE_ACCOUNT     e.g. "ab12345.eu-west-2"
    SNOWFLAKE_USER
    SNOWFLAKE_PASSWORD
    SNOWFLAKE_WAREHOUSE   e.g. "COMPUTE_WH" (the default free-trial warehouse)
    SNOWFLAKE_ROLE        e.g. "ACCOUNTADMIN" (default role on trial accounts)

Install first:  pip install snowflake-connector-python
"""
import os
import sys
from pathlib import Path

try:
    import snowflake.connector
except ImportError:
    print("Missing dependency. Run:  pip install snowflake-connector-python")
    sys.exit(1)

BASE = Path(__file__).resolve().parent.parent
DDL_FILE = BASE / "sql" / "01_snowflake_ddl.sql"
PARQUET_DIR = BASE / "data" / "parquet"

REQUIRED_ENV = ["SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PASSWORD", "SNOWFLAKE_WAREHOUSE"]
missing = [v for v in REQUIRED_ENV if not os.environ.get(v)]
if missing:
    print(f"Missing required environment variables: {', '.join(missing)}")
    print("Set them (see SIGNUP_CHECKLIST.md), then re-run this script.")
    sys.exit(1)

TABLES = [
    "dim_date", "dim_transaction_type", "dim_account", "dim_risk_signal",
    "dim_location", "fact_transaction", "fact_daily_financial_activity",
    "fact_merchant_revenue",
]

conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    password=os.environ["SNOWFLAKE_PASSWORD"],
    warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
    role=os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN"),
)
cur = conn.cursor()

print("1/4 Running DDL (database, schema, tables)...")
ddl_sql = DDL_FILE.read_text(encoding="utf-8")
for stmt in [s.strip() for s in ddl_sql.split(";") if s.strip() and not s.strip().startswith("--")]:
    cur.execute(stmt)

print("2/4 Creating internal stage...")
cur.execute("CREATE STAGE IF NOT EXISTS DWH_ANALYTICS.CORE.PARQUET_STAGE FILE_FORMAT = (TYPE = PARQUET)")

print("3/4 Uploading Parquet files to stage (PUT)...")
for table in TABLES:
    local_path = (PARQUET_DIR / f"{table}.parquet").as_posix()
    cur.execute(f"PUT 'file://{local_path}' @DWH_ANALYTICS.CORE.PARQUET_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE")

print("4/4 Loading each table (COPY INTO, MATCH_BY_COLUMN_NAME)...")
for table in TABLES:
    cur.execute(f"""
        COPY INTO DWH_ANALYTICS.CORE.{table}
        FROM @DWH_ANALYTICS.CORE.PARQUET_STAGE/{table}.parquet
        FILE_FORMAT = (TYPE = PARQUET)
        MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    """)
    count = cur.execute(f"SELECT COUNT(*) FROM DWH_ANALYTICS.CORE.{table}").fetchone()[0]
    print(f"  {table}: {count:,} rows loaded")

cur.close()
conn.close()
print("\nDone. Run sql/03_analytics_snowflake.sql in the Snowflake worksheet to verify the analytics layer.")
