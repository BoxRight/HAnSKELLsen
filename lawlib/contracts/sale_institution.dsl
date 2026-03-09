law SaleInstitution
authority legislative
enacted 2025-01-01

vocabulary
    verb deliver: deliver
    verb delivery: deliver
    verb pay: pay
    verb payment: pay
    verb transfer: pay
    verb disclose: disclose

parties
    Seller: Alice Corp
    Buyer: Bob

objects
    Goods: movable
    Price: money
    BankCredit: money
    Secrets: service

article 1 Formation
    obligation Seller must deliver Goods to Buyer.
    obligation Buyer must pay Price to Seller.

article 2 Claims
    claim Buyer may demand delivery of Goods from Seller.
    claim Seller may demand pay of Price from Buyer.

article 3 Prohibitions
    prohibition Seller must not disclose Secrets to Buyer.

article 4 Procedures
    procedure SalePerformance:
        Seller delivers Goods to Buyer.
        Buyer pays Price to Seller.
    procedure PaymentAlternative:
        Buyer pays Price to Seller.
        or
        Buyer transfers BankCredit to Seller.

article 5 Derivation
    rule PaymentClaimAfterOwnership
        If Buyer owns Goods
        then Seller may demand pay of Price from Buyer.
