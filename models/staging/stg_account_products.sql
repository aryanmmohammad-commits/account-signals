-- What each account already owns: one row per account per product.
select
    account_id,
    product_id,
    cast(start_date as date) as start_date
from {{ source('raw', 'account_products') }}
