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
    Seller: Alice Corp
    Buyer: Bob

objects
    Goods: movable
    Price: money
    Secrets: service

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
    Seller: Alice Corp
    Buyer: Bob

objects
    Car: movable
    Price: money

article 1 Exchange
    obligation Seller must deliver Car to Buyer.
    claim Seller may demand pay of Price from Buyer.
    procedure Closing:
        Seller delivers Car to Buyer.
        Buyer pays Price to Seller.
```
