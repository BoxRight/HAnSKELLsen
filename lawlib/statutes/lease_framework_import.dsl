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
