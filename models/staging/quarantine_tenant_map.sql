-- Tenant mappings we can't trust, set aside with a reason.
-- Their usage is excluded from every account metric.
select
    t.tenant_id,
    t.account_id,
    case
        when t.account_id is null then 'account_id is empty'
        else 'account_id not found in accounts'
    end as reason
from {{ source('raw', 'tenant_map') }} as t
left join {{ ref('stg_accounts') }} as a
    on t.account_id = a.account_id
where a.account_id is null