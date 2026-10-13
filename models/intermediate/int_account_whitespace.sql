-- What each account doesn't own yet: every product in the catalog minus
-- the ones it already has. One row per account per missing product.
-- An account that owns everything has no rows here (ACC-016).
--
-- potential_arr_usd = seats x list price: an upper bound, not a forecast.
select
    a.account_id,
    p.product_id,
    p.product_name,
    a.seats * p.annual_price_per_seat_usd as potential_arr_usd
from {{ ref('stg_accounts') }} as a
cross join {{ ref('stg_products') }} as p
where not exists (
    select 1
    from {{ ref('stg_account_products') }} as ap
    where ap.account_id = a.account_id
      and ap.product_id = p.product_id
)
