# Snowflake Rebuild — Enterprise Fraud DWH

Rebuilds the star schema and analytics layer from
[enterprise-dwh-analytics](https://github.com/jumma786/enterprise-dwh-analytics)
(originally Teradata + DuckDB) on Snowflake — a platform I use at work, but had
not previously migrated a warehouse onto from another engine.

## Why this project

I query Snowflake day to day at work, but running a *full platform migration*
onto it — schema translation, bulk export, load pipeline — is a different
exercise from querying an environment someone else built. Rather than just
read about the differences, I rebuilt a warehouse I'd already designed
properly once (real 6.36M-row transaction data, a working star schema, a
validated fraud scorecard) on the new platform, so the exercise is about the
platform's differences rather than a toy example.

**Honesty note:** the load step needs a Snowflake account of my own, which I
don't have — see [`SIGNUP_CHECKLIST.md`](SIGNUP_CHECKLIST.md). Everything that
doesn't require one is built and tested: the schema translation, the real data
export, and the load/analytics scripts are ready to run the moment an account
exists. To be precise about what this repo does and does not show — I use
Snowflake in my professional work, but **this particular migration has not been
executed end to end against a live Snowflake instance.** It documents a
self-directed platform-migration exercise, not a production deployment.

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
