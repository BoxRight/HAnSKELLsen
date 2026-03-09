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
    rule TaxCreditProductionEligibility
        If aboveThreshold production 10000
        then TaxAuthority must grant RenewableTaxCredit to Developer.
    rule TaxCreditFilingWindow
        If withinWindow filingDate 2025-06-01 2025-08-31
        then TaxAuthority must grant RenewableTaxCredit to Developer.
    rule TaxCreditProductionAndStorm
        If aboveThreshold production 10000 and asset InsuranceClaimFiled is present
        then TaxAuthority must grant RenewableTaxCredit to Developer.
