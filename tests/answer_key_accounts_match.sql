-- Checks all 20 accounts against answer_key/expected_accounts.csv:
-- seats, users, change, whitespace, and which signals were detected.
-- Returns one row per account where anything differs. Zero rows = pass.
--
-- The answer key is read straight from the CSV, so it never enters the
-- warehouse. It's tagged so it can be skipped on real data:
--     dbt build --exclude tag:answer_key
{{ config(tags = ['answer_key']) }}

with expected as (
    select *
    from read_csv('answer_key/expected_accounts.csv', header = true, delim = ',')
),

whitespace as (
    select account_id, count(*) as whitespace_count
    from {{ ref('int_account_whitespace') }}
    group by account_id
),

detected as (
    select
        account_id,
        string_agg(signal_type, ';' order by signal_type desc) as signals
    from {{ ref('signal_changes') }}
    group by account_id
),

actual as (
    select
        u.account_id,
        u.seats,
        u.last_week_users,
        u.this_week_users,
        u.utilization_change_pct,
        coalesce(w.whitespace_count, 0) as whitespace_count,
        coalesce(s.signals, 'none')     as signals
    from {{ ref('account_utilization') }} as u
    left join whitespace as w on w.account_id = u.account_id
    left join detected   as s on s.account_id = u.account_id
)

select
    coalesce(e.account_id, a.account_id) as account_id,
    e.what_this_row_tests,
    e.last_week_users   as expected_last_week,
    a.last_week_users   as actual_last_week,
    e.this_week_users   as expected_this_week,
    a.this_week_users   as actual_this_week,
    e.health_change_pct as expected_change_pct,
    round(a.utilization_change_pct, 1) as actual_change_pct,
    e.whitespace_count  as expected_whitespace,
    a.whitespace_count  as actual_whitespace,
    e.expected_signals,
    a.signals           as actual_signals
from expected as e
full outer join actual as a
    on a.account_id = e.account_id
where e.account_id is null
   or a.account_id is null
   or a.seats            is distinct from e.seats
   or a.last_week_users  is distinct from e.last_week_users
   or a.this_week_users  is distinct from e.this_week_users
   or a.whitespace_count is distinct from e.whitespace_count
   or a.signals          is distinct from e.expected_signals
   or abs(a.utilization_change_pct - e.health_change_pct) > 0.051
