-- The bridge from product tenant IDs to CRM account IDs: trusted rows only.
select
    tenant_id,
    account_id
from {{ source('raw', 'tenant_map') }}
where tenant_id not in (
    select tenant_id from {{ ref('quarantine_tenant_map') }}
)