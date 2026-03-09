law SalesLaw
authority legislative
enacted 2025-01-01

import "../shared/base_sale_shared.dsl"

article 1 Core Duties
    obligation Seller must deliver Goods to Buyer.
    claim Buyer may demand delivery of Goods from Seller.
    prohibition Seller must not disclose Secrets to Buyer.
    procedure Sale:
        Seller delivers Goods to Buyer.
        Buyer pays Price to Seller.
    rule DeliveryClaim
        If Buyer owns Goods
        then Buyer may demand delivery of Goods from Seller.
