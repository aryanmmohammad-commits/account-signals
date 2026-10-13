-- One row per account: utilization last week vs this week.
--
-- utilization = weekly active users / seats. It can go above 1.0 when more
-- people use the product than the account pays for (ACC-012).
--
-- The change is calculated from raw user numbers, not rounded utilization,
-- so an exact -30% stays exactly -30% (ACC-009).
--
-- When there's no usable baseline, the change is NULL with a reason,
-- instead of a fake number like -100% or "infinite growth".

with weeks as (
    select
        max(week_start)                                    as this_week,
        cast(max(week_start) - interval '7 days' as date)  as last_week
    from {{ ref('int_account_usage_weekly') }}
),

usage_by_week as (
    select
        u.account_id,
        max(case when u.week_start = w.last_week then u.weekly_active_users end) as last_week_users,
        max(case when u.week_start = w.this_week then u.weekly_active_users end) as this_week_users
    from {{ ref('int_account_usage_weekly') }} as u
    cross join weeks as w
    group by u.account_id
)

select
    a.account_id,
    a.account_name,
    a.seats,
    w.last_week,
    w.this_week,
    u.last_week_users,
    u.this_week_users,
    cast(u.last_week_users as double) / nullif(a.seats, 0) as last_week_utilization,
    cast(u.this_week_users as double) / nullif(a.seats, 0) as this_week_utilization,
    case
        when u.last_week_users is null or u.this_week_users is null then null
        when u.last_week_users = 0 then null
        else cast(100 * (u.this_week_users - u.last_week_users) as double) / u.last_week_users
    end as utilization_change_pct,
    case
        when u.last_week_users is null or u.this_week_users is null then 'unknown_missing_week'
        when u.last_week_users = 0 then 'unknown_no_baseline'
        else 'known'
    end as change_status
from {{ ref('stg_accounts') }} as a
cross join weeks as w
left join usage_by_week as u
    on u.account_id = a.account_id
