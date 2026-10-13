-- The rules engine: turns each account's numbers into signals, using the
-- rules in seeds/thresholds.csv. Change the CSV and rebuild: no code change.
--
-- A signal fires only when ALL rules with the same signal_type pass.
-- A rule on an unknown (NULL) number counts as NOT passed, so "unknown"
-- can never trigger an alert.
--
-- v0.1 safety rule: an expansion signal is kept, but SUPPRESSED, when the
-- same account has a usage_drop this week. Nobody pitches an upsell to a
-- customer whose usage is collapsing. (v0.2 will check open cases instead.)
--
-- Detection and delivery are separate on purpose: this table records every
-- signal the rules found; status says which ones go out as alerts.

with whitespace as (
    select
        a.account_id,
        count(w.product_id) as whitespace_count
    from {{ ref('stg_accounts') }} as a
    left join {{ ref('int_account_whitespace') }} as w
        on w.account_id = a.account_id
    group by a.account_id
),

-- Every number a rule can look at: one row per account per metric.
metrics as (
    select account_id, 'utilization_change_pct' as metric, utilization_change_pct as metric_value
    from {{ ref('account_utilization') }}
    union all
    select account_id, 'this_week_utilization', this_week_utilization
    from {{ ref('account_utilization') }}
    union all
    select account_id, 'whitespace_count', cast(whitespace_count as double)
    from whitespace
),

-- Each rule checked against each account.
checks as (
    select
        m.account_id,
        t.signal_type,
        t.route_to_role,
        t.version,
        case t.operator
            when '<=' then m.metric_value <= t.value
            when '>=' then m.metric_value >= t.value
            when '<'  then m.metric_value <  t.value
            when '>'  then m.metric_value >  t.value
        end as passed
    from metrics as m
    inner join {{ ref('thresholds') }} as t
        on t.metric = m.metric
),

signals as (
    select
        account_id,
        signal_type,
        min(route_to_role) as route_to_role,   -- rules of one signal type share one role
        max(version)       as rule_version
    from checks
    group by account_id, signal_type
    having bool_and(coalesce(passed, false))   -- NULL (unknown) counts as not passed
),

usage_drops as (
    select account_id
    from signals
    where signal_type = 'usage_drop'
)

select
    s.account_id || '|' || s.signal_type || '|' || cast(u.this_week as varchar) as signal_key,
    s.account_id,
    u.account_name,
    s.signal_type,
    s.route_to_role,
    case when d.account_id is not null then 'suppressed' else 'alert' end            as status,
    case when d.account_id is not null then 'open usage_drop on same account' end    as suppressed_reason,
    u.this_week          as signal_week,
    u.seats,
    u.last_week_users,
    u.this_week_users,
    u.last_week_utilization,
    u.this_week_utilization,
    u.utilization_change_pct,
    ws.whitespace_count,
    s.rule_version
from signals as s
inner join {{ ref('account_utilization') }} as u
    on u.account_id = s.account_id
inner join whitespace as ws
    on ws.account_id = s.account_id
left join usage_drops as d
    on d.account_id = s.account_id
   and s.signal_type = 'expansion'
