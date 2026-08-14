# Snowflake Rebuild — Enterprise Fraud DWH

Rebuilds the star schema and analytics layer from
[enterprise-dwh-analytics](https://github.com/jumma786/enterprise-dwh-analytics)
(originally Teradata + DuckDB) on Snowflake — a platform several job
descriptions I've applied to list explicitly and that I haven't used
professionally.

## Why this project

Snowflake shows up as a required or preferred tool on roles I'm targeting.
Rather than just reading Snowflake docs, I rebuilt a warehouse I'd already
designed properly once (real 6.36M-row transaction data, a working star
schema, a validated fraud scorecard) on the new platform, so the exercise is
about learning the platform's differences, not inventing a toy example.

**Honesty note:** the Snowflake load itself needs a Snowflake account, which
I don't have yet — see [`SIGNUP_CHECKLIST.md`](SIGNUP_CHECKLIST.md). Everything
that doesn't require an account is built and tested: the schema translation,
the real data export, and the load/analytics scripts are ready to run the
moment the account exists. I'm not claiming hands-on production Snowflake
experience — this documents a self-directed platform-migration exercise.

## What's done vs what's pending

| Step | Status |
|---|---|
| Export real warehouse data (6.36M+ rows) from the existing DuckDB build to Parquet | **Done** — `python/export_to_parquet.py`, tested locally |
| Translate Teradata-specific DDL to Snowflake-native DDL, with translation notes | **Done** — `sql/01_snowflake_ddl.sql` |
| Write the Snowflake load script (stage + PUT + COPY INTO) | **Done, untested against a live account** — `python/load_via_connector.py` |
| Adapt the analytics/fraud-scorecard queries to Snowflake (QUALIFY, window functions) | **Done, untested against a live account** — `sql/03_analytics_snowflake.sql` |
| Actual load + verification against a live Snowflake trial | **Pending** — needs account, see checklist |

## Key platform differences (documented in `01_snowflake_ddl.sql`)

- No user-defined Primary Index / partitioning — Snowflake auto-manages
  micro-partitions; `CLUSTER BY (date_key)` on `fact_transaction` is the
  closest equivalent to the original's daily `PARTITION BY RANGE_N`.
- No SET/MULTISET table semantics — uniqueness is enforced by the same
  Python data-quality gates the original project already used, not by the
  table type.
- `QUALIFY` is one of the few clauses **shared** between Teradata and
  Snowflake (not standard ANSI SQL) — used in `03_analytics_snowflake.sql`
  as a deliberate example of a transferable skill between the two.
- `COLLECT STATISTICS` has no equivalent — Snowflake's optimiser maintains
  statistics automatically from micro-partition metadata.

## How to run

```bash
python python/export_to_parquet.py   # already run — see data/parquet/
# then follow SIGNUP_CHECKLIST.md
python python/load_via_connector.py
```

## Tech

DuckDB (source), Parquet, Snowflake SQL, snowflake-connector-python.
