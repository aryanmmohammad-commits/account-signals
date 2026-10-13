-- The product catalog. P1 is the core course library every account owns.
select
    product_id,
    product_name,
    cast(annual_price_per_seat_usd as decimal(10, 2)) as annual_price_per_seat_usd
from {{ source('raw', 'products') }}
