# Legal Examples

## Sales Statute

```text
law SalesLaw
authority legislative
enacted 2025-01-01

vocabulary
    verb deliver: deliver
    verb delivery: deliver
    verb pay: pay
    verb disclose: disclose

parties
    Seller: Alice Corp, legal person, exercise capacity, address 123 Business St
    Buyer: Bob, natural person, enjoy capacity, address 456 Home Ave

objects
    Goods: movable, start 2025-01-01, due 2025-03-01
    Price: money, due 2025-03-01
    Secrets: service, omission, of Goods, start 2025-01-01, end 2025-12-31

article 1 Core Duties
    fact authority legislative is present.
    obligation Seller must deliver Goods to Buyer.
    claim Buyer may demand delivery of Goods from Seller.
    prohibition Seller must not disclose Secrets to Buyer.
    privilege Seller may refrain from disclose Secrets to Buyer.
    procedure Sale:
        Seller delivers Goods to Buyer.
        Buyer pays Price to Seller.
    rule DeliveryClaim
        If Buyer owns Goods
        then Buyer may demand delivery of Goods from Seller.
```

## Car Sale Contract

```text
law CarSale
authority private
enacted 2025-03-01

vocabulary
    verb deliver: deliver
    verb delivery: deliver
    verb pay: pay

parties
    Seller: Alice Corp, legal person, exercise capacity
    Buyer: Bob, natural person, enjoy capacity

objects
    Car: movable, start 2025-03-01, due 2025-03-01
    Price: money, due 2025-03-01

article 1 Exchange
    obligation Seller must deliver Car to Buyer.
    claim Seller may demand pay of Price from Buyer.
    privilege Buyer may pay Price to Seller.
    procedure Closing:
        Seller delivers Car to Buyer.
        Buyer pays Price to Seller.
```
