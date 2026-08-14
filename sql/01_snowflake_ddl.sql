-- =============================================================================
-- Snowflake DDL — rebuild of the enterprise-dwh-analytics star schema
-- Source (Teradata-flavoured original): github.com/jumma786/enterprise-dwh-analytics
--
-- What changed vs the Teradata original, and why:
--   - No PRIMARY INDEX / PARTITION BY RANGE_N — Snowflake has no user-defined
--     physical index. Micro-partitioning is automatic; CLUSTER BY is the
--     nearest equivalent for very large, frequently-range-filtered tables
--     (used below on fact_transaction, clustered by date_key, matching the
--     original's daily partitioning intent).
--   - SET vs MULTISET distinction doesn't exist in Snowflake — all tables
--     behave like MULTISET (duplicates allowed unless a constraint blocks
--     them). Uniqueness is enforced by the data-quality gates in Python,
--     same as the original design already did for fact_transaction.
--   - TINYINT -> BOOLEAN where the column is a true 0/1 flag, NUMBER(3,0)
--     where it's a small integer that isn't boolean (e.g. day_of_week).
--   - CHECK constraints are accepted by Snowflake's DDL but NOT enforced at
--     write time (documented Snowflake behaviour) — kept here as
--     documentation of intent, but the real enforcement is still the
--     Python data-quality gates in 03_data_quality_gates.py, exactly as
--     in the original project.
--   - COLLECT STATISTICS has no Snowflake equivalent — the query optimiser
--     auto-maintains statistics from micro-partition metadata.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS DWH_ANALYTICS;
CREATE SCHEMA IF NOT EXISTS DWH_ANALYTICS.CORE;
USE SCHEMA DWH_ANALYTICS.CORE;

CREATE OR REPLACE TABLE dim_date (
    date_key              INTEGER      NOT NULL,
    step_number           INTEGER      NOT NULL,
    calendar_datetime     TIMESTAMP_NTZ NOT NULL,
    calendar_date         DATE         NOT NULL,
    hour_of_day            NUMBER(2,0) NOT NULL,
    day_of_month            NUMBER(2,0) NOT NULL,
    simulation_day         NUMBER(5,0) NOT NULL,
    day_of_week             NUMBER(2,0) NOT NULL,
    day_name               VARCHAR      NOT NULL,
    week_of_year            NUMBER(2,0) NOT NULL,
    month_number            NUMBER(2,0) NOT NULL,
    month_name              VARCHAR      NOT NULL,
    quarter_number           NUMBER(1,0) NOT NULL,
    year_number             NUMBER(5,0) NOT NULL,
    is_weekend              BOOLEAN      NOT NULL,
    is_business_hour        BOOLEAN      NOT NULL,
    day_part                VARCHAR      NOT NULL,
    is_simulated_calendar   BOOLEAN      NOT NULL DEFAULT TRUE,
    dw_load_ts              TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key),
    CONSTRAINT chk_hour CHECK (hour_of_day BETWEEN 0 AND 23),
    CONSTRAINT chk_month CHECK (month_number BETWEEN 1 AND 12)
);

CREATE OR REPLACE TABLE dim_transaction_type (
    transaction_type_key   NUMBER(5,0)  NOT NULL,
    type_code              VARCHAR      NOT NULL,
    type_name               VARCHAR     NOT NULL,
    fund_direction           VARCHAR    NOT NULL,
    counterparty_class       VARCHAR    NOT NULL,
    is_fraud_capable         BOOLEAN    NOT NULL,
    is_revenue_bearing       BOOLEAN    NOT NULL,
    dw_load_ts               TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_dim_txn_type PRIMARY KEY (transaction_type_key)
);

CREATE OR REPLACE TABLE dim_account (
    account_key             NUMBER(38,0) NOT NULL,
    account_id               VARCHAR     NOT NULL,
    account_class            VARCHAR     NOT NULL,
    first_seen_step          INTEGER,
    last_seen_step           INTEGER,
    total_txn_count           INTEGER    NOT NULL,
    total_txn_amount           NUMBER(18,2) NOT NULL,
    sent_txn_count             INTEGER    NOT NULL,
    received_txn_count         INTEGER    NOT NULL,
    activity_band               VARCHAR   NOT NULL,
    effective_from_date         DATE      NOT NULL,
    effective_to_date           DATE      NOT NULL DEFAULT '9999-12-31',
    is_current_row               BOOLEAN  NOT NULL DEFAULT TRUE,
    dw_load_ts                    TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_dim_account PRIMARY KEY (account_key),
    CONSTRAINT chk_account_class CHECK (account_class IN ('CUSTOMER', 'MERCHANT'))
);

