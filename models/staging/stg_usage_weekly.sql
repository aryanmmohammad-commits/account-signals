-- Weekly active users per tenant.
-- Removes exact duplicate rows only. If two rows disagree on the number,
-- the uniqueness test stops the build: picking one would be guessing.
select distinct
    tenant_id,
    cast(week_start as date)             as week_start,
    cast(weekly_active_users as integer) as weekly_active_users
from {{ source('raw', 'usage_weekly') }}