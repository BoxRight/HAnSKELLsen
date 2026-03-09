law PermitLeaseCase
authority private
enacted 2025-01-01

import "../statutes/environmental_permit.dsl"
import "../statutes/lease_framework_import.dsl"

instantiate LeaseFramework(Lessor=Lessor, Lessee=Lessee, UseObject=LeaseUse, RentObject=MonthlyRent)

scenario PermitThenLease:
    at 2025-01-05
        act Regulator grants Permit to Borrower.
    at 2025-01-10
        act Lessor grants LeaseUse to Lessee.
