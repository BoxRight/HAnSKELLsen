law TemplatedResidentialLease
authority legislative
enacted 2025-01-01

vocabulary
    verb grant: grant
    verb pay: pay
    verb retake: retake

parties
    DefaultLessor: Alice Corp, legal person, exercise capacity, address 123 Business St
    DefaultLessee: Bob, natural person, enjoy capacity, address 456 Home Ave

objects
    Flat: nonmovable, start 2025-01-01, due 2025-01-01
    LeaseUse: service, performance, of Flat, start 2025-01-01, due 2025-01-01
    QuietEnjoyment: service, omission, of Flat, start 2025-01-01, end 2025-12-31
    MonthlyRent: money, due 2025-02-01

template LeaseFramework(Lessor, Lessee, UseObject, RentObject, QuietUse):
    article 1 {{Lessor}} Core Duties
        obligation Lessor must grant UseObject to Lessee.
        claim Lessee may demand grant of UseObject from Lessor.
    article 2 {{Lessee}} Payment Trigger
        rule RentDutyAfterUse
            If Lessor grants UseObject to Lessee
            then Lessee must pay RentObject to Lessor.
    article 3 Quiet Use Protection
        prohibition Lessor must not retake QuietUse to Lessee.
        privilege Lessor may refrain from retake QuietUse to Lessee.
    scenario {{Lessee}}Breach:
        at 2025-01-21
            act Lessor grants UseObject to Lessee.
        at 2025-02-21
            counteract Lessee fails to pay RentObject to Lessor.

instantiate LeaseFramework(Lessor=DefaultLessor, Lessee=DefaultLessee, UseObject=LeaseUse, RentObject=MonthlyRent, QuietUse=QuietEnjoyment)

article 9 Contract Refinement
    obligation DefaultLessee must pay MonthlyRent to DefaultLessor.
    privilege DefaultLessee may pay MonthlyRent to DefaultLessor.
