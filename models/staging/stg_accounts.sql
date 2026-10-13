-- One row per CRM account. Light cleanup only: fixed types.
-- An empty csm_owner_id means "no CSM" and routes to RevOps later.
select
    account_id,
    account_name,
    ae_owner_id,
    csm_owner_id,
    cast(seats as integer)          as seats,
    cast(arr_usd as decimal(12, 2)) as arr_usd,
    cast(renewal_date as date)      as renewal_date
from {{ source('raw', 'accounts') }}