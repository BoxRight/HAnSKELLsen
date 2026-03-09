law ComposedLeaseRegime
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
