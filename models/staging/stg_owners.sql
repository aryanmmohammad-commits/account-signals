-- People an alert can go to: AEs, CSMs, and one RevOps fallback.
-- FastAPI reads this later to turn a role into a Slack handle.
select
    owner_id,
    name  as owner_name,
    role  as owner_role,
    slack_handle
from {{ source('raw', 'owners') }}
