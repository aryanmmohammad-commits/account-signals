-- Sales call summaries from Gong. Context for the alert brief later:
-- a drop or an expansion makes more sense next to what the customer said.
select
    call_id,
    account_id,
    cast(call_date as date) as call_date,
    summary
from {{ source('raw', 'gong_calls') }}
