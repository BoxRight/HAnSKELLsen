law ProfessionalLicenseFramework
authority administrative
enacted 2025-01-15

import "../shared/commercial_shared.dsl"

article 1 Licensing
    fact authority administrative is present.
    obligation Regulator must grant License to Borrower.
    rule LicensedActivity
        If Regulator grants License to Borrower
        then Borrower may use License to Regulator.
