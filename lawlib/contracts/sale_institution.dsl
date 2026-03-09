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
    Seller: Alice Corp, legal person, exercise capacity, address 123 Business St
    Buyer: Bob, natural person, enjoy capacity, address 456 Home Ave

objects
    Goods: movable, start 2025-01-01, due 2025-03-01
    Price: money, due 2025-03-01
    BankCredit: money, due 2025-03-01
    Secrets: service, omission, of Goods, start 2025-01-01, end 2025-12-31

article 1 Formation
    fact authority legislative is present.
    obligation Seller must deliver Goods to Buyer.
    obligation Buyer must pay Price to Seller.

article 2 Claims
    claim Buyer may demand delivery of Goods from Seller.
    claim Seller may demand pay of Price from Buyer.

article 3 Prohibitions
    prohibition Seller must not disclose Secrets to Buyer.
    privilege Seller may refrain from disclose Secrets to Buyer.

article 4 Procedures
    procedure SalePerformance:
        Seller delivers Goods to Buyer.
        Buyer pays Price to Seller.
    procedure PaymentAlternative:
        Buyer pays Price to Seller.
        or
        Buyer transfers BankCredit to Seller.

article 5 Derivation
    fact Buyer owns Goods.
    rule PaymentClaimAfterOwnership
        If Buyer owns Goods
        then Seller may demand pay of Price from Buyer.
