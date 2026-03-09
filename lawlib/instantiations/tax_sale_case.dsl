law TaxSaleCase
authority private
enacted 2025-01-01

import "../statutes/generic_tax.dsl"
import "../statutes/sales.dsl"

scenario TaxAndSale:
    at 2025-02-01
        act Seller delivers Goods to Buyer.
    at 2025-02-15
        act Buyer pays Price to Seller.
    at 2025-04-15
        act Borrower pays TaxAmount to TaxAuthority.
