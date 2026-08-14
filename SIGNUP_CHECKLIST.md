# Snowflake Sign-Up Checklist

Everything in this project except the final load step is already built and
tested against the real local warehouse data. This is what's left, and it
needs your own account — I can't create it for you.

1. **Sign up** for the Snowflake free trial: https://signup.snowflake.com
   (30-day trial, $400 free credit, no card required to start). Choose the
   **Standard** edition and a region close to you (e.g. AWS eu-west-2 /
   London) to keep latency low.
2. After signup, note your **account identifier** — shown in the URL of your
   Snowflake web UI, e.g. `ab12345.eu-west-2`. This is `SNOWFLAKE_ACCOUNT`.
3. Your login username/password from signup are `SNOWFLAKE_USER` /
   `SNOWFLAKE_PASSWORD`.
4. Trial accounts come with a default `COMPUTE_WH` warehouse and
   `ACCOUNTADMIN` role — that's `SNOWFLAKE_WAREHOUSE` / `SNOWFLAKE_ROLE`,
   no extra setup needed.
5. Set the environment variables (PowerShell example):
   ```powershell
   $env:SNOWFLAKE_ACCOUNT = "ab12345.eu-west-2"
   $env:SNOWFLAKE_USER = "your_username"
   $env:SNOWFLAKE_PASSWORD = "your_password"
   $env:SNOWFLAKE_WAREHOUSE = "COMPUTE_WH"
   $env:SNOWFLAKE_ROLE = "ACCOUNTADMIN"
   ```
6. Install the connector:
   ```bash
   pip install snowflake-connector-python
   ```
7. Run the loader:
   ```bash
   python python/load_via_connector.py
   ```
8. Run `sql/03_analytics_snowflake.sql` in a Snowflake worksheet to verify
   the fraud scorecard numbers match the original project (48.6%
   recall / 76.4% precision on the 4-signal scorecard).

Never commit your password or account identifier to git — they're read from
environment variables specifically so nothing secret ends up in this repo.
