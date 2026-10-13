-- Finds tenant-weeks that appear more than once in the raw export.
-- Zero rows returned = pass. Catches the planted duplicate (T-5018).
{{ config(severity = 'warn') }}

select tenant_id, week_start, count(*) as copies
from {{ source('raw', 'usage_weekly') }}
group by tenant_id, week_start
having count(*) > 1