CREATE OR REPLACE TABLE dim_risk_signal (
    risk_signal_key          NUMBER(5,0) NOT NULL,
    has_receiver_ledger_gap   BOOLEAN    NOT NULL,
    has_account_emptied        BOOLEAN   NOT NULL,
    is_off_hours                BOOLEAN  NOT NULL,
    is_high_value                BOOLEAN NOT NULL,
    signal_count                  NUMBER(2,0) NOT NULL,
    reason_code_list                VARCHAR,
    risk_score                       NUMBER(5,0) NOT NULL,
    risk_tier                         VARCHAR NOT NULL,
    dw_load_ts                         TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_dim_risk_signal PRIMARY KEY (risk_signal_key)
);

CREATE OR REPLACE TABLE dim_location (
    location_key            INTEGER      NOT NULL,
    country_code              VARCHAR,
    country_name               VARCHAR,
    region_name                  VARCHAR,
    city_name                     VARCHAR,
    is_unknown_member              BOOLEAN NOT NULL DEFAULT FALSE,
    dw_load_ts                      TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_dim_location PRIMARY KEY (location_key)
);

-- fact_transaction: 6.36M rows in the source project — clustered by date_key
-- as the Snowflake-idiomatic equivalent of the original's daily
-- PARTITION BY RANGE_N, since most analytics queries filter/aggregate by day.
CREATE OR REPLACE TABLE fact_transaction (
    transaction_key         NUMBER(38,0) NOT NULL,
    date_key                 INTEGER     NOT NULL,
    transaction_type_key       NUMBER(5,0) NOT NULL,
    orig_account_key             NUMBER(38,0) NOT NULL,
    dest_account_key               NUMBER(38,0) NOT NULL,
    risk_signal_key                  NUMBER(5,0) NOT NULL,
    location_key                       INTEGER   NOT NULL DEFAULT -1,
    transaction_amount                  NUMBER(18,2) NOT NULL,
    orig_balance_before                   NUMBER(18,2) NOT NULL,
    orig_balance_after                      NUMBER(18,2) NOT NULL,
    dest_balance_before                       NUMBER(18,2) NOT NULL,
    dest_balance_after                          NUMBER(18,2) NOT NULL,
    orig_balance_delta                            NUMBER(18,2) NOT NULL,
    dest_balance_delta                              NUMBER(18,2) NOT NULL,
    orig_ledger_variance                              NUMBER(18,2) NOT NULL,
    dest_ledger_variance                                NUMBER(18,2) NOT NULL,
    balance_drain_ratio                                   NUMBER(15,6),
    is_fraud                                                BOOLEAN NOT NULL,
    is_flagged_fraud                                          BOOLEAN NOT NULL,
    is_account_emptied                                          BOOLEAN NOT NULL,
    dw_load_ts                                                    TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_transaction PRIMARY KEY (transaction_key),
    CONSTRAINT chk_amount CHECK (transaction_amount >= 0)
)
CLUSTER BY (date_key);

CREATE OR REPLACE TABLE fact_daily_financial_activity (
    activity_date_key        INTEGER      NOT NULL,
    transaction_type_key       NUMBER(5,0) NOT NULL,
    transaction_count            NUMBER(38,0) NOT NULL,
    total_amount                   NUMBER(18,2) NOT NULL,
    avg_amount                       NUMBER(18,2) NOT NULL,
    median_amount                      NUMBER(18,2),
    max_amount                           NUMBER(18,2) NOT NULL,
    distinct_orig_accounts                 NUMBER(38,0) NOT NULL,
    distinct_dest_accounts                   NUMBER(38,0) NOT NULL,
    fraud_count                                NUMBER(38,0) NOT NULL,
    fraud_amount                                 NUMBER(18,2) NOT NULL,
    flagged_count                                  NUMBER(38,0) NOT NULL,
    fraud_rate_pct                                   NUMBER(15,6) NOT NULL,
    dw_load_ts                                         TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_daily PRIMARY KEY (activity_date_key, transaction_type_key)
);

CREATE OR REPLACE TABLE fact_merchant_revenue (
    activity_date_key       INTEGER       NOT NULL,
    merchant_account_key       NUMBER(38,0) NOT NULL,
    payment_count                 INTEGER   NOT NULL,
    gross_revenue                    NUMBER(18,2) NOT NULL,
    avg_ticket_value                   NUMBER(18,2) NOT NULL,
    max_ticket_value                     NUMBER(18,2) NOT NULL,
    distinct_payers                        INTEGER NOT NULL,
    dw_load_ts                               TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_merchant PRIMARY KEY (activity_date_key, merchant_account_key)
);
