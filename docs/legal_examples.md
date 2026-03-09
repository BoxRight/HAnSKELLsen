# Legal Examples

## Sales Statute Module

```text
law SalesLaw
authority legislative
enacted 2025-01-01

import "../shared/base_sale_shared.dsl"

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

## Car Sale Refinement Module

```text
law CarSaleRefinement
authority private
enacted 2025-03-01

import "../statutes/sales.dsl"

article 9 Exchange Refinement
    obligation Buyer must pay Price to Seller.
    claim Seller may demand pay of Price from Buyer.
    privilege Buyer may pay Price to Seller.
    procedure Closing:
        Seller delivers Goods to Buyer.
        Buyer pays Price to Seller.
```

## Car Sale Case Instantiation

```text
law CarSaleCase
authority private
enacted 2025-03-01

import "../statutes/sales.dsl"
import "../contracts/car_sale.dsl"

scenario ClosingDay:
    at 2025-03-01
        act Seller delivers Goods to Buyer.
        act Buyer pays Price to Seller.
```

## Templated Lease Case

```text
law TemplatedLease
authority legislative
enacted 2025-01-01

parties
    DefaultLessor: Alice Corp, legal person, exercise capacity
    DefaultLessee: Bob, natural person, enjoy capacity

objects
    Flat: nonmovable, start 2025-01-01, due 2025-01-01
    LeaseUse: service, performance, of Flat, start 2025-01-01, due 2025-01-01
    MonthlyRent: money, due 2025-02-01

template LeaseFramework(Lessor, Lessee, UseObject, RentObject):
    article 1 {{Lessor}} Core Duties
        obligation Lessor must grant UseObject to Lessee.
        claim Lessee may demand grant of UseObject from Lessor.
    article 2 {{Lessee}} Payment Trigger
        rule RentDutyAfterUse
            If Lessor grants UseObject to Lessee
            then Lessee must pay RentObject to Lessor.

instantiate LeaseFramework(Lessor=DefaultLessor, Lessee=DefaultLessee, UseObject=LeaseUse, RentObject=MonthlyRent)

article 9 Contract Refinement
    obligation DefaultLessee must pay MonthlyRent to DefaultLessor.
    privilege DefaultLessee may pay MonthlyRent to DefaultLessor.
```

## Imported Legislative And Private Layers

```text
law LeaseFrameworkStatute
authority legislative
enacted 2025-01-01

import "../shared/base_lease_shared.dsl"

template LeaseFramework(Lessor, Lessee, UseObject, RentObject):
    article 1 Legislative Lease Framework
        obligation Lessor must grant UseObject to Lessee.
        claim Lessee may demand grant of UseObject from Lessor.
    article 2 Legislative Payment Trigger
        rule RentDutyAfterUse
            If Lessor grants UseObject to Lessee
            then Lessee must pay RentObject to Lessor.
```

```text
law PrivateLeaseRefinement
authority private
enacted 2025-01-15

import "../shared/base_lease_shared.dsl"

article 9 Contract Refinement
    obligation Lessee must pay MonthlyRent to Lessor.
    privilege Lessee may pay MonthlyRent to Lessor.
```

```text
law ComposedLeaseCase
authority private
enacted 2025-02-01

import "../statutes/lease_framework_import.dsl"
import "../contracts/private_lease_refinement.dsl"

instantiate LeaseFramework(Lessor=Lessor, Lessee=Lessee, UseObject=LeaseUse, RentObject=MonthlyRent)

scenario PrivateBreach:
    at 2025-01-21
        act Lessor grants LeaseUse to Lessee.
    at 2025-02-21
        counteract Lessee fails to pay MonthlyRent to Lessor.
```

In this composition:

- the imported legislative file contributes the reusable lease framework template
- the imported private file contributes only the private contract refinement
- the instantiation file is the canonical runnable entrypoint and owns the executable scenario
- the instantiated framework keeps legislative authority on the norms it generates
- the private refinement keeps private authority on the clauses defined in the contract file

Recommended `lawlib` structure:

- `statutes/` holds reusable legal frameworks
- `contracts/` holds reusable private refinements
- `shared/` holds common declarations imported by multiple modules
- `instantiations/` holds assembled case files with scenarios

Typical runnable files now live at paths like:

- `lawlib/instantiations/composed_lease_regime.dsl`
- `lawlib/instantiations/car_sale_case.dsl`
- `lawlib/instantiations/residential_lease.dsl`
- `lawlib/instantiations/templated_residential_lease.dsl`

## Renewable Energy Benchmark

The repository also includes a multi-regime benchmark intended to stress the current DSL boundary before any numeric intrinsic layer is added:

- `lawlib/shared/renewable_project_shared.dsl`
- `lawlib/statutes/renewable_energy_leasing.dsl`
- `lawlib/statutes/biodiversity_regulation.dsl`
- `lawlib/statutes/renewable_tax_credit.dsl`
- `lawlib/contracts/solar_farm_lease.dsl`
- `lawlib/contracts/project_financing.dsl`
- `lawlib/contracts/project_insurance.dsl`
- `lawlib/instantiations/renewable_energy_case.dsl`

See `docs/renewable_energy_benchmark.md` for the coverage map and the ranked backlog of legal-structural gaps versus future computational needs.
