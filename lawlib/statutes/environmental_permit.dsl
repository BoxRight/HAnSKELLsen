law EnvironmentalPermitRegulation
authority administrative
enacted 2025-02-01

import "../shared/commercial_shared.dsl"

article 1 Permit Framework
    fact authority administrative is present.
    obligation Regulator must grant Permit to Borrower.
    rule PermitRequiredForActivity
        If Regulator grants Permit to Borrower
        then Borrower may use Permit to Regulator.
