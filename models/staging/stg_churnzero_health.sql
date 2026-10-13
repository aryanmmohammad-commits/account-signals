-- ChurnZero's health score (0-100): one input, not the truth.
-- ACC-008 shows why: the score stays high while usage halves,
-- because the vendor score lags behind real behavior.
select
    account_id,
    cast(cz_health_score as integer) as cz_health_score,
    cast(score_date as date)         as score_date
from {{ source('raw', 'churnzero_health') }}
