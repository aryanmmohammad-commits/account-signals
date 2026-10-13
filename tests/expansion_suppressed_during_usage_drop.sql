-- Safety rule: an account with a usage_drop must never get a LIVE expansion
-- alert, and only expansion signals can be suppressed.
-- Returns every row that breaks the rule. Zero rows = pass.
select e.account_id, e.signal_type, e.status, 'expansion went out during a usage_drop' as problem
from {{ ref('signal_changes') }} as e
inner join {{ ref('signal_changes') }} as d
    on d.account_id = e.account_id
   and d.signal_type = 'usage_drop'
where e.signal_type = 'expansion'
  and e.status <> 'suppressed'

union all

select account_id, signal_type, status, 'only expansion can be suppressed' as problem
from {{ ref('signal_changes') }}
where status = 'suppressed'
  and signal_type <> 'expansion'
