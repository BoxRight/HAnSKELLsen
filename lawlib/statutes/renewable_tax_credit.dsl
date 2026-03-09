law RenewableTaxCreditStatute
authority legislative
enacted 2025-06-01

import "../shared/renewable_project_shared.dsl"

article 1 Tax Credit Framework
    fact authority legislative is present.
    claim Developer may demand grant of RenewableTaxCredit from TaxAuthority.
    rule TaxCreditAfterCertification
        If Agency approves BiodiversityCertification to Developer
        then TaxAuthority must grant RenewableTaxCredit to Developer.
