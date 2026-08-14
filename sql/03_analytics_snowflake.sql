-- =============================================================================
-- Snowflake analytics layer — adapted from the original Teradata queries in
-- enterprise-dwh-analytics. Run after 01_snowflake_ddl.sql + a successful load.
--
-- QUALIFY is one of the few clauses Snowflake and Teradata share (not
-- standard ANSI SQL) — kept deliberately below as the clearest example of a
-- transferable skill between the two platforms.
-- =============================================================================
USE SCHEMA DWH_ANALYTICS.CORE;

-- -----------------------------------------------------------------------------
-- 1. Fraud scorecard recall/precision — reproduces the headline result from
--    the source project (baseline 0.19% recall vs scorecard signals)
-- -----------------------------------------------------------------------------
WITH scored AS (
    SELECT
        f.transaction_key,
        f.is_fraud,
        f.is_flagged_fraud AS baseline_flag,
        r.has_receiver_ledger_gap,
        r.has_account_emptied,
        r.is_off_hours,
        r.signal_count,
        CASE WHEN r.signal_count >= 1 THEN 1 ELSE 0 END AS scorecard_flag
    FROM fact_transaction f
    JOIN dim_risk_signal r ON f.risk_signal_key = r.risk_signal_key
)
SELECT
    'baseline_control' AS model,
    SUM(CASE WHEN baseline_flag = 1 AND is_fraud = 1 THEN 1 ELSE 0 END) AS true_positives,
    SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) AS total_frauds,
    ROUND(100.0 * SUM(CASE WHEN baseline_flag = 1 AND is_fraud = 1 THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END), 0), 2) AS recall_pct,
    ROUND(100.0 * SUM(CASE WHEN baseline_flag = 1 AND is_fraud = 1 THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN baseline_flag = 1 THEN 1 ELSE 0 END), 0), 2) AS precision_pct
FROM scored
UNION ALL
SELECT
    'four_signal_scorecard' AS model,
    SUM(CASE WHEN scorecard_flag = 1 AND is_fraud = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END),
    ROUND(100.0 * SUM(CASE WHEN scorecard_flag = 1 AND is_fraud = 1 THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END), 0), 2),
    ROUND(100.0 * SUM(CASE WHEN scorecard_flag = 1 AND is_fraud = 1 THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN scorecard_flag = 1 THEN 1 ELSE 0 END), 0), 2)
FROM scored;

-- -----------------------------------------------------------------------------
-- 2. Top 10 highest-value days by transaction volume, using QUALIFY (shared
--    Snowflake/Teradata syntax) instead of a wrapping subquery + WHERE rn <= 10
-- -----------------------------------------------------------------------------
SELECT
    d.calendar_date,
    tt.type_name,
    fda.transaction_count,
    fda.total_amount,
    RANK() OVER (ORDER BY fda.total_amount DESC) AS amount_rank
FROM fact_daily_financial_activity fda
JOIN dim_date d ON fda.activity_date_key = d.date_key
JOIN dim_transaction_type tt ON fda.transaction_type_key = tt.transaction_type_key
QUALIFY amount_rank <= 10
ORDER BY amount_rank;

-- -----------------------------------------------------------------------------
-- 3. Merchant revenue trend with 7-day moving average (running-window function,
--    same pattern as the original's revenue-analytics module)
-- -----------------------------------------------------------------------------
SELECT
    d.calendar_date,
    SUM(fmr.gross_revenue) AS daily_revenue,
    AVG(SUM(fmr.gross_revenue)) OVER (
        ORDER BY d.calendar_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS revenue_7day_moving_avg
FROM fact_merchant_revenue fmr
JOIN dim_date d ON fmr.activity_date_key = d.date_key
GROUP BY d.calendar_date
ORDER BY d.calendar_date;

-- -----------------------------------------------------------------------------
-- 4. Account activity bands vs fraud exposure — cross-check the dim_account
--    SCD Type 2 "is_current_row" logic loaded correctly
-- -----------------------------------------------------------------------------
SELECT
    a.activity_band,
    COUNT(DISTINCT a.account_key) AS accounts,
    SUM(f.is_fraud) AS fraud_txn_count,
    ROUND(100.0 * SUM(f.is_fraud) / COUNT(*), 4) AS fraud_rate_pct
FROM fact_transaction f
JOIN dim_account a ON f.orig_account_key = a.account_key AND a.is_current_row = TRUE
GROUP BY a.activity_band
ORDER BY fraud_rate_pct DESC;
