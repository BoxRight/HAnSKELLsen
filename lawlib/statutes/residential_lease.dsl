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
    Lessor: Alice Corp, legal person, exercise capacity, address 123 Business St
    Lessee: Bob, natural person, enjoy capacity, address 456 Home Ave

objects
    Property: nonmovable, start 2025-01-01, due 2025-01-01
    Rent: money, due 2025-02-01
    LeaseUse: service, performance, of Property, start 2025-01-01, due 2025-01-01
    QuietEnjoyment: service, omission, of Property, start 2025-01-01, end 2025-12-31
    BankDeposit: money, due 2025-02-01

article 1 Fundamental Duties
    fact authority legislative is present.
    obligation Lessor must grant LeaseUse to Lessee.

article 2 Core Claims
    claim Lessee may demand grant of LeaseUse from Lessor.
    claim Lessor may demand pay of Rent from Lessee.
    privilege Lessee may pay Rent to Lessor.

article 3 Protection Of Use
    prohibition Lessor must not retake Property to Lessee.
    privilege Lessor may refrain from retake Property to Lessee.

article 4 Normal Performance
    procedure LeasePerformance:
        Lessor grants LeaseUse to Lessee.
        Lessee pays Rent to Lessor.
    procedure RentPaymentAlternative:
        Lessee pays Rent to Lessor.
        or
        Lessee transfers BankDeposit to Lessor.

article 5 Derived Effect
    rule RentDutyAfterUseGranted
        If Lessor grants LeaseUse to Lessee
        then Lessee must pay Rent to Lessor.
    rule UseDutyAfterRentPaid
        If Lessee pays Rent to Lessor
        then Lessor must grant LeaseUse to Lessee.

scenario LeaseBreach:
    at 2025-01-21
        act Lessor grants LeaseUse to Lessee.
    at 2026-01-21
        counteract Lessee fails to pay Rent to Lessor.
        natural event SevereStorm damaged the district.

scenario RentThenUse:
    at 2025-01-21
        act Lessee pays Rent to Lessor.
