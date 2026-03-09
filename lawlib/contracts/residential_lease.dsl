law ResidentialLease
authority legislative
enacted 2025-01-01

vocabulary
    verb grant: grant
    verb use: use
    verb pay: pay
    verb payment: pay
    verb transfer: pay
    verb retake: retake

parties
    Lessor: Alice Corp
    Lessee: Bob

objects
    Property: nonmovable
    Rent: money
    LeaseUse: service
    BankDeposit: money

article 1 Fundamental Duties
    obligation Lessor must grant LeaseUse to Lessee.
    obligation Lessee must pay Rent to Lessor.

article 2 Core Claims
    claim Lessee may demand grant of LeaseUse from Lessor.
    claim Lessor may demand pay of Rent from Lessee.

article 3 Protection Of Use
    prohibition Lessor must not retake Property to Lessee.

article 4 Normal Performance
    procedure LeasePerformance:
        Lessor grants LeaseUse to Lessee.
        Lessee pays Rent to Lessor.
    procedure RentPaymentAlternative:
        Lessee pays Rent to Lessor.
        or
        Lessee transfers BankDeposit to Lessor.

article 5 Derived Effect
    rule UseRightFromPropertyHolding
        If Lessor owns Property
        then Lessor must grant LeaseUse to Lessee.
