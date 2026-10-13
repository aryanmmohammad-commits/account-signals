-- Re-grain: one row per TENANT per week  ->  one row per ACCOUNT per week.
-- Only trusted tenants count (stg_tenant_map); quarantined ones never get here.
--
-- Assumption, written down on purpose: an account's tenants have different
-- people (e.g. two offices), so adding their weekly active users doesn't
-- count anyone twice. If one person used both tenants, this would overcount.
select
    m.account_id,
    u.week_start,
    cast(sum(u.weekly_active_users) as integer) as weekly_active_users,
    count(*)                                    as tenant_count
from {{ ref('stg_usage_weekly') }} as u
inner join {{ ref('stg_tenant_map') }} as m
    on u.tenant_id = m.tenant_id
group by m.account_id, u.week_start
