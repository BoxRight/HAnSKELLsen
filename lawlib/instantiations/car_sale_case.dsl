law CarSaleCase
authority private
enacted 2025-03-01

import "../statutes/sales.dsl"
import "../contracts/car_sale.dsl"

scenario ClosingDay:
    at 2025-03-01
        act Seller delivers Goods to Buyer.
        act Buyer pays Price to Seller.
